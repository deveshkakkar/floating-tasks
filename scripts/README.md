# Deployment preflight

Run this before any AWS deployment:

```bash
PYTHONPATH=scripts python3 scripts/deployment_preflight.py \
  --account-id 477439418849 \
  --domain-prefix floating-brain-dev
```

The command only checks local files, AWS/SAM CLI availability, and the active AWS account. It never deploys resources.
