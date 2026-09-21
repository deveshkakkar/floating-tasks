import { randomBytes } from "node:crypto";
import { chmod, mkdir, open, readFile, rename } from "node:fs/promises";
import { dirname, join } from "node:path";
import { execFileSync } from "node:child_process";
import { COGNITO_CLIENT_ID, COGNITO_TOKEN_ENDPOINT } from "./config.ts";

const KEYCHAIN_SERVICE = "floating-brain-spectrum";
const KEYCHAIN_ACCOUNT = "refresh-token";
const DEFAULT_LINUX_TOKEN_FILE = "/run/auth/refresh-token";

async function readLinuxRefreshToken(): Promise<string | null> {
  const path = process.env.COGNITO_REFRESH_TOKEN_FILE ?? DEFAULT_LINUX_TOKEN_FILE;
  try {
    const token = (await readFile(path, "utf8")).trim();
    return token || null;
  } catch {
    return null;
  }
}

function readMacRefreshToken(): string | null {
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

export async function saveRefreshToken(token: string): Promise<void> {
  if (process.platform === "darwin") {
    execFileSync(
      "security",
      ["add-generic-password", "-U", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w", token],
      { stdio: "ignore" },
    );
    return;
  }

  if (process.platform !== "linux") throw new Error("Unsupported credential storage platform");
  const path = process.env.COGNITO_REFRESH_TOKEN_FILE ?? DEFAULT_LINUX_TOKEN_FILE;
  const directory = dirname(path);
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await chmod(directory, 0o700);
  const temporaryPath = join(directory, `.refresh-token-${randomBytes(12).toString("hex")}`);
  const handle = await open(temporaryPath, "wx", 0o600);
  try {
    await handle.writeFile(`${token}\n`, "utf8");
    await handle.sync();
  } finally {
    await handle.close();
  }
  await rename(temporaryPath, path);
  await chmod(path, 0o600);
}

export async function getAccessToken(): Promise<string | null> {
  const refreshToken = process.platform === "darwin"
    ? readMacRefreshToken()
    : process.platform === "linux" ? await readLinuxRefreshToken() : null;
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
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) return null;
    const payload = (await response.json()) as { access_token?: string };
    return payload.access_token ?? null;
  } catch {
    return null;
  }
}

export const LOGIN_REQUIRED = "Run the documented Cognito login flow on the home server before querying tasks.";
