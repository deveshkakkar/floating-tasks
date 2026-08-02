from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

from floating_brain import Reminder


@dataclass(frozen=True)
class PiAWSConfiguration:
    table_name: str
    user_id: str
    region: str


class DynamoDBQueryClient(Protocol):
    def query(self, **kwargs: Any) -> dict[str, Any]: ...


class ReadOnlyDynamoDBSource:
    """DynamoDB adapter exposing query-only access to the dashboard selector."""

    def __init__(self, client: DynamoDBQueryClient, configuration: PiAWSConfiguration):
        self.client = client
        self.configuration = configuration

    def active_reminders(self) -> list[Reminder]:
        response = self.client.query(
            TableName=self.configuration.table_name,
            KeyConditionExpression="PK = :pk AND begins_with(SK, :prefix)",
            FilterExpression="#status = :active",
            ExpressionAttributeValues={
                ":pk": f"USER#{self.configuration.user_id}",
                ":prefix": "REMINDER#",
                ":active": "ACTIVE",
            },
            ProjectionExpression="SK, #text, #status",
            ExpressionAttributeNames={"#status": "status", "#text": "text"},
        )
        return [
            Reminder(
                reminder_id=item["SK"].removeprefix("REMINDER#"),
                text=item["text"],
            )
            for item in response.get("Items", [])
            if item.get("status") == "ACTIVE" and item.get("text", "").strip()
        ]
