import { request } from "node:http";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { withTyping } from "./typing.ts";

type Routing = { allowed_sender: string; bridge_number: string };
export type Incoming = {
  id?: string; platform?: string; direction?: string; timestamp?: Date;
  sender?: { id: string; __platform?: string; kind?: string };
  content: { type: string; text?: string };
};
export type Destination = {
  id?: string; __platform?: string; type?: string; phone?: string;
  send(text: string): Promise<unknown>;
  startTyping?: () => Promise<void>;
  stopTyping?: () => Promise<void>;
};
type Result = { id?: string; state?: string; reply?: string; line?: string; error?: string; claimed?: boolean; ok?: boolean };
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
  private activeRequests = 0;
  private pollingReplies = false;
  private controlInFlight = false;
  private deliveryTail: Promise<void> = Promise.resolve();
  private queuedDeliveries = 0;
  private queuedControls = 0;
  private controlAdmissionTail: Promise<void> = Promise.resolve();
  private requestAdmissionTail: Promise<void> = Promise.resolve();
  constructor(private routing: Routing, private call: Call = callBroker,
    private sleep = (ms: number) => new Promise<void>(r=>setTimeout(r,ms)),
    private now = Date.now, private dedicated = false) {}

  private requestText(text: string): string | undefined {
    const value=text.trim();
    if(!this.dedicated && !/^agent(?:\s|$)/i.test(value))return undefined;
    return /^agent(?:\s|$)/i.test(value) ? value.slice(5).trim() : value;
  }

  private async admitRequest(body: {sender:string;line:string;spaceId:string;messageId:string;text:string}): Promise<Result> {
    const identity=JSON.stringify([body.sender,body.line,body.spaceId,body.messageId])
      .replace(/[\u007f-\uffff]/g,c=>"\\u"+c.charCodeAt(0).toString(16).padStart(4,"0"));
    const ident=createHash("sha256").update(identity).digest("hex");
    const definiteDenial=(value:Result)=>["agent_deploying","retained_capacity_reached","identity_denied",
      "invalid_request","missing_message_identity","invalid_text","invalid_body"].includes(value.error??"");
    try {
      const first=await this.call("POST","/requests",body);
      if(first.id || definiteDenial(first))return first;
    } catch {}
    // Admission is an idempotent ledger insert, not a model execution. Read
    // back before one bounded retry; the same provider identity cannot dispatch
    // a second turn even if the first POST committed before its reply was lost.
    try {
      const found=await this.call("GET","/requests/"+ident);
      if(found.id===ident)return found;
    } catch {}
    try {
      const second=await this.call("POST","/requests",body);
      if(second.id || definiteDenial(second))return second;
    } catch {}
    try {
      const found=await this.call("GET","/requests/"+ident);
      if(found.id===ident)return found;
    } catch {}
    return {error:"admission_unconfirmed"};
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

  private async notifyNotQueued(space: Destination, reason?: string): Promise<void> {
    const message=reason==="request_budget_reached" ? "Your message was not queued: the agent request limit is reached. Please try later."
      : reason==="retained_capacity_reached" ? "Your message was not queued: the agent ledger needs operator attention."
      : reason==="agent_deploying" ? "Your message was not queued while the agent is updating. Please try again after it returns."
      : "I could not confirm whether your message was queued. Check agent status before resending.";
    const previous=this.deliveryTail;
    let release!:()=>void;
    this.deliveryTail=new Promise<void>(resolve=>{release=resolve;});
    try {
      await previous;
      if(this.pending.size)throw Error("previous_send_uncertain");
      const sending=Promise.resolve().then(()=>space.send(message));
      this.pending.add(sending);
      void sending.then(()=>this.pending.delete(sending),()=>this.pending.delete(sending));
      let timer:ReturnType<typeof setTimeout>|undefined;
      const receipt=await Promise.race([sending,new Promise((_,reject)=>{
        timer=setTimeout(()=>reject(Error("send_uncertain")),15000);
      })]).finally(()=>{if(timer)clearTimeout(timer);});
      if(typeof receipt!=="object" || receipt===null || typeof (receipt as {id?:unknown}).id!=="string")
        throw Error("send_not_confirmed");
    } catch {console.error("personal_agent: admission_notice_uncertain");}
    finally {release();}
  }

  async pollWeekly(resolveOwner: (owner: string, line: string) => Promise<Destination>): Promise<void> {
    if(this.activeRequests || this.controlInFlight || this.pending.size)return;
    try {
      const result=await this.call("GET","/weekly/pending");
      if(!result.id || typeof result.reply!=="string" || !result.reply.trim())return;
      const space=await resolveOwner(this.routing.allowed_sender,this.routing.bridge_number);
      if(space.id!=="any;-;"+this.routing.allowed_sender || space.__platform!=="imessage" || space.type!=="dm"
        || ![this.routing.bridge_number,"shared"].includes(space.phone??""))throw Error("weekly_destination_denied");
      await this.deliver(space,result,"/weekly");
    } catch {console.error("personal_agent: weekly_delivery_uncertain");}
  }

  async pollReplies(resolveOwner: (owner: string, line: string) => Promise<Destination>): Promise<void> {
    if(this.pollingReplies || this.pending.size)return;
    this.pollingReplies=true;
    try {
      const result=await this.call("GET","/requests/pending");
      if(!result.id || typeof result.reply!=="string" || !result.reply.trim())return;
      if(![this.routing.bridge_number,"shared"].includes(result.line??""))throw Error("reply_line_denied");
      const space=await resolveOwner(this.routing.allowed_sender,result.line!);
      if(space.id!=="any;-;"+this.routing.allowed_sender || space.__platform!=="imessage" || space.type!=="dm"
        || ![this.routing.bridge_number,"shared"].includes(space.phone??""))throw Error("reply_destination_denied");
      await this.deliver(space,result,"/requests");
    } catch {console.error("personal_agent: reply_delivery_uncertain");}
    finally {this.pollingReplies=false;}
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
    this.activeRequests++;
    void this.handle(space,message).finally(()=>{this.activeRequests--;});
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
    let ident: string|undefined;
    try {
      const requestBody={sender:message.sender.id,line:space.phone!,
        spaceId:space.id!,messageId:message.id!,text:body};
      let result:Result;
      if(base==="/controls"){
        const admission=this.controlAdmissionTail.then(()=>this.call("POST",base,requestBody));
        this.controlAdmissionTail=admission.then(()=>undefined,()=>undefined);
        result=await admission;
      } else {
        const admission=this.requestAdmissionTail.then(()=>this.admitRequest(requestBody));
        this.requestAdmissionTail=admission.then(()=>undefined,()=>undefined);
        result=await admission;
      }
      ident=result.id;
      if(result.error || !ident){
        console.error("personal_agent: admission_denied");
        if(base==="/requests")await this.notifyNotQueued(space,result.error);
        return true;
      }
      const complete=async()=>{
        const deadline=this.now()+AGENT_RESULT_TIMEOUT_MS;
        while(result.state==="queued" || result.state==="running"){
          if(this.now()>=deadline){console.error("personal_agent: result_uncertain");return;}
          await this.sleep(1000);result=await this.call("GET",base+"/"+ident);
        }
        if(!["done","rejected"].includes(result.state??"") || typeof result.reply!=="string" || !result.reply.trim())return;
        await this.deliver(space,result,base);
      };
      if(base==="/requests")await withTyping(space,complete);
      else await complete();
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
