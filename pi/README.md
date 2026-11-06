# Floating Brain Raspberry Pi reader

This directory contains Python reader and cache modules, not a complete Raspberry Pi display application. There is no device installer, rendering UI, service entry point, or credential provisioner yet. [DISPLAY_SPEC.md](../DISPLAY_SPEC.md) describes planned display behavior.

Daily task selection is server-owned. The Pi reads the persisted `DAILY#<local-date>` record and does not select tasks locally.

## Local tests

From the repository root, with Python 3.12+:

```bash
PYTHONPATH=pi python3 -m unittest discover -s pi/tests -v
```

The tests require neither AWS credentials nor Pi hardware.

## Integration contract

- `aws_reader.py` provides `PiAWSConfiguration` and `ReadOnlyDynamoDBSource`. Supply a DynamoDB client adapter with `query` and `get_item` methods that accepts and returns ordinary Python values, as the tests demonstrate; a raw low-level boto3 client needs a serialization adapter.
- The device runtime must provide temporary AWS credentials and an IAM policy restricted to read operations for the intended `USER#<sub>` partition. Do not embed access keys in the image or repository.
- `floating_brain.py` provides `SelectionStore` over an injected SQLite connection and `DailySelector` over an injected source and clock. Align the clock's local date with the backend's `SelectionTimeZone`.
- The selector caches the server's ordered selection for the day. On a read failure it returns the most recent cached selection with `stale=True`; without a previous cache it raises the error.

SQLite stores task text and display history without automatic expiry or application-level encryption. Protect filesystem access, define a cleanup policy, and remove cached data before transferring or retiring a device. See [SECURITY.md](../SECURITY.md).
