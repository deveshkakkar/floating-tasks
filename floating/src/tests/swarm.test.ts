import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, writeFile, chmod, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createSwarmReader, parseSnapshot, readSnapshot, type SwarmMessage } from "../swarm.ts";
import { Processor } from "../processor.ts";

const observed = "2026-09-23T12:00:00+00:00", now = Date.parse(observed);
const dm = { __platform: "imessage", type: "dm" };
const message = (text = "swarm status"): SwarmMessage => ({ direction: "inbound", platform: "imessage",
  sender: { __platform: "imessage", id: "operator@example.invalid" }, content: { type: "text", text } });
const fixture = () => ({ schema_version: 1, producer: "swarm-readonly-status-v1", published_at: observed,
  max_age_seconds: 120, health: { observed_at: observed, canvas_active: true, running_conversations: 0,
    active_worker_guard_units: 0, failed_worker_guard_units: 4 }, tasks_observed_at: observed,
  inventory_complete: true, tasks: [{ kind: "coding", id: "task-one", runtime: "stopped", outcome: "completed", duration_seconds: 9.3, fake: true }] });
const signal = () => new AbortController().signal;

test("sender, direction, platform and direct-message checks run before any snapshot read", async () => {
  let reads = 0;
  const route = createSwarmReader({ allowedSender: "operator@example.invalid", path: "/fixed/status.json", now: () => now,
    read: async () => { reads++; return parseSnapshot(JSON.stringify(fixture())); } });
  for (const input of [
    { ...message(), sender: undefined }, { ...message(), direction: "outbound" },
    { ...message(), platform: "other" }, { ...message(), direction: undefined },
    { ...message(), sender: { __platform: "other", id: "operator@example.invalid" } },
    { ...message(), sender: { __platform: "imessage", id: "unauthorized@example.invalid" } },
    { ...message(), sender: { __platform: "imessage", id: "operator@example.invalid", kind: "agent" } },
  ]) assert.equal(await route(dm, input, signal()), null);
  assert.equal(await route({ ...dm, type: "group" }, message(), signal()), null);
  assert.equal(await route({}, message(), signal()), null);
  assert.equal(reads, 0);
  assert.match((await route(dm, message(), signal()))!, /Canvas: active/);
  assert.equal(reads, 1);
});

test("unconfigured sender denies access, and missing snapshot never falls through to task operations", async () => {
  let reads = 0;
  const route = createSwarmReader({ allowedSender: "", path: "/fixed/status.json", read: async () => { reads++; throw Error("private"); } });
  assert.equal(await route(dm, message(), signal()), null);
  assert.equal(reads, 0);
  const missing = createSwarmReader({ allowedSender: "operator@example.invalid", path: "/fixed/status.json", read: async () => { throw Error("private"); } });
  const result = await missing(dm, message(), signal());
  assert.match(result!, /unavailable/); assert.doesNotMatch(result!, /private/);
});

test("stale and future source times cannot be renewed by a new publication time", async () => {
  for (const delta of [-121_000, 1000]) {
    const value = fixture(); value.health.observed_at = new Date(now + delta).toISOString(); value.tasks_observed_at = value.health.observed_at;
    const route = createSwarmReader({ allowedSender: "operator@example.invalid", path: "/fixed/status.json", now: () => now,
      read: async () => parseSnapshot(JSON.stringify(value)) });
    assert.match((await route(dm, message(), signal()))!, /unknown/);
    assert.match((await route(dm, message("swarm result coding task-one"), signal()))!, /unknown/);
  }
});

test("completion is a typed task lookup and does not claim accepted code", async () => {
  const route = createSwarmReader({ allowedSender: "operator@example.invalid", path: "/fixed/status.json", now: () => now,
    read: async () => parseSnapshot(JSON.stringify(fixture())) });
  const reply = await route(dm, message("swarm result coding task-one"), signal());
  assert.match(reply!, /outcome: completed/); assert.match(reply!, /fake provider/); assert.match(reply!, /not acceptance/);
  assert.match((await route(dm, message("swarm result batch task-one"), signal()))!, /No matching/);
  assert.match((await route(dm, message("swarm submit do-stuff"), signal()))!, /submission.*unavailable/);
  assert.match((await route(dm, message("swarm result coding ..\/private"), signal()))!, /Read-only/);
});

test("unknown counts and partial task inventories remain explicit", async () => {
  const value = JSON.parse(JSON.stringify(fixture()));
  value.health.running_conversations = null; value.inventory_complete = false; value.tasks = [];
  const route = createSwarmReader({ allowedSender: "operator@example.invalid", path: "/fixed/status.json", now: () => now,
    read: async () => parseSnapshot(JSON.stringify(value)) });
  assert.match((await route(dm, message(), signal()))!, /running conversations: unknown/);
  assert.match((await route(dm, message("swarm result coding task-one"), signal()))!, /partial snapshot/);
});

test("schema rejects arbitrary fields, duplicate task identities and invalid counts", () => {
  for (const change of [
    (v: any) => { v.secret = "private"; }, (v: any) => { v.tasks.push(v.tasks[0]); },
    (v: any) => { v.health.running_conversations = true; }, (v: any) => { v.tasks[0].outcome = "private"; },
    (v: any) => { v.tasks[0].kind = ["coding"]; }, (v: any) => { v.max_age_seconds = 999999; }, (v: any) => { v.tasks[0].id = "../private"; },
  ]) { const value = fixture(); change(value); assert.throws(() => parseSnapshot(JSON.stringify(value))); }
});

test("file reader rejects links, shared permissions, invalid JSON and oversized data", async () => {
  const dir = await mkdtemp(join(tmpdir(), "swarm-reader-")), path = join(dir, "status.json");
  await writeFile(path, JSON.stringify(fixture()), { mode: 0o600 });
  assert.equal((await readSnapshot(path, signal())).tasks[0]?.id, "task-one");
  const link = join(dir, "link.json"); await symlink(path, link);
  await assert.rejects(readSnapshot(link, signal()));
  await chmod(path, 0o644); await assert.rejects(readSnapshot(path, signal()));
  await chmod(path, 0o600); await writeFile(path, "not JSON"); await assert.rejects(readSnapshot(path, signal()));
  await writeFile(path, "x".repeat(300_000)); await assert.rejects(readSnapshot(path, signal()));
});

test("processor routes allowed queries and preserves existing non-Swarm commands; denial sends nothing", async () => {
  const replies: string[] = [], legacy: string[] = [];
  const route = createSwarmReader({ allowedSender: "operator@example.invalid", path: "/fixed/status.json", now: () => now,
    read: async () => parseSnapshot(JSON.stringify(fixture())) });
  const processor = new Processor(async text => { legacy.push(text); return "legacy reply"; }, () => {}, 1000, 1000, route);
  const space = { ...dm, send: async (text: string) => { replies.push(text); } };
  await processor.handle(space, { ...message(), sender: undefined });
  assert.deepEqual(replies, []); assert.deepEqual(legacy, []);
  await processor.handle(space, message());
  await processor.handle(space, message("help"));
  assert.equal(replies.length, 2); assert.deepEqual(legacy, ["help"]);
});

test("fresh process reads the same task identity without submitting or replaying work", async () => {
  const read = async () => parseSnapshot(JSON.stringify(fixture()));
  for (let i = 0; i < 2; i++) {
    const route = createSwarmReader({ allowedSender: "operator@example.invalid", path: "/fixed/status.json", now: () => now, read });
    assert.match((await route(dm, message("swarm result coding task-one"), signal()))!, /coding task task-one/);
  }
});
