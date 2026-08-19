Below is an implementation-ready specification for the **Floating Brain** MVP.

# Floating Brain Dashboard — Technical Specification

**Status:** Draft for implementation
**Version:** 1.0
**Target platform:** iPhone, AWS, Raspberry Pi Zero W
**Primary task source:** Apple Reminders
**Dashboard display:** Raspberry Pi-driven apartment dashboard, with future support for the reTerminal E1001 e-paper display

---

## 1. Overview

Floating Brain is a personal task-resurfacing system that allows the user to capture thoughts, tasks, ideas, and reminders through Apple Reminders and later rediscover a small randomized selection on an apartment dashboard.

The user will continue using Apple Reminders as the only task-capture interface. A lightweight iOS helper application will securely synchronize reminders from a designated Apple Reminders list to AWS.

The server will select and persist three items for the current day. The iOS app, widgets, notifications, and Raspberry Pi will read that same server-owned selection. The Raspberry Pi retains read-only DynamoDB access and caches the daily selection locally for offline display.

The Raspberry Pi will not:

* Receive reminders directly from the iPhone
* Host a public or private ingestion API
* Write to DynamoDB
* Update task completion state
* Run the Apple Reminders synchronization process
* Expose services to the public internet

---

## 2. Goals

The system must:

1. Allow thoughts and tasks to be captured through Apple Reminders.
2. Support capture through Siri, the Reminders app, and the iOS Share Sheet.
3. Synchronize a designated Reminders list to DynamoDB.
4. Avoid permanent AWS credentials or shared API secrets on the iPhone.
5. Avoid public unauthenticated AWS endpoints.
6. Give the Raspberry Pi read-only access to DynamoDB.
7. Select three active reminders for display each day.
8. Return the same three reminders throughout the day.
9. Avoid frequently repeating recently shown reminders.
10. Continue operating when the Pi temporarily loses internet access.
11. Be inexpensive enough for personal usage and designed to remain within low-volume AWS usage limits.

---

## 3. Non-Goals

The first release will not:

* Replace Apple Reminders as the task-management application
* Allow tasks to be completed directly from the dashboard
* Support multiple users or shared household task lists
* Provide bidirectional synchronization from DynamoDB to Apple Reminders
* Provide an AWS-hosted management interface
* Support attachments, images, subtasks, or reminder notes
* Provide machine-learning-based task selection
* Guarantee immediate background synchronization after every reminder change
* Require the reTerminal E1001 display for initial testing

---

## 4. High-Level Architecture

```text
Apple Reminders
      ↓
Floating Brain iOS Helper
      ↓
Amazon Cognito authentication
      ↓
API Gateway HTTP API
      ↓
Write-only Lambda function
      ↓
Amazon DynamoDB
      ↑
Read-only AWS credentials
      ↑
Raspberry Pi Zero W
      ↓
Local daily-selection cache
      ↓
Dashboard renderer
      ↓
Future reTerminal E1001 display
```

---

## 5. System Components

### 5.1 Apple Reminders

Apple Reminders is the authoritative capture interface.

A dedicated list named:

```text
Floating Brain
```

will contain the reminders eligible for dashboard synchronization.

Users may add reminders through:

* Siri
* The Apple Reminders application
* The iOS Share Sheet
* Apple Shortcuts
* Other Apple applications that can create reminders

The system will initially synchronize:

* Reminder identifier
* Title
* Completion status
* Creation date
* Modification date
* Due date, when present
* Priority, when present

Reminder notes, URLs, attachments, subtasks, locations, and recurrence rules are outside the MVP unless they are available without materially increasing complexity.

---

### 5.2 Floating Brain iOS Helper

A small native iOS application will bridge Apple Reminders and AWS.

The application is not intended to replace Apple Reminders. Its responsibilities are limited to authorization, synchronization, status reporting, and optional Shortcut integration.

#### Required technologies

* Swift
* SwiftUI
* EventKit
* URLSession
* AuthenticationServices or AWS-supported OAuth flow
* Keychain Services
* App Intents for Shortcuts integration

#### Responsibilities

The application must:

1. Request access to Apple Reminders through EventKit.
2. Locate the `Floating Brain` list.
3. Read reminders from that list.
4. Authenticate the user through Amazon Cognito.
5. Obtain short-lived authentication tokens.
6. Store refresh credentials or tokens in the iOS Keychain.
7. Send reminder changes to the AWS ingestion API.
8. Retry failed synchronization attempts.
9. Display the last successful synchronization time.
10. Expose a `Sync Floating Brain` App Intent for Apple Shortcuts.
11. Never contain a hard-coded AWS access key or shared application secret.

#### Minimum user interface

The app should contain one screen showing:

* Reminders permission status
* Cognito login status
* Selected Reminders list
* Number of active reminders found
* Number of completed reminders found
* Last successful sync time
* Last sync result
* `Sync Now` button
* `Sign Out` button

---

### 5.3 Amazon Cognito

Amazon Cognito will authenticate the iOS user.

For the MVP, the system will support one user account.

#### Recommended configuration

* Cognito User Pool
* App client configured for a native mobile application
* Authorization Code flow with PKCE
* No client secret embedded in the iOS application
* Short-lived access tokens
* Refresh-token rotation where supported
* Hosted UI or standards-based OAuth login flow

Cognito will issue a JWT access token. The iOS application will attach the token to API requests:

```http
Authorization: Bearer <access-token>
```

---

### 5.4 API Gateway

An Amazon API Gateway HTTP API will provide the authenticated ingestion interface.

The API must use a JWT authorizer linked to the Cognito User Pool.

Requests without a valid JWT must be rejected before Lambda invocation.

#### Required endpoints

```text
POST /v1/reminders/sync
GET  /v1/sync/status
```

The status endpoint is optional for the first release but recommended for troubleshooting.

The API will not expose a public endpoint that accepts a shared header secret.

---

### 5.5 Write Lambda

The ingestion Lambda will process synchronization requests from the iOS application.

#### Responsibilities

The Lambda must:

1. Trust only requests authenticated by API Gateway.
2. Obtain the user identifier from validated JWT claims.
3. Validate request size and JSON structure.
4. Enforce a maximum number of reminders per request.
5. Validate text length and date formats.
6. Upsert new or modified reminders.
7. Mark missing or completed reminders inactive.
8. Prevent users from writing to another user’s partition.
9. Return a synchronization summary.
10. Avoid logging reminder text.

#### Lambda permissions

The Lambda role should be limited to:

```text
dynamodb:PutItem
dynamodb:UpdateItem
dynamodb:BatchWriteItem
dynamodb:TransactWriteItems
dynamodb:GetItem
dynamodb:Query
```

These actions must be restricted to the Floating Brain table.

The Lambda role must not have permission to:

* Scan unrelated tables
* Delete the DynamoDB table
* Create AWS resources
* Access IAM
* Access S3
* Invoke arbitrary Lambda functions
* Modify API Gateway or Cognito

Although the Lambda is primarily a write component, limited reads may be required to compare synchronization state and safely perform idempotent updates.

---

### 5.6 DynamoDB

DynamoDB will be the cloud system of record for synchronized reminders.

The table will use a composite primary key.

#### Table name

```text
FloatingBrain
```

#### Primary key

```text
PK — partition key
SK — sort key
```

#### Reminder record

```json
{
  "PK": "USER#<cognito-user-id>",
  "SK": "REMINDER#<apple-reminder-id>",
  "entityType": "REMINDER",
  "text": "Replace the bedroom air filter",
  "status": "ACTIVE",
  "createdAt": "2026-07-31T20:00:00Z",
  "modifiedAt": "2026-07-31T20:05:00Z",
  "syncedAt": "2026-07-31T20:06:00Z",
  "dueAt": null,
  "priority": 0,
  "source": "APPLE_REMINDERS",
  "schemaVersion": 1
}
```

#### Supported status values

```text
ACTIVE
COMPLETED
DELETED
```

The system should use soft deletion rather than immediately removing records.

#### Sync-state record

```json
{
  "PK": "USER#<cognito-user-id>",
  "SK": "SYNC#STATE",
  "entityType": "SYNC_STATE",
  "lastSyncAt": "2026-07-31T20:06:00Z",
  "lastSyncId": "uuid",
  "activeCount": 25,
  "completedCount": 8,
  "schemaVersion": 1
}
```

#### Capacity mode

Provisioned capacity is preferred for predictable, low-volume usage when the account’s applicable DynamoDB allowances support it.

Initial capacity:

```text
Read capacity units: 5
Write capacity units: 5
```

Auto scaling should initially remain disabled unless usage requires it.

Point-in-time recovery may be disabled for the MVP if minimizing cost is more important than recovery protection. This decision should be revisited after the system becomes valuable to the user.

---

## 6. Synchronization Model

### 6.1 Source of Truth

Apple Reminders is the source of truth for:

* Reminder text
* Completion status
* Deletion status
* Due dates
* Priority

DynamoDB is a synchronized cloud copy used by the dashboard.

The Raspberry Pi must never change reminder state in DynamoDB.

---

### 6.2 Full Sync

The MVP may use a full-list synchronization because the expected number of reminders is small.

The iOS app sends all reminders currently visible in the `Floating Brain` list.

Example request:

```json
{
  "syncId": "0d8c8f21-3c42-42d2-a5d8-2b9037cb6755",
  "generatedAt": "2026-07-31T20:06:00Z",
  "listName": "Floating Brain",
  "items": [
    {
      "externalId": "apple-reminder-123",
      "text": "Replace the bedroom air filter",
      "completed": false,
      "createdAt": "2026-07-30T13:00:00Z",
      "modifiedAt": "2026-07-31T19:55:00Z",
      "dueAt": null,
      "priority": 0
    }
  ]
}
```

#### Limits

Initial API limits:

```text
Maximum reminders per request: 500
Maximum reminder title length: 500 characters
Maximum request body size: 512 KB
Maximum requests per user: 30 per minute
```

---

### 6.3 Idempotency

Every synchronization request must contain a unique `syncId`.

The backend must safely handle repeated submission of the same request.

Replaying a successful synchronization must not create duplicate reminders or corrupt completion state.

Apple’s reminder identifier will be used as the external identifier.

Because external identifiers may contain characters unsuitable for direct DynamoDB keys, the implementation may store either:

* The original identifier after safe encoding, or
* A SHA-256 hash of the identifier

The raw external identifier should not be logged.

---

### 6.4 Completion and Deletion

When a reminder is marked complete in Apple Reminders:

```text
status = COMPLETED
```

When a reminder previously synchronized is no longer present in the list, the backend may mark it:

```text
status = DELETED
```

A grace period is recommended before treating a missing reminder as deleted, because EventKit retrieval or synchronization may occasionally return incomplete results.

Suggested rule:

* First missing sync: set `missingSince`
* Missing for three consecutive successful syncs: set `status = DELETED`

---

### 6.5 Sync Triggers

The iOS application should support:

* Manual synchronization from the app
* Manual synchronization through a Shortcut
* Personal automation when joining home Wi-Fi
* Optional scheduled synchronization
* Synchronization when the app becomes active, subject to throttling

The system must not depend on guaranteed continuous iOS background execution.

---

## 7. Raspberry Pi Reader

### 7.1 Responsibilities

The Raspberry Pi application must:

1. Authenticate to AWS using temporary credentials.
2. Read the server-owned daily selection from DynamoDB.
3. Never write, update, or delete DynamoDB records.
4. Never select or shuffle reminders locally.
5. Cache the selected reminders locally.
6. Reuse the cached selection throughout the day.
7. Continue displaying the cached selection if AWS is unavailable.
8. Provide data to the dashboard renderer.
9. Store display history locally.
10. Avoid repeatedly showing recently displayed reminders.

---

### 7.2 Pi Authentication

The preferred authentication model is:

```text
AWS IoT Core X.509 certificate
        ↓
AWS IoT credentials provider
        ↓
Temporary AWS role credentials
        ↓
Read-only DynamoDB access
```

The Pi will store:

* Device certificate
* Device private key
* AWS IoT root certificate
* IoT credentials-provider endpoint
* Role alias

The Pi must not store a permanent IAM user access key.

Certificate and key permissions:

```bash
chmod 600 device-certificate.pem.crt
chmod 600 private.pem.key
```

The Pi’s IoT certificate must be individually revocable.

---

### 7.3 Pi IAM Role

The Raspberry Pi role will be restricted to read operations on one DynamoDB table and one user partition.

Base policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadFloatingBrainTable",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:<region>:<account-id>:table/FloatingBrain"
    }
  ]
}
```

A `Scan` permission should be avoided.

The application should query a known partition:

```text
PK = USER#<configured-user-id>
```

Where practical, IAM conditions should restrict access to that leading partition key.

---

### 7.4 Local Storage

The Pi will maintain a local SQLite database:

```text
/opt/floating-brain/data/floating-brain.db
```

Suggested tables:

```sql
CREATE TABLE daily_selection (
    selection_date TEXT NOT NULL,
    slot INTEGER NOT NULL,
    reminder_id TEXT NOT NULL,
    reminder_text TEXT NOT NULL,
    selected_at TEXT NOT NULL,
    PRIMARY KEY (selection_date, slot)
);

CREATE TABLE display_history (
    reminder_id TEXT PRIMARY KEY,
    last_shown_date TEXT NOT NULL,
    show_count INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE sync_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

The local database is used only for dashboard state. It is not synchronized back to AWS.

---

## 8. Daily Selection Algorithm

### 8.1 Daily Stability

The server materializes one ordered `DAILY#<local-date>` record shortly after the start of each configured local day. The same three reminders must be displayed for the full local calendar day.

The scheduled server job is the normal creation path. The daily API endpoint uses the same idempotent ensure operation as a recovery path if the scheduled job is missed.

When the dashboard loads:

1. Determine the current local date.
2. Check the local SQLite `daily_selection` table.
3. If three records already exist for today, return them.
4. Otherwise, read the server-owned `DAILY#<local-date>` record from DynamoDB.
5. Store the server-provided ordered items in SQLite.
6. Return the saved selection.

---

### 8.2 Server Eligibility Rules

A reminder is eligible when:

```text
status = ACTIVE
text is not empty
```

The server applies the eligibility and repetition policy when it creates the daily record. Consumers do not reapply or reinterpret those rules.

If fewer than three reminders remain:

1. Reduce the exclusion window from seven days to three days.
2. If still insufficient, remove the exclusion window.
3. If fewer than three active reminders exist, display all available reminders.

---

### 8.3 Controlled Randomness

The server performs randomized selection once when creating the daily record. The first successful conditional write wins; later requests never reshuffle the day.

Optional weighting:

* Older reminders receive greater weight.
* Reminders never displayed receive the highest weight.
* Recently shown reminders receive the lowest weight.
* Priority reminders may receive a modest weighting increase.

Pure random selection without history protection should not be used.

---

### 8.4 Text Length

The dashboard renderer must handle long reminder titles.

Recommended behavior:

* Preserve the full text in local data.
* Wrap text across lines.
* Display a maximum of three lines per item.
* Truncate visually with an ellipsis when necessary.
* Do not modify the underlying reminder.

---

## 9. Local Dashboard Interface

The Pi application should expose an internal Python interface first. A local HTTP endpoint may be added later for display integration.

Suggested local response:

```json
{
  "date": "2026-07-31",
  "generatedAt": "2026-07-31T06:00:04-07:00",
  "source": "dynamodb",
  "items": [
    {
      "slot": 1,
      "id": "reminder-hash-1",
      "text": "Replace the bedroom air filter"
    },
    {
      "slot": 2,
      "id": "reminder-hash-2",
      "text": "Research local-first software"
    },
    {
      "slot": 3,
      "id": "reminder-hash-3",
      "text": "Finish the bookshelf lighting idea"
    }
  ]
}
```

When DynamoDB is unavailable and a cached selection exists:

```json
{
  "source": "local-cache",
  "stale": true
}
```

The local HTTP service, if implemented, should bind only to:

```text
127.0.0.1
```

unless LAN access is explicitly needed.

---

## 10. Security Requirements

### 10.1 General

The system must follow least-privilege access.

There must be no:

* Public unauthenticated ingestion endpoint
* Shared static API key in an Apple Shortcut
* IAM access key embedded in the iOS app
* Permanent IAM access key stored on the Pi
* Pi write permission to DynamoDB
* Reminder text in CloudWatch logs
* Public inbound port opened on the home router

---

### 10.2 iOS Security

The iOS application must:

* Use Cognito authorization with PKCE
* Store tokens only in Keychain
* Use HTTPS for all network requests
* Validate server certificates through the standard iOS trust chain
* Clear credentials during sign-out
* Avoid storing reminder text in diagnostic logs
* Request only Reminders permission
* Not request Contacts, Photos, Calendar, Location, or Microphone access

---

### 10.3 AWS Security

AWS must:

* Require JWT authentication for ingestion requests
* Restrict Lambda permissions to one table
* Encrypt DynamoDB at rest
* Use TLS for all data in transit
* Limit CloudWatch log retention
* Avoid recording request bodies in API access logs
* Enable API throttling
* Maintain separate IAM roles for Lambda and the Pi
* Allow immediate revocation of the Pi certificate
* Use AWS Budgets or billing alarms

---

### 10.4 Pi Security

The Pi must:

* Run the dashboard under a dedicated Linux user
* Store certificate material outside the web root
* Restrict private-key file permissions
* Apply operating-system security updates
* Disable unused services
* Avoid exposing the dashboard process to the internet
* Cache only reminder text required for display
* Avoid logging AWS temporary credentials

Suggested user:

```text
floatingbrain
```

Suggested application path:

```text
/opt/floating-brain
```

---

## 11. Logging and Monitoring

### AWS logs

Log:

* Request identifier
* Cognito user identifier or hashed equivalent
* Sync identifier
* Number of records received
* Number created
* Number updated
* Number completed
* Number rejected
* Processing duration
* Error category

Do not log:

* Reminder text
* Reminder notes
* Apple reminder identifiers
* Access tokens
* Authorization headers
* Device private keys

### Pi logs

Log:

* DynamoDB fetch success or failure
* Number of active reminders fetched
* Daily-selection creation
* Cache usage
* Credential-refresh errors
* Rendering errors

Do not log complete temporary AWS credentials.

---

## 12. Error Handling

### iOS errors

The app must handle:

* Reminders permission denied
* `Floating Brain` list not found
* Cognito login expired
* No internet connection
* API throttling
* Invalid reminder data
* Partial sync rejection
* Server errors
* Request timeout

Failed syncs should be retried with exponential backoff.

The app should clearly distinguish:

```text
Last sync succeeded
Last sync partially succeeded
Last sync failed
```

---

### Pi errors

The Pi must handle:

* No internet connection
* DynamoDB timeout
* Expired temporary credentials
* IoT certificate rejection
* Empty DynamoDB response
* Corrupt SQLite database
* Fewer than three active reminders
* Invalid reminder records
* System date or timezone errors

If today’s selection is already cached, AWS failure must not blank the dashboard.

If no current selection exists, the Pi may display the most recent cached selection with a stale-data indicator.

---

## 13. Cost Controls

The deployment must:

* Avoid EC2
* Avoid RDS
* Avoid NAT Gateway
* Avoid load balancers
* Avoid provisioned Lambda concurrency
* Use short CloudWatch log retention
* Use low provisioned DynamoDB capacity
* Configure an AWS Budget alert
* Apply API throttling
* Avoid unnecessary AWS IoT message publishing

The design is intended for extremely low personal usage. Actual charges depend on the AWS account’s eligibility, region, current pricing, and other resources consuming account-level allowances.

---

## 14. Deployment Environments

Two environments are recommended:

```text
development
production
```

For a personal MVP, development may initially use:

* A separate DynamoDB table
* A separate Cognito app client
* A separate API Gateway stage
* A separate Lambda alias

Suggested resource names:

```text
floating-brain-dev
floating-brain-prod
```

Infrastructure should be defined through AWS SAM, AWS CDK, or Terraform rather than created exclusively through the console.

---

## 15. Testing Requirements

### iOS tests

Verify that:

* Permission can be granted and revoked
* The correct Reminders list is selected
* A new reminder is synchronized
* An edited reminder updates the existing item
* A completed reminder becomes inactive
* Repeated sync does not create duplicates
* Expired authentication triggers reauthentication
* Tokens are not stored outside Keychain
* The Shortcut intent triggers synchronization

### AWS tests

Verify that:

* Requests without JWTs are rejected
* Invalid JWTs are rejected
* Valid users can sync their records
* A user cannot write another user’s partition
* Oversized requests are rejected
* Invalid dates are rejected
* Excessively long text is rejected
* Repeated `syncId` values are idempotent
* Reminder text is absent from logs

### Pi tests

Verify that:

* The Pi can obtain temporary credentials
* The Pi can query DynamoDB
* The Pi cannot call `PutItem`
* Three items are selected when available
* The same three items remain all day
* Recently shown items are deprioritized
* Fewer than three active items are handled
* Cached items display while offline
* The selection changes on the next calendar day

---

## 16. Acceptance Criteria

The MVP is accepted when all of the following are true:

1. The user can add a reminder to the `Floating Brain` Apple Reminders list.
2. The iOS helper can read that reminder after receiving permission.
3. The user can securely authenticate through Cognito.
4. The iOS helper can synchronize the reminder to DynamoDB.
5. No static AWS access key or shared API secret exists in the app or Shortcut.
6. Unauthenticated API requests are rejected.
7. The Pi authenticates using temporary credentials.
8. The Pi can read active reminders from DynamoDB.
9. The Pi cannot write to DynamoDB.
10. The server selects up to three reminders and persists the ordered daily record.
11. The selection remains stable throughout the day.
12. The Pi can display a cached selection while offline.
13. Completing a reminder in Apple Reminders eventually removes it from the eligible dashboard pool.
14. Reminder text does not appear in AWS infrastructure logs.
15. No inbound port is opened on the home router.

---

## 17. Implementation Phases

### Phase 1 — AWS Foundation

* Create DynamoDB table
* Create Cognito User Pool
* Create native application client
* Create API Gateway HTTP API
* Configure JWT authorizer
* Create synchronization Lambda
* Configure IAM policies
* Create budget alert
* Configure log retention

### Phase 2 — iOS Helper

* Create SwiftUI project
* Add EventKit permission handling
* Locate the `Floating Brain` list
* Implement Cognito login with PKCE
* Implement sync request
* Add Keychain storage
* Add sync status UI
* Add App Intent for Shortcuts

### Phase 3 — Raspberry Pi Reader

* Register the Pi as an AWS IoT Thing
* Generate device certificate
* Configure credentials provider and role alias
* Create read-only DynamoDB IAM policy
* Install Python application
* Create local SQLite cache
* Read the server-owned daily selection
* Add systemd service and timer

### Phase 4 — Dashboard Integration

* Create basic terminal or web preview
* Define e-paper layout
* Render three floating thoughts
* Add current date and cache status
* Connect to reTerminal E1001 after hardware purchase

---

## 18. Future Enhancements

Possible later capabilities include:

* Task categories based on Reminders tags
* One task, one idea, and one reading item per day
* Pinning or excluding specific reminders
* Due-date-aware selection
* Different weekday and weekend selection modes
* Household shared lists
* Dashboard completion actions
* Bi-directional completion synchronization
* Reminder aging reports
* Automated archive suggestions
* Multiple dashboard pages
* Optional web administration interface
* End-to-end encryption of reminder text before DynamoDB storage

---

## 19. Key Design Decisions

| Decision                      | Selected approach                     |
| ----------------------------- | ------------------------------------- |
| Task capture                  | Apple Reminders                       |
| iPhone-to-AWS authentication  | Cognito OAuth with PKCE               |
| AWS ingestion                 | API Gateway and Lambda                |
| Database                      | DynamoDB                              |
| Pi access                     | Read only                             |
| Pi credentials                | Temporary credentials through AWS IoT |
| Daily state                   | Local SQLite                          |
| AWS write access from Pi      | Prohibited                            |
| Public shared-secret endpoint | Prohibited                            |
| Dashboard task selection      | Controlled random selection           |
| Same-day stability            | Local cached daily selection          |
| Offline operation             | Use cached selection                  |

This version is suitable as the baseline for the AWS, iOS, and Raspberry Pi implementation.
