export const API_URL = process.env.FLOATING_BRAIN_API_URL ??
  "https://xv5xsshic3.execute-api.us-east-1.amazonaws.com";
export const COGNITO_AUTHORIZATION_ENDPOINT = process.env.COGNITO_AUTHORIZATION_ENDPOINT ??
  "https://floating-brain-dev.auth.us-east-1.amazoncognito.com/oauth2/authorize";
export const COGNITO_TOKEN_ENDPOINT = process.env.COGNITO_TOKEN_ENDPOINT ??
  "https://floating-brain-dev.auth.us-east-1.amazoncognito.com/oauth2/token";
export const COGNITO_CLIENT_ID = process.env.COGNITO_CLIENT_ID ?? "5kb00q1qsduj6pvelg48cn6rn2";
export const COGNITO_REDIRECT_URI = process.env.COGNITO_REDIRECT_URI ?? "http://127.0.0.1:8765/callback";
