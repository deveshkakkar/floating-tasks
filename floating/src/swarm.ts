/** Read-only Swarm routing: exact sender + direct-message gate before any file read. */
import { constants } from "node:fs";
import { open } from "node:fs/promises";
import { isAbsolute } from "node:path";

export type SwarmMessage = {
  direction?: string; platform?: string;
  sender?: { id: string; __platform: string; kind?: string };
  content: { type: string; text?: string };
};
export type SwarmSpace = { type?: string; __platform?: string };
type Health = { observed_at: string | null; canvas_active: boolean | null;
  running_conversations: number | null; active_worker_guard_units: number | null;
  failed_worker_guard_units: number | null };
type Task = { kind: "coding" | "batch"; id: string; runtime: string; outcome: string;
  duration_seconds: number | null; fake: boolean | null };
export type Snapshot = { schema_version: 1; producer: "swarm-readonly-status-v1";
  published_at: string; max_age_seconds: 120; health: Health;
  tasks_observed_at: string | null; inventory_complete: boolean; tasks: Task[] };
const MAX_BYTES = 256 * 1024;
const HELP = "Read-only Swarm commands: swarm status; swarm result <coding|batch> <task-id>. Job submission and service control are unavailable.";
const OUTCOMES = new Set(["completed", "interrupted", "deadline", "observation_failed", "stopped_without_completion",
  "teardown_unconfirmed", "transport_completed; acceptance_unknown", "unknown"]);
const STATES = new Set(["active", "stopped", "failed", "unknown"]);
const ID = /^[a-z][a-z0-9-]{0,47}$/;
const isObject = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const exact = (value: Record<string, unknown>, keys: string[]) => Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
const nullableCount = (value: unknown) => value === null || (typeof value === "number" && Number.isSafeInteger(value) && value >= 0);
const nullableBool = (value: unknown) => value === null || typeof value === "boolean";
const validTime = (value: unknown) => value === null || (typeof value === "string" && /^\d{4}-\d\d-\d\dT.*(?:Z|\+00:00)$/.test(value) && Number.isFinite(Date.parse(value)));

export function parseSnapshot(raw: string): Snapshot {
  if (Buffer.byteLength(raw) > MAX_BYTES) throw Error("Snapshot too large");
  const value: unknown = JSON.parse(raw);
  if (!isObject(value) || !exact(value, ["schema_version", "producer", "published_at", "max_age_seconds", "health", "tasks_observed_at", "inventory_complete", "tasks"])
      || value.schema_version !== 1 || value.producer !== "swarm-readonly-status-v1" || value.max_age_seconds !== 120
      || typeof value.published_at !== "string" || !validTime(value.published_at) || !validTime(value.tasks_observed_at)
      || typeof value.inventory_complete !== "boolean" || !Array.isArray(value.tasks) || value.tasks.length > 400) throw Error("Invalid snapshot");
  const health = value.health;
  if (!isObject(health) || !exact(health, ["observed_at", "canvas_active", "running_conversations", "active_worker_guard_units", "failed_worker_guard_units"])
      || !validTime(health.observed_at) || !nullableBool(health.canvas_active)
      || ![health.running_conversations, health.active_worker_guard_units, health.failed_worker_guard_units].every(nullableCount)) throw Error("Invalid health");
  const seen = new Set<string>();
  for (const task of value.tasks) {
    if (!isObject(task) || !exact(task, ["kind", "id", "runtime", "outcome", "duration_seconds", "fake"])
        || typeof task.kind !== "string" || !["coding", "batch"].includes(task.kind) || typeof task.id !== "string" || !ID.test(task.id)
        || typeof task.runtime !== "string" || !STATES.has(task.runtime) || typeof task.outcome !== "string" || !OUTCOMES.has(task.outcome)
        || !nullableBool(task.fake) || !(task.duration_seconds === null || (typeof task.duration_seconds === "number" && Number.isFinite(task.duration_seconds) && task.duration_seconds >= 0))) throw Error("Invalid task");
    const key = `${task.kind}/${task.id}`;
    if (seen.has(key)) throw Error("Duplicate task");
    seen.add(key);
  }
  return value as Snapshot;
}

export async function readSnapshot(path: string, signal: AbortSignal): Promise<Snapshot> {
  if (!isAbsolute(path)) throw Error("Absolute snapshot path required");
  signal.throwIfAborted();
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const info = await file.stat();
    if (!info.isFile() || info.size > MAX_BYTES || (info.mode & 0o077) !== 0 || info.uid !== process.getuid?.()) throw Error("Unsafe snapshot file");
    const buffer = Buffer.alloc(MAX_BYTES + 1);
    const result = await file.read(buffer, 0, buffer.length, 0);
    signal.throwIfAborted();
    if (result.bytesRead > MAX_BYTES) throw Error("Snapshot too large");
    return parseSnapshot(buffer.subarray(0, result.bytesRead).toString("utf8"));
  } finally { await file.close(); }
}

function fresh(value: string | null, now: number, maxAge = 120_000) {
  if (value === null) return false;
  const age = now - Date.parse(value);
  return Number.isFinite(age) && age >= 0 && age <= maxAge;
}
function stamp(value: string) { return new Date(value).toISOString(); }
function shown(value: number | null) { return value === null ? "unknown" : String(value); }

export function createSwarmReader(options: {
  allowedSender?: string; path?: string;
  read?: typeof readSnapshot; now?: () => number;
} = {}) {
  const allowed = (options.allowedSender ?? process.env.PHOTON_ALLOWED_SENDER ?? "").trim();
  const path = options.path ?? process.env.SWARM_STATUS_FILE;
  const read = options.read ?? readSnapshot, now = options.now ?? Date.now;
  return async (space: SwarmSpace, message: SwarmMessage, signal: AbortSignal): Promise<string | null | undefined> => {
    const text = message.content.text?.trim();
    if (message.content.type !== "text" || !text || !/^swarm(?:\s|$)/i.test(text)) return undefined;
    if (!allowed || message.direction !== "inbound" || message.platform !== "imessage"
        || message.sender?.__platform !== "imessage" || message.sender.kind === "agent" || message.sender.id !== allowed
        || space.__platform !== "imessage" || space.type !== "dm") return null;
    const parts = text.split(/\s+/);
    const status = parts.length === 2 && parts[1]?.toLowerCase() === "status";
    const result = parts.length === 4 && parts[1]?.toLowerCase() === "result" && ["coding", "batch"].includes(parts[2]!) && ID.test(parts[3]!);
    if (!status && !result) return HELP;
    if (!path) return "Swarm status is unavailable: no private snapshot is configured.";
    let snapshot: Snapshot;
    try { snapshot = await read(path, signal); }
    catch { return "Swarm status is unavailable. No job or service action was performed."; }
    if (status) {
      const health = snapshot.health;
      if (!fresh(health.observed_at, now(), 60_000)) return "Swarm status is stale or unavailable; current health is unknown.";
      const state = health.canvas_active === null ? "unknown" : health.canvas_active ? "active" : "inactive";
      return `Swarm observed ${stamp(health.observed_at!)}\nCanvas: ${state}; running conversations: ${shown(health.running_conversations)}; active worker/guard units: ${shown(health.active_worker_guard_units)}; retained failed units: ${shown(health.failed_worker_guard_units)}.\nZero active workers can be normal idle state. This does not verify application results or billing.`;
    }
    if (!fresh(snapshot.tasks_observed_at, now())) return "Swarm task snapshot is stale or unavailable; current task state is unknown.";
    const task = snapshot.tasks.find(row => row.kind === parts[2] && row.id === parts[3]);
    if (!task) return snapshot.inventory_complete ? "No matching task in this snapshot." : "No matching task in the partial snapshot; the task may be unobserved.";
    return `${task.kind} task ${task.id} · observed ${stamp(snapshot.tasks_observed_at!)}\nRuntime: ${task.runtime}; outcome: ${task.outcome.replaceAll("_", " ")}; duration: ${shown(task.duration_seconds)} seconds${task.fake === true ? "; fake provider" : ""}.\nCompletion is workflow evidence, not acceptance of generated code. No private output or prompt is included.`;
  };
}
