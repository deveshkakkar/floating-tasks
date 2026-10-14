# Dedicated Photon agent app cutover (candidate)

Intended behavior: keep the existing Floating Brain Photon project on task commands, and route every permitted owner iMessage in the new Photon project to the existing OpenClaw `agent:main:photon-personal` broker/session. Preserve weekly outbox delivery and deterministic owner controls in the agent project. Do not add recipients, external ports, model routes, or vault access.

Allowed candidate writes: this isolated `floating-photon-agent-20261014` worktree and a separate proposed Compose file. Deployment would change only the Spectrum services' image/config and the private owner-routing line after the new app identity and owner-only credential file are supplied. No old app credentials are rotated or printed. Keep the existing image, Compose preimage, routing preimage, broker state and new candidate image for rollback.

Acceptance: offline TypeScript tests and typecheck; a credential-free container smoke test for both modes; Compose validation; new project startup/authentication without exposing credentials; broker health; one owner-initiated agent message with a confirmed provider send receipt; old app task query still works. Automatic weekly delivery remains unverified until its next due run unless a separately approved one-off send is performed.

Limits: existing 384 MiB/0.5 CPU/64 PID Spectrum envelope per app, no public ports, no inferred external send, one broker and one agent project consumer. Stop if the new project identity/line or secure credential source is missing, or if an existing/uncertain send is in progress. Do not clear or replay uncertain sends to force cutover.
