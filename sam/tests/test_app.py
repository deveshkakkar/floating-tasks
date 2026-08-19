import importlib.util
import pathlib
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
                    "items": [{"slot": 1, "externalId": "one", "text": "One", "priority": 1}],
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
