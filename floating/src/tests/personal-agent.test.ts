import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PersonalAgent,type Incoming,type Destination} from '../personal-agent.ts';
const routing={allowed_sender:'+10000000001',bridge_number:'+10000000002'};
const now=Date.now();
function fixture(){
  const sent:string[]=[];const calls:string[]=[];
  const space:Destination={id:'dm-1',phone:routing.bridge_number,type:'dm',__platform:'imessage',send:async text=>{sent.push(text);return {id:'out-1'};}};
  const message:Incoming={id:'in-1',platform:'imessage',direction:'inbound',timestamp:new Date(now),sender:{id:routing.allowed_sender,__platform:'imessage',kind:'person'},content:{type:'text',text:'agent hello'}};
  let claimed=false;
  const agent=new PersonalAgent(routing,async(method,path,body)=>{
    calls.push(method+' '+path);
    if(path==='/requests')return {id:'a'.repeat(64),state:claimed?'sent':'done',reply:'Synthetic reply'};
    if(path.endsWith('/claim')){const result=!claimed;claimed=true;return {claimed:result};}
    return {};
  },async()=>{},()=>now);
  return {agent,space,message,sent,calls};
}
test('ordinary commands retain original route',async()=>{
 const f=fixture();f.message.content.text='query';assert.equal(await f.agent.handle(f.space,f.message),false);assert.equal(f.calls.length,0);
});
test('owner direct message produces once-only reply and receipt',async()=>{
 const f=fixture();assert.equal(await f.agent.handle(f.space,f.message),true);await f.agent.handle(f.space,f.message);
 assert.deepEqual(f.sent,['Synthetic reply']);assert(f.calls.some(x=>x.endsWith('/settle')));
});
test('unauthorized/group/outbound/missing IDs/line denied before broker',async()=>{
 for(const change of ['sender','group','outbound','id','space','line','timestamp','platform']){
  const f=fixture();
  if(change==='sender')f.message.sender!.id='+10000000003';
  if(change==='group')f.space.type='group';if(change==='outbound')f.message.direction='outbound';
  if(change==='id')f.message.id=undefined;if(change==='space')f.space.id=undefined;
  if(change==='line')f.space.phone=undefined;if(change==='timestamp')f.message.timestamp=new Date(now-86400001);
  if(change==='platform')f.message.platform='sms';
  assert.equal(await f.agent.handle(f.space,f.message),true);assert.equal(f.calls.length,0);assert.equal(f.sent.length,0);
 }
});
test('send failure records uncertain without retry',async()=>{
 const f=fixture();f.space.send=async()=>{throw Error('synthetic failure');};await f.agent.handle(f.space,f.message);
 assert.equal(f.calls.filter(x=>x.endsWith('/claim')).length,1);assert.equal(f.calls.filter(x=>x.endsWith('/settle')).length,1);
});
test('slow agent request never blocks ordinary task route or starts another model',async()=>{
 const f=fixture();let resolve!: (value: {})=>void;let count=0;
 const pending=new Promise<{}>(r=>{resolve=r;});
 const agent=new PersonalAgent(routing,async()=>{count++;return pending;},async()=>{},()=>now);
 assert.equal(agent.route(f.space,f.message),true);
 assert.equal(agent.route(f.space,{...f.message,content:{type:'text',text:'query'}}),false);
 assert.equal(agent.route(f.space,{...f.message,id:'in-2'}),true);
 assert.equal(count,1);resolve({});await new Promise(r=>setTimeout(r,0));
});
