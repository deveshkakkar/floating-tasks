# Floating Brain AWS development stack

This directory contains a local AWS SAM definition for the development environment. It provisions:

- Cognito User Pool with a public PKCE-compatible app client
- Cognito hosted UI domain
- API Gateway HTTP API with Cognito JWT authorization
- Write Lambda for `POST /v1/reminders/sync`
- Provisioned, encrypted DynamoDB table

No AWS account credentials or client secrets belong in this repository. The supplied AWS account ID is deployment context only; SAM resolves the account and region from the active AWS profile.

## Validate locally

```bash
sam validate --template-file sam/template.yaml
sam build --template-file sam/template.yaml
```

## Deploy to a development stack

Use an authenticated AWS CLI profile and choose a globally unique Cognito domain prefix:

```bash
sam deploy --guided \
  --template-file sam/template.yaml \
  --stack-name floating-brain-dev \
  --parameter-overrides CognitoDomainPrefix=<unique-prefix>
```

Keep the generated deployment configuration local and out of source control if it contains account-specific values.
