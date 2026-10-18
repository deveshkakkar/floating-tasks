import { request } from "node:http";
import { readFileSync } from "node:fs";

type Routing = { allowed_sender: string; bridge_number: string };
export type Incoming = {
  id?: string; platform?: string; direction?: string; timestamp?: Date;
  sender?: { id: string; __platform?: string; kind?: string };
  content: { type: string; text?: string };
};
export type Destination = {
  id?: string; __platform?: string; type?: string; phone?: string;
  send(text: string): Promise<unknown>;
};
type Result = { id?: string; state?: string; reply?: string; error?: string; claimed?: boolean; ok?: boolean };
type Call = (method: string, path: string, body?: unknown) => Promise<Result>;
const SOCKET = "/run/personal-agent/socket/broker.sock";
const AGENT_RESULT_TIMEOUT_MS = 960000;

export function callBroker(method: string, path: string, body?: unknown): Promise<Result> {
  return new Promise((resolve,reject) => {
    const raw = body === undefined ? undefined : JSON.stringify(body);
    const req = request({socketPath:SOCKET,path,method,headers:raw === undefined ? {} : {
      "Content-Type":"application/json","Content-Length":Buffer.byteLength(raw),
    }}, res => {
      res.setEncoding("utf8");
      let text = "";
      res.on("data", chunk => {text += chunk;if(text.length>65536){req.destroy(Error("broker_response_capacity"));}});
      res.on("end", () => {
        try {resolve(JSON.parse(text));} catch {reject(Error("invalid_broker_response"));}
      });
      res.on("error",reject);
    });
    req.setTimeout(5000,()=>req.destroy(Error("broker_timeout")));
    req.on("error",reject);req.end(raw);
  });
}

export class PersonalAgent {
  private pending = new Set<Promise<unknown>>();
  private inFlight = false;
  private controlInFlight = false;
  private deliveryTail: Promise<void> = Promise.resolve();
  private queuedDeliveries = 0;
  private queuedControls = 0;
  private controlAdmissionTail: Promise<void> = Promise.resolve();
  constructor(private routing: Routing, private call: Call = callBroker,
    private sleep = (ms: number) => new Promise<void>(r=>setTimeout(r,ms)),
    private now = Date.now, private dedicated = false) {}

  private requestText(text: string): string | undefined {
    const value=text.trim();
    if(!this.dedicated && !/^agent(?:\s|$)/i.test(value))return undefined;
    return /^agent(?:\s|$)/i.test(value) ? value.slice(5).trim() : value;
  }

  private async deliver(space: Destination, result: Result, base: string): Promise<void> {
    if(this.queuedDeliveries>=5)throw Error("send_capacity_busy");
    this.queuedDeliveries++;
    const previous=this.deliveryTail;
    let release!:()=>void;
    this.deliveryTail=new Promise<void>(resolve=>{release=resolve;});
    try {
      await previous;
      if(this.pending.size)throw Error("previous_send_uncertain");
      const weekly=base==="/weekly";
      const claimPath=weekly?"/weekly/claim":base+"/"+result.id+"/claim";
      if(!(await this.call("POST",claimPath,weekly?{id:result.id}:undefined)).claimed)return;
      let accepted=false;
      let timer:ReturnType<typeof setTimeout>|undefined;
      try {
        const sending=Promise.resolve().then(()=>space.send(result.reply!.slice(0,15900)));
        this.pending.add(sending);
        void sending.then(()=>this.pending.delete(sending),()=>this.pending.delete(sending));
        const receipt=await Promise.race([sending,new Promise((_,reject)=>{
          timer=setTimeout(()=>reject(Error("send_uncertain")),15000);
        })]);
        accepted=typeof receipt==="object" && receipt!==null && typeof (receipt as {id?:unknown}).id==="string";
      } finally {
        if(timer)clearTimeout(timer);
        await this.call("POST",weekly?"/weekly/settle":base+"/"+result.id+"/settle",
          weekly?{id:result.id,accepted}:{accepted});
      }
    } finally {this.queuedDeliveries--;release();}
  }

  async pollWeekly(resolveOwner: (owner: string, line: string) => Promise<Destination>): Promise<void> {
    if(this.inFlight || this.controlInFlight || this.pending.size)return;
    this.inFlight=true;
    try {
      const result=await this.call("GET","/weekly/pending");
      if(!result.id || typeof result.reply!=="string" || !result.reply.trim())return;
      const space=await resolveOwner(this.routing.allowed_sender,this.routing.bridge_number);
      if(space.id!=="any;-;"+this.routing.allowed_sender || space.__platform!=="imessage" || space.type!=="dm"
        || ![this.routing.bridge_number,"shared"].includes(space.phone??""))throw Error("weekly_destination_denied");
      await this.deliver(space,result,"/weekly");
    } catch {console.error("personal_agent: weekly_delivery_uncertain");}
    finally {this.inFlight=false;}
  }

  route(space: Destination, message: Incoming): boolean {
    const text=message.content.type==="text" ? message.content.text : undefined;
    if(typeof text!=="string")return false;
    const body=this.requestText(text);
    if(body===undefined)return false;
    const command=body.toLowerCase();
    if(["status","pause background","resume background"].includes(command)){
      if(this.queuedControls>=4){console.error("personal_agent: control_admission_capacity");return true;}
      this.queuedControls++;
      this.controlInFlight=true;
      void this.handle(space,message).finally(()=>{this.queuedControls--;this.controlInFlight=this.queuedControls>0;});
      return true;
    }
    if(this.inFlight)return true;
    this.inFlight=true;
    void this.handle(space,message).finally(()=>{this.inFlight=false;});
    return true;
  }

  async handle(space: Destination, message: Incoming): Promise<boolean> {
    const text = message.content.type === "text" ? message.content.text : undefined;
    if(typeof text !== "string")return false;
    const body=this.requestText(text);
    if(body===undefined)return false;
    if(message.direction!=="inbound" || message.platform!=="imessage" || space.__platform!=="imessage"
      || space.type!=="dm" || message.sender?.__platform!=="imessage" || message.sender.kind==="agent"
      || message.sender.id!==this.routing.allowed_sender || ![this.routing.bridge_number,"shared"].includes(space.phone??"")
      || !space.id || !message.id || !(message.timestamp instanceof Date)
      || !Number.isFinite(message.timestamp.getTime()) || this.now()-message.timestamp.getTime()>86400000
      || message.timestamp.getTime()-this.now()>300000 || text.length>4096)return true;
    if(!body)return true;
    const base=["status","pause background","resume background"].includes(body.toLowerCase())?"/controls":"/requests";
    if(this.pending.size && base!=="/controls"){console.error("personal_agent: send_capacity_busy");return true;}
    let ident: string|undefined;
    try {
      const requestBody={sender:message.sender.id,line:space.phone,
        spaceId:space.id,messageId:message.id,text:body};
      let result:Result;
      if(base==="/controls"){
        const admission=this.controlAdmissionTail.then(()=>this.call("POST",base,requestBody));
        this.controlAdmissionTail=admission.then(()=>undefined,()=>undefined);
        result=await admission;
      } else result=await this.call("POST",base,requestBody);
      ident=result.id;
      if(result.error || !ident){console.error("personal_agent: admission_denied");return true;}
      const deadline=this.now()+AGENT_RESULT_TIMEOUT_MS;
      while(result.state==="queued" || result.state==="running"){
        if(this.now()>=deadline){console.error("personal_agent: result_uncertain");return true;}
        await this.sleep(1000);result=await this.call("GET",base+"/"+ident);
      }
      if(result.state!=="done" || typeof result.reply!=="string" || !result.reply.trim())return true;
      await this.deliver(space,result,base);
    } catch {
      console.error("personal_agent: request_or_send_uncertain");
    }
    return true;
  }
}

export function configuredPersonalAgent(dedicated = false): PersonalAgent {
  const routing=JSON.parse(readFileSync("/run/personal-agent/routing.json","utf8")) as Routing;
  if(!/^\+1\d{10}$/.test(routing.allowed_sender) || !/^\+1\d{10}$/.test(routing.bridge_number)){
    throw Error("personal_agent_routing_missing");
  }
  return new PersonalAgent(routing,callBroker,undefined,undefined,dedicated);
}
