# Floating Brain Analytics History

## Purpose

Measure whether resurfaced reminders are completed, deleted, or repeatedly resurfaced. The history is append-oriented and independent of DynamoDB TTL cleanup.

## Storage

- Provider: encrypted, versioned S3 history bucket created by `sam/template.yaml`.
- Object root: `users/<user-id>/events/<YYYY-MM-DD>/<event-type>/`.
- Format: one JSON object per event.
- Retention: no application TTL; S3 lifecycle/retention can be added after usage is understood.

## Event types

### `DAILY_SELECTION_CREATED`

Created when the server materializes a new daily selection.

- `occurredAt`: selection generation timestamp
- `selection`: the complete server-owned daily selection record, including ordered items

### `REMINDER_COMPLETED`

Created when a Photon task is completed through the API or when the iOS sync reports a completed Apple Reminder.

- `occurredAt`: completion timestamp or trusted Apple Reminder modification timestamp
- `source`: `APPLE_REMINDERS` when reported by iOS sync; omitted for API-originated completion
- `reminder`: reminder snapshot at completion

### `REMINDER_DELETED`

Created immediately before the DynamoDB soft-deleted row is written after the three-sync omission grace period.

- `occurredAt`: deletion transition timestamp
- `reminder`: reminder snapshot at deletion

## Metrics

Initial Athena/reporting metrics should include:

- completion rate of selected reminders;
- deletion rate of selected reminders;
- median time from selection to completion or deletion;
- resurfacing count before completion/deletion;
- selection volume by day and source.

The Pi display remains read-only in the first release, so these metrics measure server selection and task outcomes, not confirmed human viewing. Add display telemetry only after the separate display repository defines its device identity and privacy contract.
