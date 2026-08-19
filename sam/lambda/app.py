import base64
import json
import os
import random
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from zoneinfo import ZoneInfo

try:
    import boto3
    from boto3.dynamodb.conditions import Key
except ModuleNotFoundError:  # Local pure-function tests do not require the AWS SDK.
    boto3 = None
    Key = None


MAX_ITEMS = 500
MAX_CAPTURE_ITEMS = 50
MAX_ACTIVE_PAGE_SIZE = 50
MAX_TITLE_LENGTH = 500
MAX_BODY_BYTES = 512 * 1024
ACTIVE_TTL_SECONDS = 30 * 24 * 60 * 60
DAILY_SELECTION_TTL_SECONDS = 180 * 24 * 60 * 60
DEFAULT_SELECTION_TIME_ZONE = "America/Los_Angeles"
TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"]) if boto3 else None


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, default=json_default),
    }


def json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def user_id_from_event(event):
    claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
    return claims.get("sub")


def active_reminder_items(records):
    return [
        {
            "externalId": record["SK"].removeprefix("REMINDER#"),
            "text": record["text"],
            "completed": False,
            "createdAt": record.get("createdAt"),
            "modifiedAt": record.get("modifiedAt"),
            "dueAt": record.get("dueAt"),
            "priority": int(record.get("priority", 0)),
        }
        for record in records
        if record.get("status") == "ACTIVE" and isinstance(record.get("text"), str) and record["text"].strip()
    ]


def selection_date(now=None, time_zone=None):
    current = now or datetime.now(timezone.utc)
    zone = ZoneInfo(time_zone or os.environ.get("SELECTION_TIME_ZONE", DEFAULT_SELECTION_TIME_ZONE))
    return current.astimezone(zone).date().isoformat()


def daily_selection_items(user_id, date_key, reminders, recent_selections=()):
    candidates = sorted(active_reminder_items(reminders), key=lambda item: item["externalId"])
    selected_by_date = {
        selection["selectionDate"]: {item["externalId"] for item in selection.get("items", [])}
        for selection in recent_selections
    }
    current_date = datetime.strptime(date_key, "%Y-%m-%d").date()

    def eligible(days):
        cutoff = current_date - timedelta(days=days)
        excluded = {
            reminder_id
            for selected_date, reminder_ids in selected_by_date.items()
            if cutoff.isoformat() <= selected_date < date_key
            for reminder_id in reminder_ids
        }
        return [item for item in candidates if item["externalId"] not in excluded]

    candidates = eligible(7) or eligible(3) or candidates
    randomizer = random.Random(f"{user_id}:{date_key}:daily-selection-v1")
    randomizer.shuffle(candidates)
    return [
        {
            "slot": index,
            "externalId": item["externalId"],
            "text": item["text"],
            "priority": item["priority"],
        }
        for index, item in enumerate(candidates[:3], start=1)
    ]


def daily_selection_item(user_id, date_key, generated_at, reminders, recent_selections=()):
    return {
        "PK": f"USER#{user_id}",
        "SK": f"DAILY#{date_key}",
        "entityType": "DAILY_SELECTION",
        "schemaVersion": 1,
        "selectionDate": date_key,
        "generatedAt": generated_at,
        "timeZone": os.environ.get("SELECTION_TIME_ZONE", DEFAULT_SELECTION_TIME_ZONE),
        "items": daily_selection_items(user_id, date_key, reminders, recent_selections),
        "expiresAt": int(datetime.now(timezone.utc).timestamp()) + DAILY_SELECTION_TTL_SECONDS,
    }


def _query_all_reminders(table, partition_key):
    items = []
    query = {"KeyConditionExpression": Key("PK").eq(partition_key) & Key("SK").begins_with("REMINDER#")}
    while True:
        result = table.query(**query)
        items.extend(result.get("Items", []))
        last_key = result.get("LastEvaluatedKey")
        if not last_key:
            return items
        query["ExclusiveStartKey"] = last_key


def _query_recent_daily_selections(table, partition_key, date_key):
    cutoff = (datetime.strptime(date_key, "%Y-%m-%d").date() - timedelta(days=7)).isoformat()
    items = []
    query = {"KeyConditionExpression": Key("PK").eq(partition_key) & Key("SK").begins_with("DAILY#")}
    while True:
        result = table.query(**query)
        items.extend(
            item for item in result.get("Items", [])
            if cutoff <= item.get("selectionDate", "") < date_key
        )
        last_key = result.get("LastEvaluatedKey")
        if not last_key:
            return items
        query["ExclusiveStartKey"] = last_key


def _is_conditional_write_conflict(error):
    return getattr(error, "response", {}).get("Error", {}).get("Code") == "ConditionalCheckFailedException"


def ensure_daily_selection(user_id, date_key=None, generated_at=None, table=None):
    table = table or TABLE
    date_key = date_key or selection_date()
    generated_at = generated_at or now_iso()
    key = {"PK": f"USER#{user_id}", "SK": f"DAILY#{date_key}"}
    existing = table.get_item(Key=key).get("Item")
    if existing:
        return existing

    item = daily_selection_item(
        user_id,
        date_key,
        generated_at,
        _query_all_reminders(table, key["PK"]),
        _query_recent_daily_selections(table, key["PK"], date_key),
    )
    try:
        table.put_item(Item=item, ConditionExpression="attribute_not_exists(PK)")
        return item
    except Exception as error:
        if not _is_conditional_write_conflict(error):
            raise
        return table.get_item(Key=key)["Item"]


def daily_handler(event, _context):
    user_id = user_id_from_event(event)
    if not user_id:
        return response(401, {"error": "unauthorized"})

    item = ensure_daily_selection(user_id)
    return response(200, {
        "date": item["selectionDate"],
        "generatedAt": item["generatedAt"],
        "source": "server",
        "items": item.get("items", []),
    })


def scheduled_daily_handler(_event, _context):
    user_id = os.environ.get("DAILY_SELECTION_USER_ID")
    if not user_id:
        return response(200, {"source": "scheduled-server-generation", "skipped": True})

    item = ensure_daily_selection(user_id)
    return response(200, {
        "date": item["selectionDate"],
        "items": len(item.get("items", [])),
        "source": "scheduled-server-generation",
    })


def active_handler(event, _context):
    user_id = user_id_from_event(event)
    if not user_id:
        return response(401, {"error": "unauthorized"})

    partition_key = f"USER#{user_id}"
    query_parameters = event.get("queryStringParameters") or {}
    try:
        limit = min(max(int(query_parameters.get("limit", 25)), 1), MAX_ACTIVE_PAGE_SIZE)
    except (TypeError, ValueError):
        return response(400, {"error": "invalid_limit"})

    query = {
        "KeyConditionExpression": Key("PK").eq(partition_key) & Key("SK").begins_with("REMINDER#"),
        "Limit": limit,
    }
    cursor = decode_cursor(query_parameters.get("cursor"))
    if query_parameters.get("cursor") and (cursor is None or cursor.get("PK") != partition_key):
        return response(400, {"error": "invalid_cursor"})
    if cursor:
        query["ExclusiveStartKey"] = cursor

    result = TABLE.query(**query)
    next_cursor = encode_cursor(result.get("LastEvaluatedKey"))
    return response(200, {
        "items": active_reminder_items(result.get("Items", [])),
        "nextCursor": next_cursor,
    })


def encode_cursor(key):
    if not key:
        return None
    raw = json.dumps(key, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def decode_cursor(cursor):
    if not cursor:
        return None
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        value = json.loads(base64.urlsafe_b64decode(padded).decode("utf-8"))
        if not isinstance(value, dict) or not isinstance(value.get("PK"), str) or not isinstance(value.get("SK"), str):
            return None
        return {"PK": value["PK"], "SK": value["SK"]}
    except (ValueError, TypeError, UnicodeDecodeError):
        return None


def capture_handler(event, _context):
    user_id = user_id_from_event(event)
    if not user_id:
        return response(401, {"error": "unauthorized"})

    try:
        raw_body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            raw_body = base64.b64decode(raw_body).decode("utf-8")
        payload = json.loads(raw_body)
        items = payload.get("items")
        if not isinstance(items, list) or not items or len(items) > MAX_CAPTURE_ITEMS:
            raise ValueError("invalid capture count")
        for item in items:
            if not isinstance(item, dict) or not isinstance(item.get("id"), str):
                raise ValueError("invalid capture")
            if not item["id"] or not isinstance(item.get("text"), str) or not item["text"].strip():
                raise ValueError("invalid capture text")
            if len(item["text"]) > MAX_TITLE_LENGTH:
                raise ValueError("capture text is too long")
            if not isinstance(item.get("capturedAt"), str) or not item["capturedAt"]:
                raise ValueError("capture timestamp is required")
    except (ValueError, json.JSONDecodeError, UnicodeDecodeError):
        return response(400, {"error": "invalid_request"})

    partition_key = f"USER#{user_id}"
    expires_at = int(datetime.now(timezone.utc).timestamp()) + ACTIVE_TTL_SECONDS
    for item in items:
        capture_id = item["id"].replace("-", "")
        TABLE.put_item(Item={
            "PK": partition_key,
            "SK": f"REMINDER#capture:{capture_id}",
            "entityType": "REMINDER",
            "text": item["text"].strip(),
            "status": "ACTIVE",
            "createdAt": item["capturedAt"],
            "modifiedAt": item["capturedAt"],
            "dueAt": None,
            "priority": Decimal("0"),
            "expiresAt": expires_at,
            "source": "SHARE_EXTENSION",
            "schemaVersion": 1,
        })

    return response(200, {"captured": len(items)})


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
    payload["items"] = [item for item in items if not item["completed"]]
    return payload


def missing_record_updates(existing_records, incoming_ids, synced_at):
    """Return soft-deletion updates after one successful sync omission."""
    updates = []
    for record in existing_records:
        external_id = record["SK"].removeprefix("REMINDER#")
        if (
            external_id in incoming_ids
            or record.get("status") == "DELETED"
            or record.get("source") != "APPLE_REMINDERS"
        ):
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
    if event.get("source") == "aws.scheduler" and event.get("detail-type") == "DailySelection":
        return scheduled_daily_handler(event, _context)
    route = event.get("routeKey") or event.get("rawPath") or ""
    if route in {"GET /reminders/daily", "/reminders/daily"}:
        return daily_handler(event, _context)
    if route in {"GET /reminders/active", "/reminders/active"}:
        return active_handler(event, _context)
    if route in {"POST /items/capture", "/items/capture"}:
        return capture_handler(event, _context)

    try:
        user_id = user_id_from_event(event)
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

    expires_at = int(datetime.now(timezone.utc).timestamp()) + ACTIVE_TTL_SECONDS
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
            "expiresAt": expires_at,
            "syncedAt": synced_at,
            "source": "APPLE_REMINDERS",
            "schemaVersion": 1,
        })

    active_count = len(payload["items"])
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
