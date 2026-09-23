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

## Read-only Swarm candidate (SWARM-001)

`swarm status` and `swarm result <coding|batch> <task-id>` read a bounded private
JSON snapshot. Exact `PHOTON_ALLOWED_SENDER` matching, inbound iMessage identity
and direct-message checks precede file access. Missing identity denies silently;
non-Swarm commands retain their existing behavior. This gate applies to Swarm
commands only. Job submission, service control and unsolicited replies are absent.

`SWARM_STATUS_FILE` must name an absolute path to an owner-only regular file
owned by the bridge UID. Provisioning this optional setting and a read-only
directory mount is a separate deployment step. Mount the directory, not a single
file inode: the host publisher replaces snapshots atomically. The bridge needs
no Docker socket, SSH key, Swarm credentials or host command execution.

Health expires after 60 seconds; task metadata after 120 seconds, based on original
observation times. Republishing cannot renew stale evidence. Unknown and partial
observations remain explicit; completed workflows do not imply accepted code.
Only selected counts, task IDs, runtime/outcome, duration and fake-provider markers
are exposed; no prompts, generated output or billing data. Snapshots are rebuildable.

Task lookup uses kind plus stable task ID across restarts. There is no submission,
durable message mapping or inbox/outbox, and event redelivery may repeat a read-only
reply. Offline tests cover denial, schema/file boundaries, freshness, restart lookup
and legacy routing. No live recipient test, schedule or production cutover has
been performed. Retain the prior image and use a single connected bridge instance
when an explicitly scoped deployment and recipient test are approved.
