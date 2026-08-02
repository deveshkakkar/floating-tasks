import base64
import json
import os
from datetime import datetime, timezone
from decimal import Decimal

try:
    import boto3
    from boto3.dynamodb.conditions import Key
except ModuleNotFoundError:  # Local pure-function tests do not require the AWS SDK.
    boto3 = None
    Key = None


MAX_ITEMS = 500
MAX_TITLE_LENGTH = 500
MAX_BODY_BYTES = 512 * 1024
TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"]) if boto3 else None


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_request(event):
    raw_body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw_body = base64.b64decode(raw_body).decode("utf-8")
    if len(raw_body.encode("utf-8")) > MAX_BODY_BYTES:
        raise ValueError("request body is too large")
    payload = json.loads(raw_body)
    items = payload.get("items")
    if not isinstance(payload.get("syncId"), str) or not payload["syncId"]:
        raise ValueError("syncId is required")
    if not isinstance(payload.get("listName"), str) or payload["listName"] != "Floating Brain":
        raise ValueError("invalid listName")
    if not isinstance(items, list) or len(items) > MAX_ITEMS:
        raise ValueError("invalid item count")
    for item in items:
        if not isinstance(item, dict) or not isinstance(item.get("externalId"), str):
            raise ValueError("invalid reminder")
        if not item["externalId"] or not isinstance(item.get("text"), str) or not item["text"].strip():
            raise ValueError("invalid reminder text")
        if len(item["text"]) > MAX_TITLE_LENGTH:
            raise ValueError("reminder text is too long")
        if not isinstance(item.get("completed"), bool):
            raise ValueError("invalid completion state")
    return payload


def missing_record_updates(existing_records, incoming_ids, synced_at):
    """Return soft-deletion updates after one successful sync omission."""
    updates = []
    for record in existing_records:
        external_id = record["SK"].removeprefix("REMINDER#")
        if external_id in incoming_ids or record.get("status") == "DELETED":
            continue
        missing_count = int(record.get("missingSyncCount", 0)) + 1
        updated = dict(record)
        updated["missingSince"] = record.get("missingSince", synced_at)
        updated["missingSyncCount"] = missing_count
        updated["syncedAt"] = synced_at
        if missing_count >= 3:
            updated["status"] = "DELETED"
        updates.append(updated)
    return updates


def handler(event, _context):
    try:
        claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
        user_id = claims.get("sub")
        if not user_id:
            return response(401, {"error": "unauthorized"})
        payload = parse_request(event)
    except (ValueError, json.JSONDecodeError, UnicodeDecodeError):
        return response(400, {"error": "invalid_request"})

    partition_key = f"USER#{user_id}"
    sync_key = {"PK": partition_key, "SK": "SYNC#STATE"}
    existing = TABLE.get_item(Key=sync_key).get("Item")
    if existing and existing.get("lastSyncId") == payload["syncId"]:
        return response(200, {"syncId": payload["syncId"], "idempotent": True})

    synced_at = now_iso()
    existing_reminders = TABLE.query(
        KeyConditionExpression=Key("PK").eq(partition_key) & Key("SK").begins_with("REMINDER#")
    ).get("Items", [])
    incoming_ids = {item["externalId"] for item in payload["items"]}
    for record in missing_record_updates(existing_reminders, incoming_ids, synced_at):
        TABLE.put_item(Item=record)

    for item in payload["items"]:
        TABLE.put_item(Item={
            "PK": partition_key,
            "SK": f"REMINDER#{item['externalId']}",
            "entityType": "REMINDER",
            "text": item["text"],
            "status": "COMPLETED" if item["completed"] else "ACTIVE",
            "createdAt": item.get("createdAt"),
            "modifiedAt": item.get("modifiedAt"),
            "dueAt": item.get("dueAt"),
            "priority": Decimal(str(item.get("priority", 0))),
            "syncedAt": synced_at,
            "source": "APPLE_REMINDERS",
            "schemaVersion": 1,
        })

    active_count = sum(1 for item in payload["items"] if not item["completed"])
    TABLE.put_item(Item={
        **sync_key,
        "entityType": "SYNC_STATE",
        "lastSyncAt": synced_at,
        "lastSyncId": payload["syncId"],
        "activeCount": active_count,
        "completedCount": len(payload["items"]) - active_count,
        "schemaVersion": 1,
    })
    return response(200, {
        "syncId": payload["syncId"],
        "received": len(payload["items"]),
        "active": active_count,
        "completed": len(payload["items"]) - active_count,
    })
