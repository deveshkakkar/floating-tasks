type Environment = Record<string, string | undefined>;

export const API_URL = process.env.FLOATING_BRAIN_API_URL?.trim() ?? "";
export const COGNITO_AUTHORIZATION_ENDPOINT = process.env.COGNITO_AUTHORIZATION_ENDPOINT?.trim() ?? "";
export const COGNITO_TOKEN_ENDPOINT = process.env.COGNITO_TOKEN_ENDPOINT?.trim() ?? "";
export const COGNITO_CLIENT_ID = process.env.COGNITO_CLIENT_ID?.trim() ?? "";
export const COGNITO_REDIRECT_URI = process.env.COGNITO_REDIRECT_URI ?? "http://127.0.0.1:8765/callback";

export function requireSetting(name: string, environment: Environment = process.env): string {
  const value = environment[name]?.trim();
  if (!value) throw new Error(`Set ${name} in your local environment before starting this command.`);
  return value;
}

function httpsEndpoint(name: string, environment: Environment): URL {
  const value = requireSetting(name, environment);
  let url: URL;
  try { url = new URL(value); } catch { throw new Error(`${name} must be a valid HTTPS URL.`); }
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash ||
      url.hostname === "invalid" || url.hostname.endsWith(".invalid")) {
    throw new Error(`${name} must be an HTTPS URL without credentials, query, or fragment.`);
  }
  return url;
}

export function validateOAuthConfiguration(environment: Environment = process.env): void {
  const authorization = httpsEndpoint("COGNITO_AUTHORIZATION_ENDPOINT", environment);
  const token = httpsEndpoint("COGNITO_TOKEN_ENDPOINT", environment);
  if (authorization.origin !== token.origin) {
    throw new Error("Cognito authorization and token endpoints must share an origin.");
  }
  requireSetting("COGNITO_CLIENT_ID", environment);
}

export function validateCloudConfiguration(environment: Environment = process.env): void {
  const api = httpsEndpoint("FLOATING_BRAIN_API_URL", environment);
  if (api.pathname !== "/") throw new Error("FLOATING_BRAIN_API_URL must be the API origin without /v1.");
  validateOAuthConfiguration(environment);
}
