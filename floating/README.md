# Floating Brain messaging companion

This optional TypeScript process connects a Spectrum/Photon iMessage provider to your own Floating Brain backend. It is experimental and requires a configured Photon project, an authenticated Cognito user, and a restricted sender. It is not needed to build or use the iOS app.

## Local checks

Use Node.js 22.13+ and run from this directory:

```bash
npm ci
npm run typecheck
npm test
```

These checks use synthetic data and require no credentials. Follow [AGENTS.md](AGENTS.md) when using an automated coding agent; agents must not read, write, or echo `.env`.

## Configure and run

Create your own local `.env` from `.env.example` and fill in its values yourself. Never commit it or paste its contents into an issue. Required configuration includes:

| Variable | Meaning |
| --- | --- |
| `PROJECT_ID`, `PROJECT_SECRET` | Your Spectrum/Photon project credentials |
| `PHOTON_ALLOWED_SENDER` | Exact sender identifier permitted to issue commands |
| `FLOATING_BRAIN_API_URL` | Your HTTPS API origin, without `/v1` |
| `COGNITO_AUTHORIZATION_ENDPOINT`, `COGNITO_TOKEN_ENDPOINT` | Your Cognito endpoints, sharing the same origin |
| `COGNITO_CLIENT_ID` | Your public Cognito app client ID |
| `COGNITO_REDIRECT_URI` | Local login callback; keep `http://127.0.0.1:8765/callback` unless both client and deployment are deliberately reconfigured |
| `PHOTON_RECIPIENT` | Recipient for the optional manual send command |

Deploy the backend using [sam/README.md](../sam/README.md) and use its outputs. The companion has no built-in deployment endpoints. It processes only incoming iMessage messages from the configured sender in a direct conversation. Groups, SMS, RCS, and messages without recognized service metadata are ignored.

```bash
npm run login
npm start
```

`login` runs a PKCE browser login with a callback bound to `127.0.0.1`. For a remote machine, use SSH local forwarding instead of exposing the callback publicly. Access tokens stay in memory. Refresh tokens use macOS Keychain; on Linux the default is `/run/auth/refresh-token`, which must be writable by the process, or an absolute path selected with `COGNITO_REFRESH_TOKEN_FILE`. The token file is written with owner-only permissions. Keep it outside the repository. See [SECURITY.md](../SECURITY.md) for retention and account cleanup limits.

Starting the companion connects to the real provider and can send replies. `npm run send` also sends a real message to `PHOTON_RECIPIENT`; use it only with a recipient you intend to contact.

## Current behavior

Commands include `query`, `today`, `archived`, `complete <task ID or exact text>`, `restore <task ID>`, and `help`. Completion and restore depend on the task types supported by the backend. Unrecognized text is echoed.

A `create ...` message is acknowledged by this process; that acknowledgment does not prove persistence. Text ingestion is handled by the separately configured Photon webhook. Register and configure it as described in the backend guide, then use `query` to verify the result. Starting this companion alone does not set up webhook ingestion.

The [Spectrum documentation](https://photon.codes/docs/spectrum-ts) describes the provider integration. Bundled third-party reference material is attributed in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
