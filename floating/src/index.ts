import { Spectrum } from "spectrum-ts";
import { imessage } from "@spectrum-ts/imessage";
import { processMessages } from "./processor.ts";
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

// Individual operation failures are handled without replay by the processor.
// An iterator/provider failure remains fatal; the existing supervisor owns restart.
try {
  await processMessages(app.messages);
} catch {
  console.error("Photon: message_stream_failed");
  process.exitCode = 1;
  // SDK stop is not assumed cancellable; terminate after a bounded grace period.
  const shutdown = setTimeout(() => process.exit(1), 3_000);
  await app.stop().catch(() => {});
  clearTimeout(shutdown);
}
