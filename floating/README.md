# floating

A [Spectrum](https://photon.codes/docs/spectrum-ts) project. Wired with: imessage.

## Environment

Before running, open `.env` and fill in the values:

From your project Settings on the [Photon dashboard](https://app.photon.codes):

- `PROJECT_ID`
- `PROJECT_SECRET`
- `FLOATING_BRAIN_API_URL`
- `COGNITO_AUTHORIZATION_ENDPOINT`
- `COGNITO_TOKEN_ENDPOINT`
- `COGNITO_CLIENT_ID`
- `COGNITO_REDIRECT_URI=http://127.0.0.1:8765/callback`
- `FLOATING_BRAIN_API_URL` (the deployed API base URL)
- `FLOATING_BRAIN_ACCESS_TOKEN` (a Cognito access token for the account)

## Run

```sh
npm install
npm run start
```

The messaging bridge uses Cognito Authorization Code + PKCE. Run the one-time
login command to open Hosted UI and store the refresh token in macOS Keychain:

```sh
npm run login
```

The bridge refreshes short-lived access tokens automatically; do not store an
access token in `.env`.

## Where to go next

- [Spectrum docs](https://photon.codes/docs/spectrum-ts)
- `src/index.ts` currently echoes each inbound text message back to its conversation.
- Edit `src/index.ts` to replace the echo loop with real agent logic.
- Add more providers from `spectrum-ts/providers/*`.
