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


if __name__ == "__main__":
    unittest.main()
