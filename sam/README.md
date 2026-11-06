# Floating Brain AWS backend

This is a development stack defined with AWS SAM. It provisions a Cognito user pool and public OAuth client, an HTTP API, Python 3.12 Lambda functions, DynamoDB, an EventBridge daily scheduler, and a private versioned S3 archive bucket. You deploy and operate it in your own AWS account.

## Local checks

Run from the repository root:

```bash
python3 -m unittest discover -s sam/tests -v
sam validate --lint --template-file sam/template.yaml
sam build --template-file sam/template.yaml
```

The unit tests use local fixtures and need no AWS credentials. The other commands require the AWS SAM CLI; building also needs a suitable Python runtime or SAM's container build option. Validation/building does not deploy the stack.

## Deploy your own development stack

Configure an authenticated AWS CLI profile and choose a region, stack name, and globally unique Cognito hosted UI domain prefix. Use the guided deployment prompts to review changes and IAM permissions:

```bash
sam deploy --guided
```

Run this from the repository root after `sam build`. Set `CognitoDomainPrefix` in the prompts and choose `SelectionTimeZone` for your daily boundary. The default timezone is `America/Los_Angeles`; change it if that is not your intended timezone. Keep generated `samconfig.toml` deployment settings local.

Self-sign-up is disabled. Create a development user in your own Cognito user pool through the AWS console or your account's administrative process, then complete its initial password setup. Do not put account passwords or AWS keys in this repository.

Map the stack outputs into `Config/Local.xcconfig` for iOS, or the local environment for the messaging companion:

| Stack output | Client setting |
| --- | --- |
| `SyncApiBaseURL` | `FLOATING_BRAIN_API_URL` — origin only, without `/v1` |
| `CognitoAuthorizationEndpoint` | `COGNITO_AUTHORIZATION_ENDPOINT` |
| `CognitoTokenEndpoint` | `COGNITO_TOKEN_ENDPOINT` |
| `UserPoolClientId` | `COGNITO_CLIENT_ID` |

The configured callbacks are `floatingbrain://oauth/callback` for iOS and `http://127.0.0.1:8765/callback` for the companion. There is no OAuth client secret.

## API and optional integrations

Authenticated routes use the Cognito JWT subject to identify the user:

| Method and path | Purpose |
| --- | --- |
| `POST /v1/reminders/sync` | Reconcile a snapshot of active Apple reminders |
| `GET /v1/reminders/active` | Read active tasks |
| `GET /v1/reminders/daily` | Read or materialize the day's ordered selection |
| `GET /v1/reminders/archived` | Read archived reminders |
| `POST /v1/reminders/complete` | Complete a supported task |
| `POST /v1/reminders/restore` | Restore a supported archived reminder |
| `POST /v1/items/capture` | Capture text from the app |

`DailySelectionUserId` is optional. Set it to your Cognito user's `sub` to materialize that user's selection on the scheduler; authenticated reads can create a missed selection on demand.

The optional `POST /v1/photon/webhook` uses webhook signature verification instead of Cognito authorization. To enable it, configure `PhotonUserId`, `PhotonAllowedSender`, and `PhotonWebhookSigningSecret`, and register the endpoint with your own Photon project. Supply the signing secret through a protected deployment process, not shell history, a committed config, or a pull request. The TypeScript companion is a separate process; starting it does not register this webhook.

## Retention and cleanup

Read [SECURITY.md](../SECURITY.md) before using personal data. DynamoDB TTL is asynchronous. The archive bucket has **no lifecycle expiry**, is versioned, and survives stack deletion; deleting a stack does not delete all stored task data. The template also does not configure a CloudWatch log retention period. Set retention and cleanup procedures for your deployment, and account for AWS charges.
