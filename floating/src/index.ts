import { Spectrum } from "spectrum-ts";
import { imessage } from "@spectrum-ts/imessage";
import { classifyMessage } from "./intent.ts";
import { queryActiveTasks } from "./query.ts";
import { queryArchivedTasks } from "./archive.ts";
import { restoreArchivedTask } from "./restore.ts";
import { completeTask } from "./complete.ts";
import { queryDailyTasks } from "./daily.ts";
import { HELP_MESSAGE } from "./help.ts";
// Spectrum bridges a single agent loop to many messaging interfaces.
// Each provider in `providers` adds an interface (terminal TUI, iMessage, …).
// Docs: https://photon.codes/docs/spectrum-ts
const app = await Spectrum({
  projectId: process.env.PROJECT_ID!,
  projectSecret: process.env.PROJECT_SECRET!,
  providers: [
    // imessage
    imessage.config(),
  ],
});

// `app.messages` is an async iterable. Each tick yields a `space` (the
// conversation) and an inbound `message`. Reply by awaiting `space.send(...)`.
for await (const [space, message] of app.messages) {
  if (message.direction === "outbound") continue;
  if (message.content.type === "text") {
    const intent = classifyMessage(message.content.text);
    if (intent.kind === "create") {
      await space.send(`Created: ${intent.text}`);
    } else if (intent.kind === "query") {
      await space.send(await queryActiveTasks());
    } else if (intent.kind === "daily") {
      await space.send(await queryDailyTasks());
    } else if (intent.kind === "archived") {
      await space.send(await queryArchivedTasks());
    } else if (intent.kind === "restore") {
      await space.send(await restoreArchivedTask(intent.target));
    } else if (intent.kind === "complete") {
      await space.send(await completeTask(intent.target));
    } else if (intent.kind === "help") {
      await space.send(HELP_MESSAGE);
    } else {
      await space.send(message.content.text);
    }
  }
}
