# Floating Brain Raspberry Pi reader

This module contains the local cache behavior for the Raspberry Pi. Daily task selection is server-owned; the Pi reads the persisted `DAILY#<local-date>` record and never chooses tasks locally.

`aws_reader.py` provides the read-only DynamoDB adapter. Construct it with temporary-credential-backed boto3 client credentials supplied by the device runtime; do not put IAM access keys in the Pi repository.

The reader:

- reads the server's ordered selection for the local calendar day;
- stores that selection in SQLite for offline use;
- falls back to the most recent cached selection while offline;
- keeps display history in SQLite.

Run local tests with:

```bash
PYTHONPATH=pi python3 -m unittest discover -s pi/tests
```
