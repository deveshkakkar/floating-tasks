import { timingSafeEqual } from "node:crypto";

export function matchesOAuthState(received: string, expected: string): boolean {
  const actualBytes = Buffer.from(received, "utf8");
  const expectedBytes = Buffer.from(expected, "utf8");
  return expectedBytes.length > 0 && actualBytes.length === expectedBytes.length &&
    timingSafeEqual(actualBytes, expectedBytes);
}

export function loopbackCallback(value: string, bind?: string): URL {
  const url = new URL(value);
  if (url.protocol !== "http:" || url.hostname !== "127.0.0.1" || url.pathname !== "/callback" ||
      url.username || url.password || url.search || url.hash || url.port === "0" ||
      (bind !== undefined && bind !== url.hostname)) {
    throw new Error("Cognito callback must use http://127.0.0.1:<port>/callback and bind only to 127.0.0.1.");
  }
  return url;
}
