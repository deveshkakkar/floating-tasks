# Floating Brain Raspberry Pi reader

This module contains the local selection/cache behavior for the Raspberry Pi. It deliberately depends on a `ReminderSource` protocol rather than AWS SDK code so credential retrieval and DynamoDB access can be added without changing daily-selection behavior.

The selector:

- stores the same selection for the local calendar day;
- avoids reminders shown within seven days, then three days when needed;
- selects up to three active, non-empty reminders;
- falls back to the most recent cached selection while offline;
- keeps display history in SQLite.

Run local tests with:

```bash
PYTHONPATH=pi python3 -m unittest discover -s pi/tests
```
