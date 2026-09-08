import { createHash, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { execFile } from "node:child_process";
import { saveRefreshToken } from "./auth.ts";
import {
  COGNITO_AUTHORIZATION_ENDPOINT,
  COGNITO_CLIENT_ID,
  COGNITO_REDIRECT_URI,
  COGNITO_TOKEN_ENDPOINT,
} from "./config.ts";

const authorizationEndpoint = COGNITO_AUTHORIZATION_ENDPOINT;
const tokenEndpoint = COGNITO_TOKEN_ENDPOINT;
const clientID = COGNITO_CLIENT_ID;
const redirectURI = COGNITO_REDIRECT_URI;

const verifier = randomBytes(32).toString("base64url");
const challenge = createHash("sha256").update(verifier).digest("base64url");
const authorizationURL = new URL(authorizationEndpoint);
authorizationURL.search = new URLSearchParams({
  client_id: clientID,
  response_type: "code",
  redirect_uri: redirectURI,
  scope: "openid email",
  code_challenge_method: "S256",
  code_challenge: challenge,
}).toString();

const callback = new URL(redirectURI);
let handledCallback = false;
const server = createServer(async (request, response) => {
  const requestURL = new URL(request.url ?? "/", redirectURI);
  if (requestURL.pathname !== callback.pathname) {
    response.writeHead(404);
    response.end();
    return;
  }

  const code = requestURL.searchParams.get("code");
  const error = requestURL.searchParams.get("error");
  if (!code && !error) {
    response.writeHead(200, { "content-type": "text/plain" });
    response.end("Waiting for Cognito login...");
    return;
  }
  if (handledCallback) {
    response.writeHead(409);
    response.end("Login callback already handled.");
    return;
  }
  handledCallback = true;
  response.writeHead(200, { "content-type": "text/plain" });
  response.end(error ? "Login failed. You can close this window." : "Login complete. You can close this window.");
  server.close();

  if (!code) {
    console.error(`Login failed: ${error ?? "authorization code missing"}`);
    process.exitCode = 1;
    return;
  }

  const tokenResponse = await fetch(tokenEndpoint, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      client_id: clientID,
      code,
      redirect_uri: redirectURI,
      code_verifier: verifier,
    }),
  });
  if (!tokenResponse.ok) {
    console.error(`Token exchange failed with status ${tokenResponse.status}.`);
    process.exitCode = 1;
    return;
  }
  const payload = (await tokenResponse.json()) as { refresh_token?: string };
  if (!payload.refresh_token) {
    console.error("Login succeeded but no refresh token was returned.");
    process.exitCode = 1;
    return;
  }
  saveRefreshToken(payload.refresh_token);
  console.log("Login saved securely to the macOS Keychain.");
});

server.listen(Number(callback.port || 8765), callback.hostname || "127.0.0.1", () => {
  console.log("Opening Cognito sign-in in your browser...");
  execFile("open", [authorizationURL.toString()], () => {});
});
