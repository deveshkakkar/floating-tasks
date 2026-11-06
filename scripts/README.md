# Local checks and deployment preflight

Run the backend, Pi, script, and TypeScript checks without AWS, Cognito, or
Photon credentials (install the Node dependencies with `npm ci` in `floating/`
first):

```bash
python3 scripts/check.py
```

Use `python3 scripts/check.py --python-only` to run the Python suites and
plist/JSON validation without Node. iOS simulator tests and SAM template lint
are separate CI jobs; see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Deployment preflight

Run this before any AWS deployment:

```bash
python3 scripts/deployment_preflight.py \
  --account-id YOUR_12_DIGIT_AWS_ACCOUNT_ID \
  --domain-prefix your-unique-cognito-domain
```

Replace both placeholders. Select your AWS profile using `AWS_PROFILE` before
running it. The command checks local files, AWS/SAM CLI availability, and the
active AWS account through STS. It never deploys resources.
