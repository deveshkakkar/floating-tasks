import importlib.util
import hashlib
import hmac
import json
import os
import pathlib
import time
import unittest


MODULE_PATH = pathlib.Path(__file__).parents[1] / "lambda" / "app.py"
SPEC = importlib.util.spec_from_file_location("floating_brain_lambda", MODULE_PATH)
APP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(APP)


class MissingRecordTests(unittest.TestCase):
    def test_first_two_omissions_remain_active(self):
        existing = [{
            "PK": "USER#u",
            "SK": "REMINDER#r1",
            "status": "ACTIVE",
            "source": "APPLE_REMINDERS",
            "missingSyncCount": 1,
        }]

        update = APP.missing_record_updates(existing, set(), "2026-08-01T00:00:00Z")[0]

        self.assertEqual(update["status"], "ACTIVE")
        self.assertEqual(update["missingSyncCount"], 2)

    def test_third_omission_soft_deletes(self):
        existing = [{
            "PK": "USER#u",
            "SK": "REMINDER#r1",
            "status": "ACTIVE",
            "source": "APPLE_REMINDERS",
            "missingSince": "2026-07-30T00:00:00Z",
            "missingSyncCount": 2,
        }]

        update = APP.missing_record_updates(existing, set(), "2026-08-01T00:00:00Z")[0]

        self.assertEqual(update["status"], "DELETED")
        self.assertEqual(update["missingSyncCount"], 3)

    def test_present_and_deleted_records_are_not_updated(self):
        existing = [
            {"PK": "USER#u", "SK": "REMINDER#present", "status": "ACTIVE"},
            {"PK": "USER#u", "SK": "REMINDER#deleted", "status": "DELETED"},
            {"PK": "USER#u", "SK": "REMINDER#captured", "status": "ACTIVE", "source": "SHARE_EXTENSION"},
        ]

        updates = APP.missing_record_updates(existing, {"present"}, "2026-08-01T00:00:00Z")

        self.assertEqual(updates, [])


class PhotonWebhookTests(unittest.TestCase):
    secret = "test-secret"

    def setUp(self):
        self.original = {key: APP.os.environ.get(key) for key in (
            "PHOTON_WEBHOOK_SIGNING_SECRET", "PHOTON_USER_ID", "PHOTON_ALLOWED_SENDER"
        )}
        APP.os.environ.update({
            "PHOTON_WEBHOOK_SIGNING_SECRET": self.secret,
            "PHOTON_USER_ID": "u",
            "PHOTON_ALLOWED_SENDER": "+15551234567",
        })

    def tearDown(self):
        for key, value in self.original.items():
            if value is None:
                APP.os.environ.pop(key, None)
            else:
                APP.os.environ[key] = value

    def event(self, payload, signature_secret=None, timestamp=None):
        body = json.dumps(payload, separators=(",", ":"))
        timestamp = str(timestamp or int(time.time()))
        signature_secret = signature_secret or self.secret
        signature = "v0=" + hmac.new(
            signature_secret.encode(), f"v0:{timestamp}:{body}".encode(), hashlib.sha256
        ).hexdigest()
        return {
            "routeKey": "POST /photon/webhook",
            "body": body,
            "headers": {
                "x-spectrum-timestamp": timestamp,
                "x-spectrum-signature": signature,
            },
        }

    def payload(self, message_id="m1", text="Remember this"):
        return {
            "event": "messages",
            "message": {
                "id": message_id,
                "timestamp": "2026-08-20T12:00:00Z",
                "sender": {"id": "+15551234567"},
                "content": {"type": "text", "text": text},
            },
        }

    def test_verifies_signature_and_captures_text(self):
        class Table:
            def __init__(self):
                self.items = {}
            def get_item(self, Key):
                return {"Item": self.items.get((Key["PK"], Key["SK"]))} if (Key["PK"], Key["SK"]) in self.items else {}
            def put_item(self, Item):
                self.items[(Item["PK"], Item["SK"])] = Item

        table = Table()
        original_table = APP.TABLE
        APP.TABLE = table
        try:
            result = APP.handler(self.event(self.payload()), None)
        finally:
            APP.TABLE = original_table

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["body"], '{"captured": 1}')
        item = next(iter(table.items.values()))
        self.assertEqual(item["source"], "PHOTON")
        self.assertEqual(item["text"], "Remember this")

    def test_create_command_stores_only_task_text(self):
        class Table:
            def __init__(self):
                self.items = {}
            def get_item(self, Key):
                key = (Key["PK"], Key["SK"])
                return {"Item": self.items[key]} if key in self.items else {}
            def put_item(self, Item):
                self.items[(Item["PK"], Item["SK"])] = Item

        table = Table()
        original_table = APP.TABLE
        APP.TABLE = table
        try:
            result = APP.handler(self.event(self.payload(text="Create a task to buy milk")), None)
        finally:
            APP.TABLE = original_table

        self.assertEqual(result["statusCode"], 200)
        item = next(iter(table.items.values()))
        self.assertEqual(item["text"], "buy milk")

    def test_query_command_is_not_captured_as_a_task(self):
        result = APP.handler(self.event(self.payload(text="query active tasks")), None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["body"], '{"ignored": true}')

    def test_fetch_command_is_not_captured_as_a_task(self):
        result = APP.handler(self.event(self.payload(text="fetch active tasks")), None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["body"], '{"ignored": true}')

    def test_help_command_is_not_captured_as_a_task(self):
        result = APP.handler(self.event(self.payload(text="help")), None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["body"], '{"ignored": true}')

    def test_archived_command_is_not_captured_as_a_task(self):
        result = APP.handler(self.event(self.payload(text="show archived tasks")), None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["body"], '{"ignored": true}')

    def test_restore_command_is_not_captured_as_a_task(self):
        result = APP.handler(self.event(self.payload(text="restore old task")), None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["body"], '{"ignored": true}')

    def test_complete_command_is_not_captured_as_a_task(self):
        result = APP.handler(self.event(self.payload(text="complete old task")), None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["body"], '{"ignored": true}')

    def test_daily_command_is_not_captured_as_a_task(self):
        result = APP.handler(self.event(self.payload(text="today")), None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["body"], '{"ignored": true}')

    def test_rejects_bad_signature_and_deduplicates_message(self):
        class Table:
            def __init__(self): self.calls = 0
            def get_item(self, Key): return {}
            def put_item(self, Item): self.calls += 1
        table = Table()
        original_table = APP.TABLE
        APP.TABLE = table
        try:
            bad = self.event(self.payload(), signature_secret="wrong")
            self.assertEqual(APP.handler(bad, None)["statusCode"], 401)
            first = APP.handler(self.event(self.payload()), None)
            table.get_item = lambda Key: {"Item": {"PK": Key["PK"], "SK": Key["SK"]}}
            second = APP.handler(self.event(self.payload()), None)
        finally:
            APP.TABLE = original_table
        self.assertEqual(first["statusCode"], 200)
        self.assertEqual(second["body"], '{"captured": 0, "idempotent": true}')
        self.assertEqual(table.calls, 1)


class RequestParsingTests(unittest.TestCase):
    def test_completed_items_are_removed_from_sync_payload(self):
        payload = APP.parse_request({
            "body": '{"syncId":"s1","listName":"Floating Brain","items":['
            '{"externalId":"active","text":"Keep","completed":false},'
            '{"externalId":"done","text":"Done","completed":true}]}'
        })

        self.assertEqual([item["externalId"] for item in payload["items"]], ["active"])


class ActiveReminderTests(unittest.TestCase):
    def test_active_reminder_items_exclude_deleted_and_empty_records(self):
        items = APP.active_reminder_items([
            {"SK": "REMINDER#active", "status": "ACTIVE", "text": "Keep", "priority": 1},
            {"SK": "REMINDER#deleted", "status": "DELETED", "text": "Gone"},
            {"SK": "REMINDER#empty", "status": "ACTIVE", "text": "  "},
        ])

        self.assertEqual(items, [{
            "externalId": "active",
            "text": "Keep",
            "completed": False,
            "createdAt": None,
            "modifiedAt": None,
            "dueAt": None,
            "priority": 1,
        }])

    def test_cursor_round_trips_dynamodb_key(self):
        key = {"PK": "USER#u", "SK": "REMINDER#task-1"}
        self.assertEqual(APP.decode_cursor(APP.encode_cursor(key)), key)

    def test_invalid_cursor_is_rejected(self):
        self.assertIsNone(APP.decode_cursor("not-a-cursor"))

    def test_deleted_items_are_exposed_for_archive_view(self):
        items = APP.deleted_reminder_items([
            {"SK": "REMINDER#old", "status": "DELETED", "text": "Old", "source": "APPLE_REMINDERS"},
            {"SK": "REMINDER#active", "status": "ACTIVE", "text": "Keep"},
        ])
        self.assertEqual(items[0]["externalId"], "old")
        self.assertEqual(items[0]["source"], "APPLE_REMINDERS")

    def test_restore_rejects_non_apple_sources(self):
        class Table:
            def get_item(self, **kwargs):
                return {"Item": {"SK": "REMINDER#capture", "status": "DELETED", "source": "SHARE_EXTENSION"}}

        original = APP.TABLE
        table = Table()
        APP.TABLE = table
        try:
            result = APP.restore_handler({
                "requestContext": {"authorizer": {"jwt": {"claims": {"sub": "u"}}}},
                "body": '{"externalId":"capture"}',
            }, None)
        finally:
            APP.TABLE = original
        self.assertEqual(result["statusCode"], 409)

    def test_complete_marks_cloud_task_completed(self):
        class Table:
            def __init__(self):
                self.item = {"PK": "USER#u", "SK": "REMINDER#capture", "status": "ACTIVE", "source": "PHOTON"}
            def get_item(self, **kwargs):
                return {"Item": self.item}
            def put_item(self, Item):
                self.item = Item

        original = APP.TABLE
        table = Table()
        APP.TABLE = table
        try:
            result = APP.complete_handler({
                "requestContext": {"authorizer": {"jwt": {"claims": {"sub": "u"}}}},
                "body": '{"externalId":"capture"}',
            }, None)
        finally:
            APP.TABLE = original
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(table.item["status"], "COMPLETED")

    def test_complete_rejects_apple_task(self):
        class Table:
            def get_item(self, **kwargs):
                return {"Item": {"status": "ACTIVE", "source": "APPLE_REMINDERS"}}

        original = APP.TABLE
        APP.TABLE = Table()
        try:
            result = APP.complete_handler({
                "requestContext": {"authorizer": {"jwt": {"claims": {"sub": "u"}}}},
                "body": '{"externalId":"apple"}',
            }, None)
        finally:
            APP.TABLE = original
        self.assertEqual(result["statusCode"], 409)


class DailySelectionTests(unittest.TestCase):
    reminders = [
        {"SK": "REMINDER#one", "status": "ACTIVE", "text": "One", "priority": 1},
        {"SK": "REMINDER#two", "status": "ACTIVE", "text": "Two", "priority": 0},
        {"SK": "REMINDER#three", "status": "ACTIVE", "text": "Three", "priority": 2},
        {"SK": "REMINDER#done", "status": "COMPLETED", "text": "Done", "priority": 0},
    ]

    def test_selection_is_deterministic_and_contains_at_most_three_active_items(self):
        first = APP.daily_selection_items("u", "2026-08-18", self.reminders)
        second = APP.daily_selection_items("u", "2026-08-18", list(reversed(self.reminders)))

        self.assertEqual(first, second)
        self.assertEqual(len(first), 3)
        self.assertEqual([item["slot"] for item in first], [1, 2, 3])
        self.assertNotIn("done", {item["externalId"] for item in first})

    def test_selection_avoids_items_selected_within_the_previous_seven_days(self):
        recent = [{
            "selectionDate": "2026-08-15",
            "items": [{"externalId": "one"}],
        }]

        selected = APP.daily_selection_items("u", "2026-08-18", self.reminders, recent)

        self.assertNotIn("one", {item["externalId"] for item in selected})

    def test_same_day_item_is_not_regenerated(self):
        item = APP.daily_selection_item("u", "2026-08-18", "2026-08-18T06:00:00Z", self.reminders)

        self.assertEqual(item["PK"], "USER#u")
        self.assertEqual(item["SK"], "DAILY#2026-08-18")
        self.assertEqual(item["entityType"], "DAILY_SELECTION")
        self.assertEqual(item["selectionDate"], "2026-08-18")
        self.assertEqual(item["generatedAt"], "2026-08-18T06:00:00Z")

    def test_daily_endpoint_returns_existing_server_selection(self):
        class ExistingSelectionTable:
            def get_item(self, **kwargs):
                return {"Item": {
                    "selectionDate": "2026-08-18",
                    "generatedAt": "2026-08-18T06:00:00Z",
                    "items": [{"slot": 1, "externalId": "one", "text": "One", "priority": APP.Decimal("1")}],
                }}

        original_table = APP.TABLE
        APP.TABLE = ExistingSelectionTable()
        try:
            result = APP.daily_handler({
                "requestContext": {"authorizer": {"jwt": {"claims": {"sub": "u"}}}}
            }, None)
        finally:
            APP.TABLE = original_table

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"source": "server"', result["body"])
        self.assertIn('"externalId": "one"', result["body"])
        self.assertIn('"priority": 1', result["body"])

    def test_timezone_controls_the_selection_date(self):
        from datetime import datetime, timezone

        instant = datetime(2026, 8, 19, 2, 30, tzinfo=timezone.utc)

        self.assertEqual(APP.selection_date(instant, "America/Los_Angeles"), "2026-08-18")

    def test_existing_selection_is_returned_without_query_or_write(self):
        class ExistingSelectionTable:
            def get_item(self, **kwargs):
                return {"Item": {"selectionDate": "2026-08-18", "items": []}}

            def query(self, **kwargs):
                raise AssertionError("existing selections must not query reminders")

            def put_item(self, **kwargs):
                raise AssertionError("existing selections must not be written")

        result = APP.ensure_daily_selection(
            "u", date_key="2026-08-18", generated_at="ignored", table=ExistingSelectionTable()
        )

        self.assertEqual(result["selectionDate"], "2026-08-18")

    def test_scheduled_handler_materializes_for_configured_user(self):
        class ExistingSelectionTable:
            def get_item(self, **kwargs):
                return {"Item": {
                    "selectionDate": "2026-08-18",
                    "generatedAt": "2026-08-18T06:00:00Z",
                    "items": [],
                }}

        original_table = APP.TABLE
        original_user_id = APP.os.environ.get("DAILY_SELECTION_USER_ID")
        APP.TABLE = ExistingSelectionTable()
        APP.os.environ["DAILY_SELECTION_USER_ID"] = "u"
        try:
            result = APP.handler({
                "source": "aws.scheduler",
                "detail-type": "DailySelection",
            }, None)
        finally:
            APP.TABLE = original_table
            if original_user_id is None:
                APP.os.environ.pop("DAILY_SELECTION_USER_ID", None)
            else:
                APP.os.environ["DAILY_SELECTION_USER_ID"] = original_user_id

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"source": "scheduled-server-generation"', result["body"])

    def test_scheduled_handler_skips_before_user_is_configured(self):
        original_user_id = APP.os.environ.pop("DAILY_SELECTION_USER_ID", None)
        try:
            result = APP.handler({
                "source": "aws.scheduler",
                "detail-type": "DailySelection",
            }, None)
        finally:
            if original_user_id is not None:
                APP.os.environ["DAILY_SELECTION_USER_ID"] = original_user_id

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"skipped": true', result["body"])


if __name__ == "__main__":
    unittest.main()
