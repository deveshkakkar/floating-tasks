# Floating Brain

Floating Brain is an experimental personal task dashboard. The iOS app syncs active reminders from an Apple Reminders list named **Floating Brain** to a backend you deploy in your own AWS account. The backend chooses a daily selection, which the app and widget display.

The repository is named `floating-tasks`. It contains working app and backend code alongside prototypes and design specifications. It is not a hosted service, and a fresh checkout has no configured cloud deployment.

## What is implemented

- An iOS 17+ SwiftUI app with Apple Reminders access, Cognito sign-in using PKCE, manual sync, Shortcuts integration, and opportunistic background refresh.
- A share extension that queues captured text and a widget that displays cached daily tasks.
- An AWS SAM backend with per-user task storage, daily selections, capture, completion, archive/restore endpoints, and an optional Photon webhook.
- An optional TypeScript messaging companion and Python modules for a Raspberry Pi reader/cache.

The Pi modules are not a finished display application. Analytics, hardware provisioning, and other ideas in [project_spec.md](project_spec.md), [DISPLAY_SPEC.md](DISPLAY_SPEC.md), [ANALYTICS_SPEC.md](ANALYTICS_SPEC.md), and [DESIGN.md](DESIGN.md) are specifications; they are not promises that every described feature exists.

## Start with local checks

The cross-platform checks need Python 3.12+ and Node.js 22.13+ with npm. They use fixtures and do not require AWS, Apple, or Photon credentials.

```bash
git clone https://github.com/deveshkakkar/floating-tasks.git
cd floating-tasks
npm ci --prefix floating
python3 scripts/check.py
```

For Python and configuration checks only, use `python3 scripts/check.py --python-only`. See [scripts/README.md](scripts/README.md) for the individual checks. GitHub Actions additionally validates the SAM template, scans for secrets, audits npm dependencies, and runs iOS tests on macOS.

## Run the iOS app

Use Xcode on macOS with an iOS 17 or newer SDK. Open `FloatingBrain.xcodeproj` and select the **FloatingBrain** scheme. The app can build without cloud configuration; sign-in and sync become available after you configure your own backend.

1. Follow [sam/README.md](sam/README.md) to deploy a development stack.
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, which is ignored by Git.
3. Set the API origin, Cognito authorization/token endpoints, and public app client ID from your stack outputs. Preserve the example's `https:/$()/` syntax: Xcode otherwise treats `//` as a comment. Do not append `/v1` to the API origin.
4. For a device build, set your own `DEVELOPMENT_TEAM` and provision the app and both extensions. If changing identifiers, update the app, share extension, and widget bundle IDs; all three entitlements; and the App Group identifiers in `SharedCapture` and `SharedWidgetData` consistently.
5. Create a Reminders list named **Floating Brain**, add a few synthetic tasks, sign in to your deployment, grant Reminders access, and sync.

The native OAuth callback is `floatingbrain://oauth/callback`. Build settings are embedded in the app; they must never contain passwords, client secrets, or access tokens. Background refresh is scheduled by iOS and is not a guaranteed delivery mechanism.

A simulator build check is available without signing:

```bash
xcodebuild -project FloatingBrain.xcodeproj -scheme FloatingBrain \
  -configuration Debug -sdk iphonesimulator -derivedDataPath .build-sim \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

## Components

| Directory | Purpose | Setup |
| --- | --- | --- |
| `FloatingBrain/`, `ShareExtension/`, `FloatingBrainWidget/` | iOS app and extensions | Instructions above |
| `sam/` | AWS infrastructure and Python API | [Backend guide](sam/README.md) |
| `floating/` | Optional Spectrum/Photon messaging companion | [Companion guide](floating/README.md) |
| `pi/` | Read-only DynamoDB adapter and SQLite cache | [Pi guide](pi/README.md) |
| `scripts/` | Local checks and deployment preflight | [Script guide](scripts/README.md) |

## Privacy, security, and release status

Task text leaves the device when you sync or capture to the cloud. Sync also sends completion events, including completed reminder text, for history. Widgets, notification previews, local caches, and optional messaging integrations can expose that text on other surfaces. DynamoDB expiry is asynchronous, and the archive bucket is retained without an expiry policy by default. See [SECURITY.md](SECURITY.md) for data handling, retention, and private reporting guidance.

Before publishing or distributing a deployment, work through the [public release checklist](docs/public-release.md). There is currently **no project license**; the owner must choose one or explicitly decide on source-available publication before presenting this as an open-source project. Third-party material is identified separately in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Development guidance is in [CONTRIBUTING.md](CONTRIBUTING.md).
