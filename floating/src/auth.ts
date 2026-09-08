import { execFileSync } from "node:child_process";
import { COGNITO_CLIENT_ID, COGNITO_TOKEN_ENDPOINT } from "./config.ts";

const KEYCHAIN_SERVICE = "floating-brain-spectrum";
const KEYCHAIN_ACCOUNT = "refresh-token";

function readRefreshToken(): string | null {
  try {
    const token = execFileSync(
      "security",
      ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    return token || null;
  } catch {
    return null;
  }
}

export function saveRefreshToken(token: string): void {
  execFileSync(
    "security",
    ["add-generic-password", "-U", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w", token],
    { stdio: "ignore" },
  );
}

export async function getAccessToken(): Promise<string | null> {
  const refreshToken = readRefreshToken();
  if (!refreshToken) return null;

  try {
    const response = await fetch(COGNITO_TOKEN_ENDPOINT, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "refresh_token",
        client_id: COGNITO_CLIENT_ID,
        refresh_token: refreshToken,
      }),
    });
    if (!response.ok) return null;
    const payload = (await response.json()) as { access_token?: string };
    return payload.access_token ?? null;
  } catch {
    return null;
  }
}

export const LOGIN_REQUIRED = "Run `npm run login` in the floating directory before querying tasks.";
