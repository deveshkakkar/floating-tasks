# Security and data handling

Floating Brain is experimental. There is no published security support policy, supported release series, or response-time commitment yet.

## Report a vulnerability

Use this repository's **Security → Report a vulnerability** option if private vulnerability reporting is enabled. If it is unavailable, contact the maintainer through an established private channel and ask for a secure reporting route. Do not put credentials, personal task text, exploit details, or private logs in a public issue. A public issue may ask the maintainer to enable private reporting without disclosing the vulnerability.

Provide the affected commit, prerequisites, impact, and a minimal reproduction with synthetic data. Test only against accounts and infrastructure you control.

## Data flow and access

The iOS app reads reminders from the `Floating Brain` list. Sync sends active task identifiers and text, plus completion events containing completed reminder text for history, to your configured AWS API. Cognito authenticates app and companion requests; the API derives the user partition from the JWT subject. The share extension queues text locally until the app uploads it.

The optional Photon integration processes messages through an external messaging provider. Its webhook verifies signature freshness and an exact configured sender; it does not filter conversation type or direction. The separate companion replies only to inbound iMessage messages from its configured sender in a direct conversation, and ignores groups, SMS, RCS, and unknown service metadata. Deploying either integration expands the places where task content and phone identifiers are processed. Use accounts and conversations you control.

The Pi adapter accesses DynamoDB directly, so its runtime needs temporary AWS credentials and a policy restricted to the intended user partition. Credential provisioning is not implemented by the Pi modules.

## Storage and retention

| Location | Data and current behavior |
| --- | --- |
| Apple Reminders | Original reminders remain under the user's control. Cloud expiration is separate from deletion in Reminders. |
| DynamoDB tasks | Active tasks have a 30-day TTL refreshed by sync/capture. Missing Apple reminders are reconciled across syncs, archived, and marked for later expiry. TTL deletion is asynchronous and is not a deletion deadline. |
| DynamoDB daily selections | Daily selection records have a short TTL, currently two days. The same asynchronous deletion limitation applies. |
| S3 archives | Archived data is versioned and encrypted. The template retains the bucket when the stack is deleted and defines no lifecycle expiry, so archived versions persist until the operator removes them or configures retention. |
| iOS shared storage | Pending captures and widget task text are stored in the App Group container. Widget content and scheduled notification previews may expose task text. Pending captures do not have an automatic expiry. |
| Pi SQLite cache | Daily selections and display history are stored locally without automatic expiry or application-level encryption. Protect the device and remove its cache when decommissioning it. |
| Authentication | iOS uses Keychain. The companion keeps access tokens in memory and refresh tokens in macOS Keychain or a restricted local file on Linux. |
| Operational logs and messaging services | The template does not specify a CloudWatch log retention period. Review logs and provider retention settings for your deployment. Avoid logging task bodies, tokens, or webhook secrets. |

There is no complete account deletion or export workflow. Signing out is not a request to delete cloud data or queued captures. Before using real personal data, decide how to delete records, archive versions, caches, and logs across all components.

## Deployment configuration

Store real credentials outside source control. The iOS client ID and endpoints are public configuration, not secrets, but Xcode settings are embedded in the app and must never contain credentials. Use HTTPS endpoints, PKCE, narrowly scoped AWS permissions, and your own signing/provisioning configuration.

Before a public release, follow [docs/public-release.md](docs/public-release.md), review dependency advisories and all publishable Git refs, and enable private vulnerability reporting. Secret scanning is a useful check, not proof that a repository contains no sensitive information.
