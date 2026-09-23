import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "node:http";
import { Processor, processMessages, replyFor, type Event } from "../processor.ts";
import { deadline, requestJSON } from "../request.ts";
import { queryActiveTasks } from "../query.ts";
import { queryArchivedTasks } from "../archive.ts";
import { queryDailyTasks } from "../daily.ts";
import { restoreArchivedTask } from "../restore.ts";
import { completeTask } from "../complete.ts";

const inbound = (text: string) => ({ direction: "inbound", content: { type: "text", text } });
const wait = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

async function withAuth(action: () => Promise<void>) {
  const old = process.env.COGNITO_REFRESH_TOKEN_FILE;
  const path = join(await mkdtemp(join(tmpdir(), "photon-offline-")), "refresh");
  await writeFile(path, "offline-test-value", { mode: 0o600 });
  process.env.COGNITO_REFRESH_TOKEN_FILE = path;
  try { await action(); } finally {
    if (old === undefined) delete process.env.COGNITO_REFRESH_TOKEN_FILE;
    else process.env.COGNITO_REFRESH_TOKEN_FILE = old;
  }
}

async function withFetch(mock: typeof fetch, action: () => Promise<void>) {
  const previous = globalThis.fetch;
  globalThis.fetch = mock;
  try { await action(); } finally { globalThis.fetch = previous; }
}
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status });
const isAuth = (url: unknown) => String(url).includes("oauth2/token");

test("outbound/non-text messages do not invoke operations or send replies", async () => {
  let calls = 0;
  const processor = new Processor(async () => { calls++; return "reply"; });
  const space = { send: async () => { calls++; } };
  await processor.handle(space, { direction: "outbound", content: { type: "text", text: "query" } });
  await processor.handle(space, { content: { type: "image" } });
  assert.equal(calls, 0);
});

test("create acknowledges receipt without claiming persistence or contacting the API", async () => {
  await withFetch(async () => { throw Error("unexpected API request"); }, async () => {
    const response = await replyFor("create a task to test", new AbortController().signal);
    assert.match(response, /^Received: test/);
    assert.match(response, /not yet confirmed/);
    assert.doesNotMatch(response, /Created|Queued/);
  });
});

test("rejected send does not terminate the iterable or retry delivery", async () => {
  const replies: string[] = [], events: Event[] = [];
  const processor = new Processor(async text => text, event => events.push(event));
  const space = { send: async (text: string) => { replies.push(text); if (text === "first") throw Error("private-error"); } };
  async function* messages() { yield [space, inbound("first")] as const; yield [space, inbound("second")] as const; }
  await processMessages(messages(), processor);
  assert.deepEqual(replies, ["first", "second"]);
  assert.deepEqual(events, ["send_failed_or_uncertain"]);
  assert.equal(processor.pendingSends, 0);
});

test("uncancellable timed-out sends retain slots and block new operations at the cap", async () => {
  let operations = 0;
  const events: Event[] = [];
  const processor = new Processor(async () => { operations++; return "reply"; }, event => events.push(event), 50, 10);
  let release!: () => void;
  const pending = new Promise<void>(resolve => { release = resolve; });
  const space = { send: () => pending };
  await processor.handle(space, inbound("one"));
  await processor.handle(space, inbound("two"));
  await processor.handle(space, inbound("three"));
  assert.equal(processor.pendingSends, 2);
  assert.equal(operations, 2);
  assert.equal(events.at(-1), "send_capacity_exhausted");
  release(); await wait(0);
  assert.equal(processor.pendingSends, 0);
  await processor.handle({ send: async () => {} }, inbound("four"));
  assert.equal(operations, 3);
});

test("slow operation is aborted and late result does not send a second reply", async () => {
  let aborted = false;
  const replies: string[] = [];
  const processor = new Processor(async (_, signal) => {
    signal.addEventListener("abort", () => { aborted = true; });
    await wait(40); return "late success";
  }, () => {}, 5, 10);
  await processor.handle({ send: async text => { replies.push(text); } }, inbound("query"));
  await wait(50);
  assert.equal(aborted, true);
  assert.equal(replies.length, 1);
  assert.match(replies[0]!, /could not be confirmed/);
});

test("missing authentication makes no network request and later messages still work", async () => {
  const old = process.env.COGNITO_REFRESH_TOKEN_FILE;
  process.env.COGNITO_REFRESH_TOKEN_FILE = "/nonexistent/photon-offline-test";
  try {
    await withFetch(async () => { throw Error("unexpected network"); }, async () => {
      assert.match(await queryActiveTasks(), /login flow/);
      assert.match(await replyFor("help", new AbortController().signal), /I can/);
    });
  } finally {
    if (old === undefined) delete process.env.COGNITO_REFRESH_TOKEN_FILE;
    else process.env.COGNITO_REFRESH_TOKEN_FILE = old;
  }
});

test("query, daily and archive API calls carry an abort signal and preserve results", async () => {
  await withAuth(async () => withFetch(async (url, init) => {
    assert.ok(init?.signal);
    return isAuth(url) ? json({ access_token: "offline-access" }) : json({ items: [{ text: "fixture task", externalId: "fixture-id" }] });
  }, async () => {
    for (const operation of [queryActiveTasks, queryDailyTasks, queryArchivedTasks]) {
      assert.match(await operation(), /fixture task/);
    }
  }));
});

test("uncertain mutations are not retried or described as confirmed", async () => {
  let mutations = 0;
  await withAuth(async () => withFetch(async (url, init) => {
    if (isAuth(url)) return json({ access_token: "offline-access" });
    if (init?.method === "POST") { mutations++; throw Error("private failure"); }
    return json({ items: [{ text: "fixture task", externalId: "fixture-id" }] });
  }, async () => {
    for (const operation of [completeTask, restoreArchivedTask]) {
      const reply = await operation("fixture-id");
      assert.match(reply, /could not be confirmed/);
      assert.doesNotMatch(reply, /private failure|Completed:|Restored:/);
    }
  }));
  assert.equal(mutations, 2);
});

test("expired message cannot start a mutation after an uncooperative late lookup", async () => {
  let mutations = 0;
  await withAuth(async () => withFetch(async (url, init) => {
    if (isAuth(url)) return json({ access_token: "offline-access" });
    if (init?.method === "POST") { mutations++; return json({}); }
    await wait(30);
    return json({ items: [{ text: "fixture task", externalId: "fixture-id" }] });
  }, async () => {
    await assert.rejects(deadline(signal => completeTask("fixture-id", signal), 5));
    await wait(50);
  }));
  assert.equal(mutations, 0);
});

test("request deadline aborts real stalled headers and response-body reads", async () => {
  let closed = 0;
  const server = createServer((req, res) => {
    req.on("close", () => { closed++; });
    if (req.url === "/body") { res.writeHead(200, { "Content-Type": "application/json" }); res.write('{"items":'); }
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address !== "string");
  try {
    for (const path of ["/headers", "/body"]) {
      await assert.rejects(requestJSON(`http://127.0.0.1:${address.port}${path}`, {}, undefined, 40));
    }
    await wait(40);
    assert.equal(closed, 2);
  } finally {
    server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve()));
  }
});

test("response size is bounded and oversized input starts no work", async () => {
  await withFetch(async () => new Response("x".repeat(300_000)), async () => {
    await assert.rejects(requestJSON("http://offline.invalid"), /too large/);
  });
  let calls = 0;
  const events: Event[] = [];
  const processor = new Processor(async () => { calls++; return "reply"; }, event => events.push(event));
  await processor.handle({ send: async () => { calls++; } }, inbound("x".repeat(4097)));
  assert.equal(calls, 0);
  assert.deepEqual(events, ["message_too_large"]);
});

test("confirmed mutation acknowledgements and Apple conflict behavior are preserved", async () => {
  let status = 200;
  await withAuth(async () => withFetch(async (url, init) => {
    if (isAuth(url)) return json({ access_token: "offline-access" });
    if (init?.method === "POST") return json({}, status);
    return json({ items: [{ text: "fixture task", externalId: "fixture-id" }] });
  }, async () => {
    assert.equal(await completeTask("fixture-id"), "Completed: fixture task");
    assert.equal(await restoreArchivedTask("fixture-id"), "Restored: fixture task");
    for (status of [202, 500]) {
      assert.match(await completeTask("fixture-id"), /not confirmed/);
      assert.match(await restoreArchivedTask("fixture-id"), /not confirmed/);
    }
    status = 409;
    assert.match(await completeTask("fixture-id"), /Reminders app first/);
  }));
});

test("a failed operation is isolated and diagnostics do not include its error or message", async () => {
  const events: Event[] = [], replies: string[] = [];
  const processor = new Processor(async text => {
    if (text === "private-message") throw Error("private-provider-error");
    return text;
  }, event => events.push(event));
  const space = { send: async (text: string) => { replies.push(text); } };
  await processor.handle(space, inbound("private-message"));
  await processor.handle(space, inbound("next"));
  assert.deepEqual(events, ["message_failed"]);
  assert.equal(replies[1], "next");
  assert.doesNotMatch(replies[0]!, /private/);
});
