import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PersonalAgent,type Destination,type Incoming} from '../personal-agent.ts';
import {withTyping} from '../typing.ts';
const routing={allowed_sender:'+10000000001',bridge_number:'+10000000002'};
const tick=()=>new Promise<void>(r=>setTimeout(r,0));
function fixture(state='done'){
 const events:string[]=[];let release!:()=>void;
 const hold=new Promise<void>(r=>{release=r;});
 const space:Destination={id:'dm-owner',type:'dm',__platform:'imessage',phone:routing.bridge_number,
  startTyping:async()=>{events.push('start');},stopTyping:async()=>{events.push('stop');},
  send:async()=>{events.push('send');return{id:'sent'};}};
 const message:Incoming={id:'in-1',platform:'imessage',direction:'inbound',timestamp:new Date(),
  sender:{id:routing.allowed_sender,__platform:'imessage',kind:'person'},content:{type:'text',text:'agent hello'}};
 const calls:string[]=[];
 const agent=new PersonalAgent(routing,async(method,path)=>{
  calls.push(method+' '+path);
  if(path==='/requests')return{id:'a'.repeat(64),state,reply:'Done'};
  if(path==='/controls')return{id:'b'.repeat(64),state:'done',reply:'Ready'};
  if(method==='GET'){await hold;return{id:'a'.repeat(64),state:'done',reply:'Done'};}
  if(path.endsWith('/claim'))return{claimed:true};return{};
 },async()=>{},Date.now);
 return{agent,space,message,calls,events,release};
}
test('short response starts after admission, stops after send',async()=>{
 const f=fixture();await f.agent.handle(f.space,f.message);
 assert.deepEqual(f.events,['start','send','stop']);assert.equal(f.calls[0],'POST /requests');
});
test('long request retains lease, refreshes, and leaves task route responsive',async()=>{
 const f=fixture('running');const agent=f.agent.handle(f.space,f.message);
 await tick();assert.equal(f.events[0],'start');
 assert.equal(f.agent.route(f.space,{...f.message,content:{type:'text',text:'query'}}),false);
 assert(!f.events.includes('stop'));f.release();await agent;
 assert.deepEqual(f.events,['start','send','stop']);
 const pulses:string[]=[];
 await withTyping({startTyping:async()=>{pulses.push('start');},stopTyping:async()=>{pulses.push('stop');}},
  async()=>{await new Promise(r=>setTimeout(r,12));assert(!pulses.includes('stop'));},3);
 assert(pulses.filter(x=>x==='start').length>=2);assert.equal(pulses.at(-1),'stop');
});
test('failures and interrupted work stop typing',async()=>{
 const f=fixture('running');const work=f.agent.handle(f.space,f.message);await tick();
 f.release();await work;assert.equal(f.events.at(-1),'stop');
 const e:string[]=[];await assert.rejects(withTyping({startTyping:async()=>{e.push('start');},stopTyping:async()=>{e.push('stop');}},async()=>{throw Error('interrupted');}));
 assert.deepEqual(e,['start','stop']);
 const bad=fixture();bad.space.send=async()=>{bad.events.push('send-fail');throw Error('send failure');};
 await bad.agent.handle(bad.space,bad.message);assert.equal(bad.events.at(-1),'stop');
});
test('unauthorized and denied admission produce no typing',async()=>{
 const f=fixture();f.message.sender!.id='+10000000003';await f.agent.handle(f.space,f.message);
 assert.deepEqual(f.events,[]);assert.deepEqual(f.calls,[]);
 const g=fixture();const agent=new PersonalAgent(routing,async()=>({error:'denied'}));
 await agent.handle(g.space,g.message);assert.deepEqual(g.events,[]);
});
test('controls and other conversations do not inherit owner typing',async()=>{
 const f=fixture();f.message.content.text='agent status';await f.agent.handle(f.space,f.message);
 assert.deepEqual(f.events,['send']);
 const other=fixture();other.space.id='other-chat';other.message.sender!.id='+10000000003';
 await other.agent.handle(other.space,other.message);assert.deepEqual(other.events,[]);
});
test('stalled typing provider cannot hold request completion',async()=>{
 const never=new Promise<void>(()=>{});
 const events:string[]=[];
 const started=Date.now();
 await withTyping({startTyping:()=>never,stopTyping:async()=>{events.push('stop');}},
  async()=>{events.push('work');},3,15);
 assert.deepEqual(events,['work','stop']);
 assert(Date.now()-started<500);
});
test('late start is cleared again after work finishes',async()=>{
 let release!:()=>void;
 const held=new Promise<void>(resolve=>{release=resolve;});
 const events:string[]=[];
 await withTyping({startTyping:()=>held,stopTyping:async()=>{events.push('stop');}},
  async()=>{},3,10);
 release();await tick();
 assert.deepEqual(events,['stop','stop']);
});
