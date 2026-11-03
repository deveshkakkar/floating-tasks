import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
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
test('dedicated app routes bare messages and legacy-prefixed messages to agent',async()=>{
 for(const input of ['hello','agent hello']){
  const f=fixture();f.message.content.text=input;
  const agent=new PersonalAgent(routing,async(method,path)=>{
   f.calls.push(method+' '+path);
   if(path==='/requests')return{id:'a'.repeat(64),state:'done',reply:'Synthetic reply'};
   if(path.endsWith('/claim'))return{claimed:true};return{};
  },async()=>{},()=>now,true);
  assert.equal(await agent.handle(f.space,f.message),true);
  assert.deepEqual(f.sent,['Synthetic reply']);assert(f.calls.includes('POST /requests'));
 }
});
test('dedicated app sends bare status to deterministic control endpoint',async()=>{
 const f=fixture();f.message.content.text='status';const calls:string[]=[];
 const agent=new PersonalAgent(routing,async(method,path)=>{
  calls.push(path);
  if(path==='/controls')return{id:'b'.repeat(64),state:'done',reply:'Agent ready.'};
  if(path.endsWith('/claim'))return{claimed:true};return{};
 },async()=>{},()=>now,true);
 assert.equal(await agent.handle(f.space,f.message),true);
 assert(calls.includes('/controls'));assert(!calls.includes('/requests'));
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
test('slow admission keeps task routing responsive and orders the next admission',async()=>{
 const f=fixture();let resolve!: (value: {})=>void;let count=0;
 const pending=new Promise<{}>(r=>{resolve=r;});
 const agent=new PersonalAgent(routing,async()=>{count++;return pending;},async()=>{},()=>now);
 assert.equal(agent.route(f.space,f.message),true);
 assert.equal(agent.route(f.space,{...f.message,content:{type:'text',text:'query'}}),false);
 assert.equal(agent.route(f.space,{...f.message,id:'in-2'}),true);
 await new Promise(r=>setTimeout(r,0));assert.equal(count,1);
 resolve({id:'a'.repeat(64),state:'generation_failed'});await new Promise(r=>setTimeout(r,0));assert.equal(count,2);
});
test('fresh bridge polls durable A/B/C replies and sends each only once in order',async()=>{
 const sent:string[]=[];const ids=['a'.repeat(64),'b'.repeat(64),'c'.repeat(64)];let next=0;
 const agent=new PersonalAgent(routing,async(method,path)=>{
  if(path==='/requests/pending')return next<3?{id:ids[next],line:'shared',reply:'reply-'+next}:{};
  if(path.endsWith('/claim'))return{claimed:true};
  if(path.endsWith('/settle')){next++;return{ok:true};}
  return{};
 });
 const resolve=async(owner:string,line:string):Promise<Destination>=>{
  assert.equal(owner,routing.allowed_sender);assert.equal(line,'shared');
  return{id:'any;-;'+owner,type:'dm',__platform:'imessage',phone:line,
   send:async text=>{sent.push(text);return{id:'receipt'};}};
 };
 for(let i=0;i<4;i++)await agent.pollReplies(resolve);
 assert.deepEqual(sent,['reply-0','reply-1','reply-2']);
});
test('bridge serializes A/B/C admission despite delayed first broker response',async()=>{
 const f=fixture();const seen:string[]=[];let release!:(value:{id:string;state:string})=>void;
 const first=new Promise<{id:string;state:string}>(resolve=>{release=resolve;});
 const agent=new PersonalAgent(routing,async(method,path,body)=>{
  if(method==='POST'&&path==='/requests'){
   const label=(body as {text:string}).text;seen.push(label);
   return label==='A'?first:{id:label.toLowerCase().repeat(64),state:'generation_failed'};
  }
  return{};
 });
 for(const label of ['A','B','C'])agent.route(f.space,{...f.message,id:'in-'+label,content:{type:'text',text:'agent '+label}});
 await new Promise(r=>setTimeout(r,0));assert.deepEqual(seen,['A']);
 release({id:'a'.repeat(64),state:'generation_failed'});
 await new Promise(r=>setTimeout(r,0));assert.deepEqual(seen,['A','B','C']);
});
test('durable capacity rejection receives one claimed not-queued response',async()=>{
 const f=fixture();let sends=0;
 f.space.send=async text=>{sends++;assert.match(text,/not queued|could not be queued/i);return{id:'receipt'};};
 let claimed=false;
 const agent=new PersonalAgent(routing,async(_method,path)=>{
  if(path==='/requests')return{id:'a'.repeat(64),state:'rejected',reply:'Your message was not queued: limit reached.'};
  if(path.endsWith('/claim')){if(claimed)return{claimed:false};claimed=true;return{claimed:true};}
  return{};
 });
 assert.equal(await agent.handle(f.space,f.message),true);
 assert.equal(await agent.handle(f.space,f.message),true);assert.equal(sends,1);
});
test('retained-ledger capacity denial receives an actionable not-queued response',async()=>{
 const f=fixture();const agent=new PersonalAgent(routing,async()=>({error:'retained_capacity_reached'}));
 await agent.handle(f.space,f.message);assert.equal(f.sent.length,1);
 assert.match(f.sent[0]!,/not queued/i);
});
test('lost admission response uses stable identity readback without replay',async()=>{
 const f=fixture();let posts=0;let reads=0;
 const ident=createHash('sha256').update(JSON.stringify([routing.allowed_sender,routing.bridge_number,'dm-1','in-1'])).digest('hex');
 const agent=new PersonalAgent(routing,async(method,path)=>{
  if(method==='POST'&&path==='/requests'){posts++;throw Error('lost response');}
  if(method==='GET'&&path==='/requests/'+ident){reads++;return{id:ident,state:'generation_failed'};}
  return{};
 });
 await agent.handle(f.space,f.message);
 assert.equal(posts,1);assert.equal(reads,1);assert.deepEqual(f.sent,[]);
});
test('broker error after uncertain insert is read back, not treated as denial',async()=>{
 const f=fixture();let posts=0;let reads=0;
 const ident=createHash('sha256').update(JSON.stringify([routing.allowed_sender,routing.bridge_number,'dm-1','in-1'])).digest('hex');
 const agent=new PersonalAgent(routing,async(method,path)=>{
  if(method==='POST'&&path==='/requests'){posts++;return{error:'broker_error'};}
  if(method==='GET'&&path==='/requests/'+ident){reads++;return{id:ident,state:'generation_failed'};}
  return{};
 });
 await agent.handle(f.space,f.message);
 assert.equal(posts,1);assert.equal(reads,1);assert.deepEqual(f.sent,[]);
});
test('admission readback identity matches broker JSON for Unicode provider IDs',async()=>{
 const f=fixture();f.space.id='dm-☃';f.message.id='msg-😀';let path='';
 const agent=new PersonalAgent(routing,async(method,route)=>{
  if(method==='POST')throw Error('lost response');
  path=route;return{id:'ee2161767c9b11cd0c5d3b9f2f3973a690b6976de8282058890483d672b758a1',state:'generation_failed'};
 });
 await agent.handle(f.space,f.message);
 assert.equal(path,'/requests/ee2161767c9b11cd0c5d3b9f2f3973a690b6976de8282058890483d672b758a1');
});
test('unconfirmed admission is reported without asserting it was not queued',async()=>{
 const f=fixture();let posts=0;let reads=0;
 const agent=new PersonalAgent(routing,async(method,path)=>{
  if(method==='POST'&&path==='/requests'){posts++;throw Error('socket unavailable');}
  if(method==='GET'&&path.startsWith('/requests/')){reads++;return{error:'not_found'};}
  return{};
 });
 await agent.handle(f.space,f.message);
 assert.equal(posts,2);assert.equal(reads,2);
 assert.equal(f.sent.length,1);assert.match(f.sent[0]!,/could not confirm whether/i);
});
test('agent result can arrive after fifteen minutes of polling',async()=>{
 const f=fixture();let clock=now;let polls=0;let sends=0;
 const agent=new PersonalAgent(routing,async(method,path)=>{
  if(path==='/requests')return{id:'a'.repeat(64),state:'running'};
  if(method==='GET'&&path.endsWith('a'.repeat(64))){polls++;return clock-now>=900000
   ?{id:'a'.repeat(64),state:'done',reply:'Long task complete'}:{id:'a'.repeat(64),state:'running'};}
  if(path.endsWith('/claim'))return{claimed:true};
  if(path.endsWith('/settle'))return{ok:true};
  return{};
 },async()=>{clock+=60000;},()=>clock);
 f.space.send=async text=>{assert.equal(text,'Long task complete');sends++;return{id:'receipt'};};
 await agent.handle(f.space,f.message);
 assert.equal(polls,15);assert.equal(sends,1);
});
test('authenticated cloud shared-pool line uses installed SDK sentinel',async()=>{
 const f=fixture();f.space.phone='shared';await f.agent.handle(f.space,f.message);assert.equal(f.sent.length,1);
});

test('weekly uses fixed owner and claims before one send; repeated poll cannot replay',async()=>{
 const events:string[]=[];let state='ready';
 const agent=new PersonalAgent(routing,async(method,path,body)=>{
  events.push(path);
  if(path==='/weekly/pending')return state==='ready'?{id:'weekly-test',reply:'Weekly test.'}:{};
  if(path==='/weekly/claim'){if(state!=='ready')return {claimed:false};state='sending';return {claimed:true};}
  if(path==='/weekly/settle'){assert.equal((body as {accepted:boolean}).accepted,true);state='sent';}
  return {};
 });
 const resolve=async(owner:string,line:string)=>{assert.equal(owner,routing.allowed_sender);assert.equal(line,routing.bridge_number);
  return {id:'any;-;'+owner,type:'dm',__platform:'imessage',phone:'shared',send:async(text:string)=>{
   assert.equal(state,'sending');events.push('send');assert.equal(text,'Weekly test.');return {id:'receipt'};
  }};
 };
 await agent.pollWeekly(resolve);await agent.pollWeekly(resolve);
 assert.equal(events.filter(x=>x==='send').length,1);assert.equal(state,'sent');
});
test('weekly destination failures cannot claim or send',async()=>{
 for(const invalid of ['recipient','line','group']){
  let claims=0;let sends=0;
  const agent=new PersonalAgent(routing,async(method,path)=>{
   if(path==='/weekly/pending')return {id:'week',reply:'Hello'};
   claims++;return {};
  });
  await agent.pollWeekly(async()=>({id:invalid==='recipient'?'wrong':'any;-;'+routing.allowed_sender,
   type:invalid==='group'?'group':'dm',__platform:'imessage',phone:invalid==='line'?'wrong':'shared',
   send:async()=>{sends++;return {};}}));
  assert.equal(claims,0);assert.equal(sends,0);
 }
});
test('weekly failure or undefined receipt is uncertain, never accepted',async()=>{
 for(const failure of [true,false]){
  let accepted:unknown;
  const agent=new PersonalAgent(routing,async(method,path,body)=>{
   if(path==='/weekly/pending')return {id:'week',reply:'Hello'};
   if(path==='/weekly/claim')return {claimed:true};
   accepted=(body as {accepted:unknown}).accepted;return {};
  });
  await agent.pollWeekly(async()=>({id:'any;-;'+routing.allowed_sender,type:'dm',__platform:'imessage',phone:'shared',
   send:async()=>{if(failure)throw Error('failure');return undefined;}}));
  assert.equal(accepted,false);
 }
});
test('weekly pending send shares admission guard with direct personal requests',async()=>{
 const f=fixture();let release!:(value:unknown)=>void;
 const agent=new PersonalAgent(routing,async(method,path)=>{
  if(path==='/weekly/pending')return {id:'week',reply:'Hello'};
  if(path==='/weekly/claim')return {claimed:true};return {};
 });
 const polling=agent.pollWeekly(async()=>({id:'any;-;'+routing.allowed_sender,type:'dm',__platform:'imessage',phone:'shared',
  send:()=>new Promise(r=>{release=r;})}));
 await new Promise(r=>setTimeout(r,0));
 assert.equal(agent.route(f.space,f.message),true);
 assert.equal(agent.route(f.space,{...f.message,content:{type:'text',text:'query'}}),false);
 release({id:'receipt'});await polling;
});

test('status bypasses slow generation and calls deterministic owner control endpoint',async()=>{
 const f=fixture();const calls:string[]=[];let finish!: (result:{})=>void;
 const agent=new PersonalAgent(routing,async(method,path)=>{
  calls.push(path);
  if(path==='/requests')return new Promise<{}>(r=>{finish=r;});
  if(path==='/controls')return {id:'b'.repeat(64),state:'done',reply:'Agent working.'};
  if(path.endsWith('/claim'))return {claimed:true};return {};
 });
 agent.route(f.space,f.message);
 agent.route(f.space,{...f.message,id:'status-1',content:{type:'text',text:'agent status'}});
 await new Promise(r=>setTimeout(r,10));
 assert.equal(calls.filter(x=>x==='/requests').length,1);
 assert.equal(calls.filter(x=>x==='/controls').length,1);assert.deepEqual(f.sent,['Agent working.']);
 finish({});await new Promise(r=>setTimeout(r,0));
});
test('control and direct replies share a bounded sequential delivery gate',async()=>{
 const f=fixture();let finishGeneration!:(result:{id:string;state:string;reply:string})=>void;
 let finishSend!:(result:unknown)=>void;let sending=0;let maximum=0;const sent:string[]=[];
 f.space.send=async text=>{sending++;maximum=Math.max(maximum,sending);sent.push(text);
  if(text==='Paused.')await new Promise(r=>{finishSend=r;});sending--;return {id:'receipt'};
 };
 const agent=new PersonalAgent(routing,async(method,path)=>{
  if(path==='/requests')return new Promise(r=>{finishGeneration=r;});
  if(path==='/controls')return {id:'b'.repeat(64),state:'done',reply:'Paused.'};
  if(path.endsWith('/claim'))return {claimed:true};return {};
 });
 agent.route(f.space,f.message);agent.route(f.space,{...f.message,id:'pause',content:{type:'text',text:'agent pause background'}});
 await new Promise(r=>setTimeout(r,10));
 finishGeneration({id:'a'.repeat(64),state:'done',reply:'Work complete.'});
 await new Promise(r=>setTimeout(r,10));assert.deepEqual(sent,['Paused.']);
 finishSend({});await new Promise(r=>setTimeout(r,10));assert.deepEqual(sent,['Paused.','Work complete.']);assert.equal(maximum,1);
});
test('control owner gates are identical and nonexact commands use model route',async()=>{
 const f=fixture();f.message.sender!.id='+10000000003';f.message.content.text='agent pause background';
 await f.agent.handle(f.space,f.message);assert.equal(f.calls.length,0);
 const good=fixture();good.message.content.text='agent status of my project';await good.agent.handle(good.space,good.message);
 assert(good.calls.includes('POST /requests'));assert(!good.calls.includes('POST /controls'));
});

test('rapid pause then resume admits both in order while first provider send waits',async()=>{
 const f=fixture();const admitted:string[]=[];const sent:string[]=[];let paused=false;let release!:(value:unknown)=>void;
 f.space.send=async text=>{sent.push(text);if(text==='pause background')await new Promise(r=>{release=r;});return{id:'receipt'};};
 const agent=new PersonalAgent(routing,async(method,path,body)=>{
  if(path==='/controls'){
   const command=(body as {text:string}).text;admitted.push(command);paused=command==='pause background';
   return{id:(paused?'b':'c').repeat(64),state:'done',reply:command};
  }
  if(path.endsWith('/claim'))return{claimed:true};return {};
 });
 agent.route(f.space,{...f.message,id:'pause',content:{type:'text',text:'agent pause background'}});
 agent.route(f.space,{...f.message,id:'resume',content:{type:'text',text:'agent resume background'}});
 await new Promise(r=>setTimeout(r,10));
 assert.deepEqual(admitted,['pause background','resume background']);assert.equal(paused,false);
 assert.deepEqual(sent,['pause background']);release({});await new Promise(r=>setTimeout(r,10));
 assert.deepEqual(sent,['pause background','resume background']);
});
