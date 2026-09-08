# Floating Brain

Floating Brain is a native iOS app that syncs the active reminders in the `Floating Brain` Apple Reminders list to a private AWS-backed dashboard.

## What it does

- Signs in with Amazon Cognito using an iOS PKCE flow.
- Reads the `Floating Brain` list from Apple Reminders.
- Sends active reminders to an authenticated API Gateway endpoint.
- Does not sync completed reminders.
- Stores active reminders in DynamoDB with a 30-day TTL. The expiration is refreshed when an active task is synced.
- Supports manual sync, Shortcuts sync, and scheduled background refresh attempts.
- Accepts private brain dumps by text message through Photon webhooks.
- Includes a diagnostics page opened with the ladybug icon in the dashboard.
- Includes an archived-task view for inspecting deleted Apple Reminders records and restoring them.

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

The first deployment leaves the daily scheduler disabled until the Cognito user exists. After creating the user, retrieve its Cognito `sub` and redeploy with:

```bash
sam deploy \
  --template-file sam/template.yaml \
  --stack-name floating-brain-dev \
  --parameter-overrides \
    CognitoDomainPrefix=floating-brain-dev \
    DailySelectionUserId=<cognito-user-sub> \
  --region us-east-1 \
  --profile floating-brain \
  --capabilities CAPABILITY_IAM \
  --resolve-s3 \
  --no-confirm-changeset \
  --no-fail-on-empty-changeset
```

You can test selection immediately through `GET /v1/reminders/daily`; you do not need to wait for the 6:00 AM scheduler run.

The deployed stack exposes the API and Cognito outputs. Keep account-specific configuration and credentials out of source control.

## Text brain dumps with Photon

Photon sends signed inbound messages to the public `POST /v1/photon/webhook` route. The Lambda verifies the signature and timestamp, accepts only the configured sender, deduplicates Photon message IDs, and stores text as an active `PHOTON` item. Attachments and other message types are ignored.

After the stack is deployed, register the webhook in Photon using the project ID and secret from your Photon account:

```bash
curl --request POST \
  --url https://spectrum.photon.codes/projects/<photon-project-id>/webhooks/ \
  --user '<photon-project-id>:<photon-project-secret>' \
  --header 'Content-Type: application/json' \
  --data '{"webhookUrl":"https://<api-id>.execute-api.<region>.amazonaws.com/v1/photon/webhook"}'
```

Save the returned `signingSecret`; Photon returns it only when the webhook is created. Redeploy with `PhotonUserId` set to the Cognito user `sub`, `PhotonAllowedSender` set to your exact Photon sender ID (normally your E.164 phone number), and `PhotonWebhookSigningSecret` set to that secret. Keep all three values out of source control. The Photon endpoint is intentionally unauthenticated at API Gateway because Photon authenticates it with its signed webhook headers.

## Release checklist

Before TestFlight or production deployment:

1. Deploy the SAM stack with a production stack name, unique Cognito domain prefix, and the intended `DailySelectionUserId`.
2. Copy the generated Cognito and API outputs into the app’s release configuration; do not commit user-specific values or tokens.
3. Confirm the App ID, widget and Share Extension bundle IDs, App Group, URL scheme, and push/background capabilities in the Apple Developer account.
4. Archive with a real signing team and verify the app, widget, and Share Extension are all embedded in the archive.
5. Run the physical-device smoke test after signing the archive: sign-in, sync, capture, restore, Siri, Share Extension, widget refresh, and notification delivery.
6. Verify the production Lambda logs, DynamoDB TTL, Cognito user creation, and scheduled daily-selection invocation.

The archived-task endpoints are `GET /v1/reminders/archived` and `POST /v1/reminders/restore` with `{ "externalId": "..." }`. Restore is intentionally limited to records sourced from Apple Reminders; Share Extension and Siri captures are never soft-deleted by sync.

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
