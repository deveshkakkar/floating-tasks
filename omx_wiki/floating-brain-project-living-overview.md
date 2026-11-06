---
title: "Floating Brain Project Living Overview"
tags: ["project", "architecture", "dynamodb", "notifications", "siri", "widget", "share-extension", "decisions", "daily-selection", "pagination", "spectrum", "cognito"]
created: 2026-08-09T23:57:25.963Z
updated: 2026-09-08T04:35:17.761Z
sources: []
links: []
category: architecture
confidence: medium
schemaVersion: 1
---

# Floating Brain Project Living Overview

> Historical development notes. For current setup, configuration, limitations,
> and verification commands, start with [README.md](../README.md) and
> [CONTRIBUTING.md](../CONTRIBUTING.md). Test counts and deployment observations
> below describe earlier work, not the current release status.

# Floating Brain — Living Project Overview

Last updated: 2026-08-09

## Product intent

Floating Brain is a private task capture and reminder app. It synchronizes the user’s Floating Brain Apple Reminders list to DynamoDB, then surfaces a small set of tasks through an 8:00 AM notification, Siri, a Share Extension, and a home-screen widget.

## Current product behavior

- The app schedules a local notification for 8:00 AM containing up to three tasks.
- Notification content is selected when the app schedules the request; it is not fetched from DynamoDB at the moment the notification fires.
- The app uses a dark-mode-compatible system background.
- The app icon is pixel-art: a coral/pink brain with lavender cobwebs on a dark indigo background.
- The app, Share Extension, and Widget Extension use the App Group `group.com.floatingbrain.app`.

## Data architecture

DynamoDB is the cloud source of truth for signed-in users. The current table is `FloatingBrain-floating-brain-dev` in `us-east-1`, keyed by `PK` and `SK`. Reminder records use `PK=USER#<cognito-sub>` and `SK=REMINDER#<id>`.

Sources currently include:

- `APPLE_REMINDERS` — records synchronized from the device’s Floating Brain list.
- `SHARE_EXTENSION` — captures created by sharing text or websites.

The active-reminders API returns only active records. The iOS app caches the latest three active cloud tasks in the App Group for the widget and reloads widget timelines after cloud refresh.

## Capture paths

### Apple Reminders

The app reads the Floating Brain list locally and uploads active reminders to the authenticated API. Device-originated records can be soft-deleted after three successful sync omissions.

### Share Extension

The Share Extension accepts text and website shares, queues them in the App Group, and uploads them to DynamoDB on the next app refresh or sign-in. URL attachments are preferred over a web page title so website shares preserve the actionable link.

### Siri / App Intents

Supported phrases include:

- “Add a task to Floating Brain”
- “Remember this with Floating Brain”
- “Sync Floating Brain”

Siri writes the task to the shared capture inbox. The app uploads it to DynamoDB on the next refresh.

### Widget

The WidgetKit extension displays up to three active tasks from the App Group cache. It does not make an unauthenticated DynamoDB request directly. The widget is refreshed after app sync and on a periodic timeline.

## Important decisions

1. Keep DynamoDB as the cloud source of truth because the app needs authenticated multi-device task storage and simple per-user queries.
2. Use local App Group caching for widgets and local notifications because extensions and scheduled local notifications should not depend on an active authenticated network request.
3. Only `APPLE_REMINDERS` records may be soft-deleted by Apple Reminders sync. DynamoDB-native tasks such as Siri and Share Extension captures must remain active when absent from the device’s Apple Reminders list.
4. Keep the first implementation dependency-light: SwiftUI, WidgetKit, App Intents, EventKit, AWS SAM/Lambda, Cognito, and DynamoDB.
5. App and embedded targets must share the development team, App Group, and correctly prefixed bundle identifiers. Custom extension plists must explicitly define `CFBundleExecutable` and `NSExtension`.

## Random task retrieval decision

The current implementation fetches active cloud tasks and selects up to three in the app. This is appropriate for the current small task volume and avoids an extra index.

If task volume or random retrieval frequency grows, add a sparse GSI containing only active tasks with a per-user partition and random sort key. Query from a random pivot and wrap around to retrieve three tasks without reading the entire user partition. Do not rely on a FilterExpression to reduce cost: DynamoDB applies filtering after reading and charges based on the data read.

For the current low and irregular development traffic, DynamoDB on-demand capacity is likely preferable to provisioned capacity. Re-evaluate before production.

## Known operational lessons

- A widget that shows only two tasks may be reflecting the actual active DynamoDB state. Check record status and source before changing widget code.
- Previous sync behavior marked older cloud records `DELETED` when they were absent from the device. The backend now protects non-Apple sources, but already-deleted records require explicit restoration or re-capture.
- Custom extension Info.plists need explicit bundle metadata; otherwise installation errors can mention missing `CFBundleExecutable` or `NSExtension`.
- The local development environment has had unavailable CoreSimulator runtimes and permission errors in Xcode DerivedData; device builds remain the authoritative integration test.

## Validation baseline

- SAM template validation passes.
- Backend unit tests currently pass: 5 tests.
- Xcode project parsing lists the app, Share Extension, and Widget target.
- Plist and entitlements validation passes.
- Full device installation, Siri execution, Share Extension upload, and widget rendering still need physical-device verification after each target/signing change.

## Next ideas

- Add an active-task GSI only when scale justifies it.
- Consider a true server-side 8:00 AM push path if notification content must be generated at delivery time.
- Add a clear in-app cloud-task view so users can inspect and restore archived/deleted records.
- Add integration tests against a local or deployed API for capture, active retrieval, and source-aware deletion behavior.

---

## Update (2026-08-10T00:07:56.593Z)

# Floating Brain — Living Project Overview

Last updated: 2026-08-09

## Product intent

Floating Brain is a private task capture and reminder app. It synchronizes the user’s Floating Brain Apple Reminders list to DynamoDB, then surfaces a small set of tasks through an 8:00 AM notification, Siri, a Share Extension, and a home-screen widget.

## Current product behavior

- The first successful cloud refresh of each local calendar day chooses up to three active tasks at random.
- The daily selection is persisted in the shared App Group and reused by the app screen, 8:00 AM notification, and widget until the next day.
- The app displays the selection in a dedicated Today’s Tasks screen and a dashboard card.
- Notification content is scheduled locally; it is not fetched from DynamoDB at the moment the notification fires.
- The app uses a dark-mode-compatible system background.
- The app icon is pixel-art: a coral/pink brain with lavender cobwebs on a dark indigo background.
- The app, Share Extension, and Widget Extension use the App Group `group.com.floatingbrain.app`.

## Data architecture

DynamoDB is the cloud source of truth for signed-in users. The current table is `FloatingBrain-floating-brain-dev` in `us-east-1`, keyed by `PK` and `SK`. Reminder records use `PK=USER#<cognito-sub>` and `SK=REMINDER#<id>`.

Sources currently include:

- `APPLE_REMINDERS` — records synchronized from the device’s Floating Brain list.
- `SHARE_EXTENSION` — captures created by sharing text or websites.

The active-reminders API returns only active records. The iOS app caches the daily selection in the App Group for the widget and reloads widget timelines after cloud refresh.

## Capture paths

### Apple Reminders

The app reads the Floating Brain list locally and uploads active reminders to the authenticated API. Device-originated records can be soft-deleted after three successful sync omissions.

### Share Extension

The Share Extension accepts text and website shares, queues them in the App Group, and uploads them to DynamoDB on the next app refresh or sign-in. URL attachments are preferred over a web page title so website shares preserve the actionable link.

### Siri / App Intents

Supported phrases include:

- “Add a task to Floating Brain”
- “Remember this with Floating Brain”
- “Sync Floating Brain”

Siri writes the task to the shared capture inbox. The app uploads it to DynamoDB on the next refresh.

### Widget

The WidgetKit extension displays the persisted daily selection from the App Group. It does not make an unauthenticated DynamoDB request directly. The widget is refreshed after app sync and on a periodic timeline.

## Important decisions

1. Keep DynamoDB as the cloud source of truth because the app needs authenticated multi-device task storage and simple per-user queries.
2. Use local App Group caching for widgets, the Today’s Tasks screen, and local notifications because extensions and scheduled local notifications should not depend on an active authenticated network request.
3. Persist one random selection per local calendar day so all surfaces show the same three tasks throughout that day.
4. Only `APPLE_REMINDERS` records may be soft-deleted by Apple Reminders sync. DynamoDB-native tasks such as Siri and Share Extension captures must remain active when absent from the device’s Apple Reminders list.
5. Keep the first implementation dependency-light: SwiftUI, WidgetKit, App Intents, EventKit, AWS SAM/Lambda, Cognito, and DynamoDB.
6. App and embedded targets must share the development team, App Group, and correctly prefixed bundle identifiers. Custom extension plists must explicitly define `CFBundleExecutable` and `NSExtension`.

## Random task retrieval decision

The current implementation fetches active cloud tasks once per refresh and selects up to three in the app. This is appropriate for the current small task volume and avoids an extra index.

If task volume or random retrieval frequency grows, add a sparse GSI containing only active tasks with a per-user partition and random sort key. Query from a random pivot and wrap around to retrieve three tasks without reading the entire user partition. Do not rely on a FilterExpression to reduce cost: DynamoDB applies filtering after reading and charges based on the data read.

For the current low and irregular development traffic, DynamoDB on-demand capacity is likely preferable to provisioned capacity. Re-evaluate before production.

## Known operational lessons

- A widget that shows only two tasks may be reflecting the actual active DynamoDB state. Check record status and source before changing widget code.
- Previous sync behavior marked older cloud records `DELETED` when they were absent from the device. The backend now protects non-Apple sources, but already-deleted records require explicit restoration or re-capture.
- Custom extension Info.plists need explicit bundle metadata; otherwise installation errors can mention missing `CFBundleExecutable` or `NSExtension`.
- The local development environment has had unavailable CoreSimulator runtimes and permission errors in Xcode DerivedData; device builds remain the authoritative integration test.

## Validation baseline

- SAM template validation passes.
- Backend unit tests currently pass: 5 tests.
- Xcode project parsing lists the app, Share Extension, and Widget target.
- Plist and entitlements validation passes.
- Full device installation, Siri execution, Share Extension upload, and widget rendering still need physical-device verification after each target/signing change.

## Next ideas

- Add an active-task GSI only when scale justifies it.
- Consider a true server-side 8:00 AM push path if notification content must be generated at delivery time.
- Add a clear in-app cloud-task view so users can inspect and restore archived/deleted records.
- Add integration tests against a local or deployed API for capture, active retrieval, and source-aware deletion behavior.

---

## Update (2026-08-10T00:13:05.460Z)

# Floating Brain — Living Project Overview

Last updated: 2026-08-09

## Product intent

Floating Brain is a private task capture and reminder app. It synchronizes the user’s Floating Brain Apple Reminders list to DynamoDB, then surfaces tasks through an 8:00 AM notification, Siri, a Share Extension, a home-screen widget, and in-app task browsing.

## Current product behavior

- The first successful cloud refresh of each local calendar day chooses up to three active tasks at random.
- The daily selection is persisted in the shared App Group and reused by the app screen, 8:00 AM notification, and widget until the next day.
- The app displays the selection in a dedicated Today’s Tasks screen and a dashboard card.
- The app includes an All Tasks screen that loads active cloud tasks in pages of 25 with a DynamoDB cursor and a Load more action.
- Notification content is scheduled locally; it is not fetched from DynamoDB at the moment the notification fires.
- The app uses a dark-mode-compatible system background.
- The app icon is pixel-art: a coral/pink brain with lavender cobwebs on a dark indigo background.
- The app, Share Extension, and Widget Extension use the App Group `group.com.floatingbrain.app`.

## Data architecture

DynamoDB is the cloud source of truth for signed-in users. The current table is `FloatingBrain-floating-brain-dev` in `us-east-1`, keyed by `PK` and `SK`. Reminder records use `PK=USER#<cognito-sub>` and `SK=REMINDER#<id>`.

Sources currently include:

- `APPLE_REMINDERS` — records synchronized from the device’s Floating Brain list.
- `SHARE_EXTENSION` — captures created by sharing text or websites.

The active-reminders API supports `limit` and an opaque, base64url-encoded `cursor`. Each request queries one DynamoDB page and returns `items` plus `nextCursor`. The iOS client exposes both page fetches for the All Tasks screen and an internal loop for callers that need the complete active set, such as daily selection.

## Capture paths

### Apple Reminders

The app reads the Floating Brain list locally and uploads active reminders to the authenticated API. Device-originated records can be soft-deleted after three successful sync omissions.

### Share Extension

The Share Extension accepts text and website shares, queues them in the App Group, and uploads them to DynamoDB on the next app refresh or sign-in. URL attachments are preferred over a web page title so website shares preserve the actionable link.

### Siri / App Intents

Supported phrases include:

- “Add a task to Floating Brain”
- “Remember this with Floating Brain”
- “Sync Floating Brain”

Siri writes the task to the shared capture inbox. The app uploads it to DynamoDB on the next refresh.

### Widget

The WidgetKit extension displays the persisted daily selection from the App Group. It does not make an unauthenticated DynamoDB request directly. The widget is refreshed after app sync and on a periodic timeline.

## Important decisions

1. Keep DynamoDB as the cloud source of truth because the app needs authenticated multi-device task storage and simple per-user queries.
2. Use local App Group caching for widgets, the Today’s Tasks screen, and local notifications because extensions and scheduled local notifications should not depend on an active authenticated network request.
3. Persist one random selection per local calendar day so all surfaces show the same three tasks throughout that day.
4. Use cursor pagination for browsing all active tasks; do not load an unbounded task list into the app screen at once.
5. Only `APPLE_REMINDERS` records may be soft-deleted by Apple Reminders sync. DynamoDB-native tasks such as Siri and Share Extension captures must remain active when absent from the device’s Apple Reminders list.
6. Keep the first implementation dependency-light: SwiftUI, WidgetKit, App Intents, EventKit, AWS SAM/Lambda, Cognito, and DynamoDB.
7. App and embedded targets must share the development team, App Group, and correctly prefixed bundle identifiers. Custom extension plists must explicitly define `CFBundleExecutable` and `NSExtension`.

## Random task retrieval decision

The current implementation fetches active cloud tasks in pages and selects up to three in the app. This is appropriate for the current small task volume and avoids an extra index.

If task volume or random retrieval frequency grows, add a sparse GSI containing only active tasks with a per-user partition and random sort key. Query from a random pivot and wrap around to retrieve three tasks without reading the entire user partition. Do not rely on a FilterExpression to reduce cost: DynamoDB applies filtering after reading and charges based on the data read.

For the current low and irregular development traffic, DynamoDB on-demand capacity is likely preferable to provisioned capacity. Re-evaluate before production.

## Known operational lessons

- A widget that shows only two tasks may be reflecting the actual active DynamoDB state. Check record status and source before changing widget code.
- Previous sync behavior marked older cloud records `DELETED` when they were absent from the device. The backend now protects non-Apple sources, but already-deleted records require explicit restoration or re-capture.
- Custom extension Info.plists need explicit bundle metadata; otherwise installation errors can mention missing `CFBundleExecutable` or `NSExtension`.
- The local development environment has had unavailable CoreSimulator runtimes and permission errors in Xcode DerivedData; device builds remain the authoritative integration test.

## Validation baseline

- SAM template validation passes.
- Backend unit tests currently pass: 7 tests.
- Xcode project parsing lists the app, Share Extension, and Widget target.
- Plist and entitlements validation passes.
- Full device installation, Siri execution, Share Extension upload, pagination, and widget rendering still need physical-device verification after each target/signing change.

## Next ideas

- Add an active-task GSI only when scale justifies it.
- Consider a true server-side 8:00 AM push path if notification content must be generated at delivery time.
- Add a clear in-app cloud-task view so users can inspect and restore archived/deleted records.
- Add integration tests against a local or deployed API for capture, active retrieval, pagination, and source-aware deletion behavior.

---

## Update (2026-09-08T04:35:17.761Z)

# Floating Brain — Current Project Snapshot

Last updated: 2026-09-08

## Product behavior

Floating Brain syncs active Apple Reminders from the `Floating Brain` list to DynamoDB and surfaces a server-owned daily selection through the iOS app, widget, and local 8:00 AM notification.

The daily selection contains up to three tasks and is persisted for the calendar day. The notification is one local notification whose body contains the selected tasks; iOS may visually truncate a collapsed notification. If the server selection was created while only one or two tasks were active, it remains that size for the rest of the day by design.

## Messaging bridge

The local Spectrum/iMessage bridge lives under `floating/` and supports:

- Create: `create`, `add`
- Query active tasks: `query`, `fetch`, `show`, `list`
- Daily selection: `today`, `daily`, `what should I do`
- Archived tasks: `archived`, `archive`, `history`
- Restore: `restore <task ID or exact text>`
- Complete: `complete <task ID or exact text>`, `finish`, `done`
- Help: `help`, `commands`

Unknown messages still echo while additional intents are added. Command messages are filtered from Photon task capture so queries and actions do not become accidental tasks.

## Authentication

The bridge uses Cognito Authorization Code + PKCE. Run `npm run login` once from `floating/`; see [the companion setup](../floating/README.md) for current token-storage behavior. The Cognito client accepts the localhost callback `http://127.0.0.1:8765/callback`. Each deployment supplies its own API and Cognito configuration; access tokens should not be stored in `.env`.

## Backend

Use the API origin returned by your own SAM stack. Deployment-specific endpoints
are intentionally omitted from these notes.

Authenticated routes include active, daily, archived, restore, capture, sync, and completion. Completion marks cloud-created tasks complete; Apple Reminders tasks must be completed in Apple Reminders so the source of truth remains consistent. Restore is limited to deleted Apple Reminders records.

The public Photon webhook verifies signatures, restricts the configured sender, deduplicates message IDs, captures brain dumps, and ignores command messages.

## Validation

- 29 backend unit tests pass.
- TypeScript compilation passes.
- Python compilation passes.
- SAM template lint passes.
- The backend and Cognito localhost callback changes have been deployed successfully.

## Open follow-up

Investigate whether reduced notification task counts come from iOS collapsed-notification rendering or from the persisted daily selection being created before all active tasks were synchronized. Use the app diagnostics `Server selection count` to distinguish those cases.
