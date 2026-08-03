# Floating Brain

Floating Brain is a native iOS app that syncs the active reminders in the `Floating Brain` Apple Reminders list to a private AWS-backed dashboard.

## What it does

- Signs in with Amazon Cognito using an iOS PKCE flow.
- Reads the `Floating Brain` list from Apple Reminders.
- Sends active reminders to an authenticated API Gateway endpoint.
- Does not sync completed reminders.
- Stores active reminders in DynamoDB with a 30-day TTL. The expiration is refreshed when an active task is synced.
- Supports manual sync, Shortcuts sync, and scheduled background refresh attempts.
- Includes a diagnostics page opened with the ladybug icon in the dashboard.

## Repository layout

```text
FloatingBrain/          iOS SwiftUI application
FloatingBrainTests/     iOS unit tests
sam/                    AWS SAM template and sync Lambda
pi/                     Raspberry Pi read-only dashboard helpers
scripts/                Deployment preflight checks
project_spec.md         Product and implementation specification
```

## Requirements

- macOS with Xcode and an iOS 17+ SDK
- AWS SAM CLI
- An authenticated AWS CLI profile named `floating-brain` for deployment
- An AWS account with Cognito, API Gateway, Lambda, and DynamoDB available

## Build and test the iOS app

Open `FloatingBrain.xcodeproj` in Xcode and run the `FloatingBrain` scheme on an iOS simulator or device.

Command-line build:

```bash
xcodebuild \
  -project FloatingBrain.xcodeproj \
  -scheme FloatingBrain \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath .build-sim \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

## Validate and deploy AWS

Run the local backend tests and validate the SAM template:

```bash
python3 -m unittest discover -s sam/tests -v
sam validate --template-file sam/template.yaml --lint
```

Deploy the development stack with the existing Cognito domain prefix:

```bash
sam deploy \
  --template-file sam/template.yaml \
  --stack-name floating-brain-dev \
  --parameter-overrides CognitoDomainPrefix=floating-brain-dev \
  --region us-east-1 \
  --profile floating-brain \
  --capabilities CAPABILITY_IAM \
  --resolve-s3 \
  --no-confirm-changeset \
  --no-fail-on-empty-changeset
```

The deployed stack exposes the API and Cognito outputs. Keep account-specific configuration and credentials out of source control.

## Debugging

Open the dashboard’s ladybug icon to inspect:

- authentication and Reminders permission state;
- last sync result and errors;
- background refresh scheduling state;
- API and Cognito configuration;
- a redacted diagnostics report that can be copied to the clipboard.

The diagnostics page intentionally excludes access tokens and reminder contents.

## Data retention

The Lambda filters completed items before writing. Active records receive an `expiresAt` Unix timestamp 30 days in the future, and DynamoDB TTL is enabled for that attribute. TTL deletion is asynchronous, so expiration is not an exact deletion deadline.

