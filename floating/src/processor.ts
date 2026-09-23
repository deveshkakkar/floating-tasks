import { classifyMessage } from "./intent.ts";
import { queryActiveTasks } from "./query.ts";
import { queryArchivedTasks } from "./archive.ts";
import { restoreArchivedTask } from "./restore.ts";
import { completeTask } from "./complete.ts";
import { queryDailyTasks } from "./daily.ts";
import { HELP_MESSAGE } from "./help.ts";
import { deadline, MESSAGE_MS } from "./request.ts";

export type Incoming = { direction?: string; content: { type: string; text?: string } };
export type Destination = { send: (text: string) => Promise<unknown> };
export type Event = "message_failed" | "send_failed_or_uncertain" | "send_capacity_exhausted" | "message_too_large";
export const MAX_PENDING_SENDS = 2;
export const SEND_MS = 15_000;

export async function replyFor(text: string, signal: AbortSignal): Promise<string> {
  const intent = classifyMessage(text);
  switch (intent.kind) {
    case "create": return `Received: ${intent.text}\nCreation is handled separately and is not yet confirmed. Use query to check.`;
    case "query": return queryActiveTasks(signal);
    case "daily": return queryDailyTasks(signal);
    case "archived": return queryArchivedTasks(signal);
    case "restore": return restoreArchivedTask(intent.target, signal);
    case "complete": return completeTask(intent.target, signal);
    case "help": return HELP_MESSAGE;
    default: return text;
  }
}

/** Sequential processing preserves mutation order. No application-level queue/retry. */
export class Processor {
  private readonly pending = new Set<Promise<unknown>>();
  constructor(
    private readonly respond = replyFor,
    private readonly report: (event: Event) => void = (event) => console.error(`Photon: ${event}`),
    private readonly messageMs = MESSAGE_MS,
    private readonly sendMs = SEND_MS,
  ) {}

  get pendingSends(): number { return this.pending.size; }

  async handle(space: Destination, message: Incoming): Promise<void> {
    if (message.direction === "outbound" || message.content.type !== "text" || typeof message.content.text !== "string") return;
    if (message.content.text.length > 4096) { this.report("message_too_large"); return; }
    // Never initiate another mutation when both uncancellable reply slots are busy.
    if (this.pending.size >= MAX_PENDING_SENDS) { this.report("send_capacity_exhausted"); return; }
    let reply: string;
    try {
      reply = await deadline((signal) => this.respond(message.content.text!, signal), this.messageMs);
    } catch {
      this.report("message_failed");
      reply = "This request could not be confirmed. Check task state before trying again.";
    }
    // Protect the provider and retained promises from large upstream response text.
    if (reply.length > 16_000) reply = reply.slice(0, 15_900) + "\n[Reply truncated]";
    const sending = Promise.resolve().then(() => space.send(reply));
    this.pending.add(sending);
    const release = () => { this.pending.delete(sending); };
    void sending.then(release, release);
    try {
      // Timeout bounds waiting, not the underlying SDK call. Keep its slot until settled.
      await deadline(() => sending, this.sendMs);
    } catch {
      this.report("send_failed_or_uncertain");
    }
  }
}

export async function processMessages(messages: AsyncIterable<readonly [Destination, Incoming]>, processor = new Processor()): Promise<void> {
  for await (const [space, message] of messages) {
    await processor.handle(space, message);
  }
}
