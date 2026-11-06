import assert from "node:assert/strict";
import { test } from "node:test";
import { loopbackCallback, matchesOAuthState } from "../src/login-security.ts";
import { mayHandleMessage } from "../src/message-policy.ts";
import { requireSetting, validateCloudConfiguration } from "../src/config.ts";

const sender = "+15551234567";
const inbound = { platform: "imessage", direction: "inbound", service: "iMessage", sender: { id: sender } };
const configured = {
  FLOATING_BRAIN_API_URL: "https://api.example.com",
  COGNITO_AUTHORIZATION_ENDPOINT: "https://auth.example.com/oauth2/authorize",
  COGNITO_TOKEN_ENDPOINT: "https://auth.example.com/oauth2/token",
  COGNITO_CLIENT_ID: "public-client",
};

test("only the configured sender's inbound direct conversation is authorized", () => {
  assert.equal(mayHandleMessage(inbound, "dm", sender), true);
  for (const candidate of [
    { ...inbound, sender: { id: "+15557654321" } },
    { ...inbound, sender: undefined },
    { ...inbound, direction: "outbound" },
    { ...inbound, platform: "terminal" },
    { ...inbound, sender: { id: sender.slice(1) } },
  ]) assert.equal(mayHandleMessage(candidate, "dm", sender), false);
});

test("group or unknown conversations and an absent allowlist never expose the account", () => {
  assert.equal(mayHandleMessage(inbound, "group", sender), false);
  assert.equal(mayHandleMessage(inbound, "unknown", sender), false);
  assert.equal(mayHandleMessage(inbound, "dm", ""), false);
  assert.equal(mayHandleMessage(inbound, "dm", "   "), false);
});

test("SMS, RCS, and unknown services cannot use a phone number to access the saved account", () => {
  for (const service of ["SMS", "RCS", undefined]) {
    assert.equal(mayHandleMessage({ ...inbound, service }, "dm", sender), false);
  }
});

test("malformed non-ASCII OAuth state is rejected without throwing", () => {
  const expected = "a".repeat(43);
  assert.equal(matchesOAuthState(expected, expected), true);
  for (const received of ["", "b".repeat(43), "é".repeat(43), "a".repeat(42), "a".repeat(44)]) {
    assert.equal(matchesOAuthState(received, expected), false);
  }
  assert.equal(matchesOAuthState("", ""), false);
});

test("the OAuth listener accepts only an unadorned IPv4 loopback callback", () => {
  assert.equal(loopbackCallback("http://127.0.0.1:8765/callback").port, "8765");
  for (const url of [
    "https://example.com/callback", "http://0.0.0.0:8765/callback", "http://localhost:8765/callback",
    "http://127.0.0.1:8765/elsewhere", "http://127.0.0.1:8765/callback?state=bad",
    "http://user:password@127.0.0.1:8765/callback", "http://127.0.0.1:8765/callback#fragment",
    "http://127.0.0.1:0/callback",
  ]) assert.throws(() => loopbackCallback(url));
  assert.throws(() => loopbackCallback("http://127.0.0.1:8765/callback", "0.0.0.0"));
});

test("a clean checkout and partial deployment configuration fail before networking", () => {
  assert.throws(() => validateCloudConfiguration({}));
  assert.doesNotThrow(() => validateCloudConfiguration(configured));
  for (const key of Object.keys(configured)) {
    assert.throws(() => validateCloudConfiguration({ ...configured, [key]: "" }), key);
  }
  assert.throws(() => requireSetting("PHOTON_ALLOWED_SENDER", {}));
});

test("deployment URLs cannot downgrade, embed credentials, or point at sample destinations", () => {
  for (const key of ["FLOATING_BRAIN_API_URL", "COGNITO_AUTHORIZATION_ENDPOINT", "COGNITO_TOKEN_ENDPOINT"]) {
    for (const value of ["http://api.example.com", "https://user:password@api.example.com", "https://api.example.com?token=value", "https://api.example.com#fragment", "https://api.example.invalid", "not-a-url"]) {
      assert.throws(() => validateCloudConfiguration({ ...configured, [key]: value }), key);
    }
  }
  assert.throws(() => validateCloudConfiguration({ ...configured, FLOATING_BRAIN_API_URL: "https://api.example.com/v1" }));
  assert.throws(() => validateCloudConfiguration({ ...configured, COGNITO_TOKEN_ENDPOINT: "https://other.example.com/oauth2/token" }));
});
