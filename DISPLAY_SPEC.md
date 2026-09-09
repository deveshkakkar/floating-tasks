# Floating Brain Display Handoff Spec

This document is a handoff for the separate Raspberry Pi display repository. The display must consume the server-owned daily selection; it must not choose or reorder tasks locally.

## First release

- Read `DAILY#<local-date>` using the existing read-only Pi adapter.
- Render up to three tasks in server-provided slot order.
- Cache the selection in SQLite for offline use.
- If today's selection is unavailable, show the newest cached selection with a visible stale indicator.
- Never write to DynamoDB from the display application.

## Screen contract

The primary screen contains:

1. Local date and a small freshness label.
2. One task card per selected item.
3. Offline/stale status when the displayed data is not today's fresh server selection.

Task cards show the complete task text, wrapping as needed. The first release should cap visual text at three lines with an ellipsis while preserving the full text in SQLite.

## Data states

- Fresh: today's server selection was fetched successfully.
- Local cache: today's selection was already cached locally.
- Stale: the display is showing the most recent prior selection because today's fetch failed.
- Empty: no server selection and no local cache exist.
- Error: the fetch failed and no cached selection is available.

## Behavior

- Refresh on process startup and at the beginning of each local calendar day.
- Retry transient network failures with bounded backoff.
- Keep the last usable screen visible during network failures.
- Do not reshuffle, filter, complete, delete, or restore tasks locally.
- Use the server's `slot`, `text`, and `externalId`; preserve ordering by `slot`.

## Effectiveness telemetry handoff

The display should initially remain read-only. If “actually shown” analytics are added later, emit a deduplicated event containing only:

- user/device pseudonymous identifier
- selection date
- reminder external ID
- display timestamp
- display result (`shown`, `partial`, or `failed`)

Do not send credentials, task contents, or raw AWS keys from the display. The event endpoint and retention policy must be defined before enabling telemetry.

## Acceptance criteria

- Three selected tasks render in server order.
- One- and two-task selections do not leave broken empty slots.
- Long text wraps without overlapping neighboring cards.
- Offline mode preserves the last usable selection and clearly marks it stale.
- A failed refresh never blanks a previously rendered selection.
- The display works without DynamoDB write permissions.
