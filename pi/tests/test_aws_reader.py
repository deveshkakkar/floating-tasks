import unittest

from aws_reader import PiAWSConfiguration, ReadOnlyDynamoDBSource


class FakeDynamoDBClient:
    def __init__(self):
        self.calls = []

    def query(self, **kwargs):
        self.calls.append(kwargs)
        return {
            "Items": [
                {"SK": "REMINDER#one", "status": "ACTIVE", "text": "One"},
                {"SK": "REMINDER#done", "status": "COMPLETED", "text": "Done"},
                {"SK": "REMINDER#blank", "status": "ACTIVE", "text": "  "},
            ]
        }


class ReadOnlyDynamoDBSourceTests(unittest.TestCase):
    def test_queries_one_user_partition_and_returns_active_items(self):
        client = FakeDynamoDBClient()
        source = ReadOnlyDynamoDBSource(client, PiAWSConfiguration("FloatingBrain-dev", "user-1", "us-west-2"))

        reminders = source.active_reminders()

        self.assertEqual(reminders[0].reminder_id, "one")
        self.assertEqual(reminders[0].text, "One")
        self.assertEqual(client.calls[0]["TableName"], "FloatingBrain-dev")
        self.assertEqual(client.calls[0]["ExpressionAttributeValues"][":pk"], "USER#user-1")
        self.assertEqual(client.calls[0]["KeyConditionExpression"], "PK = :pk AND begins_with(SK, :prefix)")
        self.assertNotIn("put_item", dir(source))
        self.assertNotIn("update_item", dir(source))


if __name__ == "__main__":
    unittest.main()
