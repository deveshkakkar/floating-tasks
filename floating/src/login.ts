import { createHash, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { saveRefreshToken } from "./auth.ts";
import {
  COGNITO_AUTHORIZATION_ENDPOINT,
  COGNITO_CLIENT_ID,
  COGNITO_REDIRECT_URI,
  COGNITO_TOKEN_ENDPOINT,
  validateOAuthConfiguration,
} from "./config.ts";
import { loopbackCallback, matchesOAuthState } from "./login-security.ts";

validateOAuthConfiguration();
const redirectURI = loopbackCallback(COGNITO_REDIRECT_URI, process.env.COGNITO_CALLBACK_BIND);

const verifier = randomBytes(32).toString("base64url");
const expectedState = randomBytes(32).toString("base64url");
const challenge = createHash("sha256").update(verifier).digest("base64url");
const authorizationURL = new URL(COGNITO_AUTHORIZATION_ENDPOINT);
authorizationURL.search = new URLSearchParams({
  client_id: COGNITO_CLIENT_ID,
  response_type: "code",
  redirect_uri: redirectURI.toString(),
  scope: "openid email",
  code_challenge_method: "S256",
  code_challenge: challenge,
  state: expectedState,
}).toString();

let handledCallback = false;
const server = createServer(async (request, response) => {
  let requestURL: URL;
  try {
    requestURL = new URL(request.url ?? "/", redirectURI);
  } catch {
    response.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
    response.end("Invalid callback URL.");
    return;
  }
  if (request.method !== "GET" || requestURL.pathname !== redirectURI.pathname) {
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    response.end("Not found.");
    return;
  }

  if (handledCallback) {
    response.writeHead(409, { "content-type": "text/plain; charset=utf-8" });
    response.end("This login callback was already used.");
    return;
  }
  const receivedState = requestURL.searchParams.get("state") ?? "";
  const stateMatches = matchesOAuthState(receivedState, expectedState);
  const code = requestURL.searchParams.get("code");
  const providerError = requestURL.searchParams.has("error");
  if (!stateMatches) {
    response.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
    response.end("Invalid login state.");
    return; // An unrelated request must not consume the pending login.
  }
  handledCallback = true;
  if (!code || providerError) {
    response.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
    response.end("Cognito login failed or was cancelled. Restart the login command and try again.");
    server.close();
    console.error("Cognito login was cancelled or its callback could not be validated.");
    process.exitCode = 1;
    return;
  }

  try {
    const tokenResponse = await fetch(COGNITO_TOKEN_ENDPOINT, {
      method: "POST",
      redirect: "error",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        client_id: COGNITO_CLIENT_ID,
        code,
        redirect_uri: redirectURI.toString(),
        code_verifier: verifier,
      }),
      signal: AbortSignal.timeout(20_000),
    });
    if (!tokenResponse.ok) throw new Error("Token exchange was rejected");
    const payload = await tokenResponse.json() as { refresh_token?: string };
    if (typeof payload.refresh_token !== "string" || !payload.refresh_token) throw new Error("No refresh token was returned");
    await saveRefreshToken(payload.refresh_token);
    response.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
    response.end("Login complete. You can close this window.");
    console.log("Cognito login completed; refresh token stored in protected runtime storage.");
  } catch {
    response.writeHead(502, { "content-type": "text/plain; charset=utf-8" });
    response.end("Cognito login could not be completed. Restart the login command and try again.");
    console.error("Cognito token exchange or protected token storage failed.");
    process.exitCode = 1;
  } finally {
    server.close();
  }
});

server.headersTimeout = 10_000;
server.requestTimeout = 20_000;
server.listen(
  Number(redirectURI.port || 80),
  redirectURI.hostname,
  () => {
    console.log("Open this URL in a browser on the client with the localhost SSH tunnel:");
    console.log(authorizationURL.toString());
    console.log("Waiting for the Cognito callback for up to 10 minutes.");
  },
);
const loginTimeout = setTimeout(() => {
  console.error("Cognito login timed out. Restart the login command to try again.");
  server.close(() => { process.exitCode = 1; });
}, 10 * 60 * 1000);
loginTimeout.unref();
server.once("close", () => clearTimeout(loginTimeout));
server.once("error", () => {
  console.error("Could not bind the Cognito callback listener. Check whether port 8765 is available.");
  process.exitCode = 1;
});
