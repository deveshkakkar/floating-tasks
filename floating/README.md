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

## Message reliability candidate (APP-001)

The processor preserves outbound filtering and existing task commands. Creation
now acknowledges receipt only: a separate webhook owns persistence. Confirm task
state with `query`; this bridge does not poll or retry creation.

Task HTTP requests, including response bodies and Cognito refresh, have a
15-second abortable deadline and a 256 KiB response limit. A message has a shared
30-second operation deadline; every later request checks the same signal before
starting. Mutation timeouts/errors are uncertain outcomes, not permission to
repeat a write. A 202 acknowledgement also does not confirm completion. Mac
Keychain reads have a 3-second subprocess limit; credential storage is unchanged.

The installed Spectrum cloud `space.send` has no abort parameter. Waiting for a
reply is capped at 15 seconds, but its slot remains reserved until the actual
promise settles. At most two sends may remain pending. When both slots are busy,
the processor skips new commands before any task operation and emits the fixed
`send_capacity_exhausted` diagnostic. No message content, recipient, credential
or provider error enters these application diagnostics. A late reply may still
arrive. This is bounded failure handling, not guaranteed delivery.

Processing stays sequential, with no application queue or automatic retry. The
SDK's internal buffering, retries and event redelivery are separate limitations;
there is no durable inbox/outbox or cross-restart deduplication in this change.
Sender authorization and Swarm routing remain separate SWARM-001 work and must
precede enabling Swarm submissions. No new provider, authentication or scheduler
is enabled here. A provider iterator failure ends the process after bounded
shutdown; the existing deployment supervisor retains its restart policy.

Run `npm ci --ignore-scripts`, `npm test`, and `npm run typecheck` for isolated
validation. Tests do not start Spectrum or use production credentials. They
exercise actual task helpers with fake fetches plus a local HTTP server for
header/body cancellation, delayed lookup, uncertain writes, missing auth,
failed/hung sends, admission limits and truthful creation acknowledgements.
Deploy only a reviewed candidate image, preserve the previous digest, and keep
one connected bridge instance. Live messaging requires an explicitly selected
recipient and test scope.
