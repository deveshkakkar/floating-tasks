import { Spectrum } from "spectrum-ts";
import { imessage } from "spectrum-ts/providers/imessage";
import { classifyMessage } from "./intent.ts";
import { queryActiveTasks } from "./query.ts";
import { queryArchivedTasks } from "./archive.ts";
import { restoreArchivedTask } from "./restore.ts";
import { completeTask } from "./complete.ts";
import { queryDailyTasks } from "./daily.ts";
import { HELP_MESSAGE } from "./help.ts";
import { requireSetting, validateCloudConfiguration } from "./config.ts";
import { mayHandleMessage } from "./message-policy.ts";

// Fail before opening a provider connection if deployment or sender identity is missing.
validateCloudConfiguration();
const allowedSender = requireSetting("PHOTON_ALLOWED_SENDER");
// Spectrum bridges a single agent loop to many messaging interfaces.
// Each provider in `providers` adds an interface (terminal TUI, iMessage, …).
// Docs: https://photon.codes/docs/spectrum-ts
const app = await Spectrum({
  projectId: requireSetting("PROJECT_ID"),
  projectSecret: requireSetting("PROJECT_SECRET"),
  providers: [
    // imessage
    imessage.config(),
  ],
});

// `app.messages` is an async iterable. Each tick yields a `space` (the
// conversation) and an inbound `message`. Reply by awaiting `space.send(...)`.
for await (const [space, message] of app.messages) {
  if (message.platform !== "imessage") continue;
  const sender = imessage(message).sender;
  if (!mayHandleMessage({
    platform: message.platform,
    direction: message.direction,
    sender,
    service: sender?.service,
  }, imessage(space).type, allowedSender)) continue;
  try {
    if (message.content.type === "text") {
      const intent = classifyMessage(message.content.text);
      if (intent.kind === "create") {
        await space.send(`Received: ${intent.text}. Use query to confirm it was saved.`);
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
  } catch {
    // Provider and transport failures must not log task text, tokens, or sender IDs.
    console.error("A message could not be processed. Check the provider and task-service connection.");
  }
}
