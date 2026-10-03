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
  constructor(private routing: Routing, private call: Call = callBroker,
    private sleep = (ms: number) => new Promise<void>(r=>setTimeout(r,ms)),
    private now = Date.now) {}

  route(space: Destination, message: Incoming): boolean {
    const text=message.content.type==="text" ? message.content.text : undefined;
    if(typeof text!=="string" || !/^agent(?:\s|$)/i.test(text.trimStart()))return false;
    if(this.inFlight)return true;
    this.inFlight=true;
    void this.handle(space,message).finally(()=>{this.inFlight=false;});
    return true;
  }

  async handle(space: Destination, message: Incoming): Promise<boolean> {
    const text = message.content.type === "text" ? message.content.text : undefined;
    if(typeof text !== "string" || !/^agent(?:\s|$)/i.test(text.trimStart()))return false;
    if(message.direction!=="inbound" || message.platform!=="imessage" || space.__platform!=="imessage"
      || space.type!=="dm" || message.sender?.__platform!=="imessage" || message.sender.kind==="agent"
      || message.sender.id!==this.routing.allowed_sender || ![this.routing.bridge_number,"shared"].includes(space.phone??"")
      || !space.id || !message.id || !(message.timestamp instanceof Date)
      || !Number.isFinite(message.timestamp.getTime()) || this.now()-message.timestamp.getTime()>86400000
      || message.timestamp.getTime()-this.now()>300000 || text.length>4096)return true;
    const body=text.trim().slice(5).trim();
    if(!body)return true;
    if(this.pending.size){console.error("personal_agent: send_capacity_busy");return true;}
    let ident: string|undefined;
    try {
      let result=await this.call("POST","/requests",{sender:message.sender.id,line:space.phone,
        spaceId:space.id,messageId:message.id,text:body});
      ident=result.id;
      if(result.error || !ident){console.error("personal_agent: admission_denied");return true;}
      const deadline=this.now()+215000;
      while(result.state==="queued" || result.state==="running"){
        if(this.now()>=deadline){console.error("personal_agent: result_uncertain");return true;}
        await this.sleep(1000);result=await this.call("GET","/requests/"+ident);
      }
      if(result.state!=="done" || typeof result.reply!=="string" || !result.reply.trim())return true;
      const claimed=await this.call("POST","/requests/"+ident+"/claim");
      if(!claimed.claimed)return true;
      // Persist send-start before the uncancellable provider call. Never replay
      // a started/uncertain send after restart or duplicate inbound delivery.
      let accepted=false;
      let timer: ReturnType<typeof setTimeout>|undefined;
      try {
        const sending=Promise.resolve().then(()=>space.send(result.reply!.slice(0,15900)));
        this.pending.add(sending);
        void sending.then(()=>this.pending.delete(sending),()=>this.pending.delete(sending));
        await Promise.race([sending,new Promise((_,reject)=>{
          timer=setTimeout(()=>reject(Error("send_uncertain")),15000);
        })]);
        accepted=true;
      } finally {
        if(timer)clearTimeout(timer);
        await this.call("POST","/requests/"+ident+"/settle",{accepted});
      }
    } catch {
      console.error("personal_agent: request_or_send_uncertain");
    }
    return true;
  }
}

export function configuredPersonalAgent(): PersonalAgent {
  const routing=JSON.parse(readFileSync("/run/personal-agent/routing.json","utf8")) as Routing;
  if(!/^\+1\d{10}$/.test(routing.allowed_sender) || !/^\+1\d{10}$/.test(routing.bridge_number)){
    throw Error("personal_agent_routing_missing");
  }
  return new PersonalAgent(routing);
}
