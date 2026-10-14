import { Spectrum } from "spectrum-ts";
import { imessage } from "@spectrum-ts/imessage";
import { configuredPersonalAgent, callBroker } from "./personal-agent.ts";

const personalAgent = configuredPersonalAgent(true);
if ((await callBroker("GET", "/health")).ok !== true) throw Error("personal_agent_broker_unavailable");

const app = await Spectrum({
  projectId: process.env.PROJECT_ID!,
  projectSecret: process.env.PROJECT_SECRET!,
  providers: [imessage.config()],
});

const ownerPlatform=imessage(app);
const weeklyPoll=setInterval(()=>void personalAgent.pollWeekly((owner,line)=>
  ownerPlatform.space.get("any;-;"+owner,{phone:line})),15000);
weeklyPoll.unref();

for await (const [space,message] of app.messages) {
  if (message.direction === "outbound") continue;
  personalAgent.route(space,message);
}
