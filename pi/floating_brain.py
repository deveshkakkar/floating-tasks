from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import date
from typing import Callable, Iterable, Protocol


@dataclass(frozen=True)
class Reminder:
    reminder_id: str
    text: str


@dataclass(frozen=True)
class DailySelection:
    selection_date: str
    generated_at: str
    source: str
    stale: bool
    items: tuple[Reminder, ...]


class ReminderSource(Protocol):
    def active_reminders(self) -> Iterable[Reminder]: ...

    def daily_selection(self, selection_date: str) -> Iterable[Reminder]: ...


class SelectionStore:
    def __init__(self, connection: sqlite3.Connection):
        self.connection = connection
        self.connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS daily_selection (
                selection_date TEXT NOT NULL,
                slot INTEGER NOT NULL,
                reminder_id TEXT NOT NULL,
                reminder_text TEXT NOT NULL,
                selected_at TEXT NOT NULL,
                PRIMARY KEY (selection_date, slot)
            );
            CREATE TABLE IF NOT EXISTS display_history (
                reminder_id TEXT PRIMARY KEY,
                last_shown_date TEXT NOT NULL,
                show_count INTEGER NOT NULL DEFAULT 1
            );
            """
        )

    def today(self, selection_date: str) -> tuple[Reminder, ...]:
        rows = self.connection.execute(
            "SELECT reminder_id, reminder_text FROM daily_selection WHERE selection_date = ? ORDER BY slot",
            (selection_date,),
        ).fetchall()
        return tuple(Reminder(row[0], row[1]) for row in rows)

    def latest(self) -> tuple[str, tuple[Reminder, ...]] | None:
        row = self.connection.execute("SELECT MAX(selection_date) FROM daily_selection").fetchone()
        if not row or not row[0]:
            return None
        return row[0], self.today(row[0])

    def last_shown(self, reminder_id: str) -> str | None:
        row = self.connection.execute(
            "SELECT last_shown_date FROM display_history WHERE reminder_id = ?", (reminder_id,)
        ).fetchone()
        return row[0] if row else None

    def save(self, selection_date: str, generated_at: str, reminders: Iterable[Reminder]) -> None:
        for slot, reminder in enumerate(reminders, start=1):
            self.connection.execute(
                "INSERT OR REPLACE INTO daily_selection VALUES (?, ?, ?, ?, ?)",
                (selection_date, slot, reminder.reminder_id, reminder.text, generated_at),
            )
            self.connection.execute(
                "INSERT INTO display_history(reminder_id, last_shown_date, show_count) VALUES (?, ?, 1) "
                "ON CONFLICT(reminder_id) DO UPDATE SET last_shown_date=excluded.last_shown_date, show_count=show_count+1",
                (reminder.reminder_id, selection_date),
            )
        self.connection.commit()


class DailySelector:
    def __init__(self, source: ReminderSource, store: SelectionStore, clock: Callable[[], tuple[date, str]]):
        self.source = source
        self.store = store
        self.clock = clock

    def get(self) -> DailySelection:
        today, generated_at = self.clock()
        selection_date = today.isoformat()
        cached = self.store.today(selection_date)
        if cached:
            return DailySelection(selection_date, generated_at, "local-cache", False, cached)

        try:
            selected = list(self.source.daily_selection(selection_date))
            self.store.save(selection_date, generated_at, selected)
            return DailySelection(selection_date, generated_at, "server", False, tuple(selected))
        except Exception:
            latest = self.store.latest()
            if latest:
                return DailySelection(selection_date, generated_at, "local-cache", True, latest[1])
            raise
