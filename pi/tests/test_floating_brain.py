import sqlite3
import unittest
from datetime import date

from floating_brain import DailySelector, Reminder, SelectionStore


class FakeSource:
    def __init__(self, reminders=None, error=None, daily_items=None):
        self.reminders = reminders or []
        self.error = error
        self.daily_items = daily_items

    def active_reminders(self):
        if self.error:
            raise self.error
        return self.reminders

    def daily_selection(self, selection_date):
        if self.error:
            raise self.error
        return self.daily_items if self.daily_items is not None else self.reminders[:3]


class DailySelectorTests(unittest.TestCase):
    def setUp(self):
        self.connection = sqlite3.connect(":memory:")
        self.store = SelectionStore(self.connection)
        self.now = (date(2026, 8, 1), "2026-08-01T06:00:00Z")

    def test_selection_is_stable_for_the_day(self):
        source = FakeSource([Reminder("1", "One"), Reminder("2", "Two"), Reminder("3", "Three"), Reminder("4", "Four")])
        selector = DailySelector(source, self.store, lambda: self.now)

        first = selector.get()
        source.reminders = [Reminder("different", "Different")]
        second = selector.get()

        self.assertEqual(first.items, second.items)
        self.assertEqual(second.source, "local-cache")

    def test_offline_uses_previous_cached_selection(self):
        source = FakeSource([Reminder("1", "One")])
        DailySelector(source, self.store, lambda: self.now).get()
        offline = DailySelector(FakeSource(error=RuntimeError("offline")), self.store, lambda: (date(2026, 8, 2), "2026-08-02T06:00:00Z")).get()

        self.assertTrue(offline.stale)
        self.assertEqual(offline.source, "local-cache")
        self.assertEqual(offline.items[0].reminder_id, "1")

    def test_selection_limits_to_three_items(self):
        source = FakeSource([Reminder(str(index), str(index)) for index in range(10)])

        selection = DailySelector(source, self.store, lambda: self.now).get()

        self.assertEqual(len(selection.items), 3)
        self.assertEqual(selection.source, "server")


if __name__ == "__main__":
    unittest.main()
