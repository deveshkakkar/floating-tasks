import base64
import hashlib
import hmac
import json
import os
import random
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from urllib.parse import quote
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
DELETED_TTL_SECONDS = 24 * 60 * 60
DAILY_SELECTION_TTL_SECONDS = 2 * 24 * 60 * 60
PHOTON_TIMESTAMP_TOLERANCE_SECONDS = 5 * 60
DEFAULT_SELECTION_TIME_ZONE = "America/Los_Angeles"
TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"]) if boto3 else None
S3 = boto3.client("s3") if boto3 else None
HISTORY_BUCKET_NAME = os.environ.get("HISTORY_BUCKET_NAME")


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


def epoch_seconds(instant):
    return int(datetime.fromisoformat(instant.replace("Z", "+00:00")).timestamp())


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


def deleted_reminder_items(records):
    return [
        {
            "externalId": record["SK"].removeprefix("REMINDER#"),
            "text": record["text"],
            "completed": False,
            "createdAt": record.get("createdAt"),
            "modifiedAt": record.get("modifiedAt"),
            "dueAt": record.get("dueAt"),
            "priority": int(record.get("priority", 0)),
            "source": record.get("source"),
        }
        for record in records
        if record.get("status") == "DELETED"
        and isinstance(record.get("text"), str)
        and record["text"].strip()
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

    candidates = eligible(2)
    if len(candidates) < 3:
        candidates = eligible(1)
    if len(candidates) < 3:
        candidates = active_reminder_items(reminders)
        candidates = sorted(candidates, key=lambda item: item["externalId"])
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
        "expiresAt": epoch_seconds(generated_at) + DAILY_SELECTION_TTL_SECONDS,
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
        archive_history_event(
            user_id,
            "DAILY_SELECTION_CREATED",
            generated_at,
            {"selection": item},
            date_key,
        )
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


def archived_handler(event, _context):
    user_id = user_id_from_event(event)
    if not user_id:
        return response(401, {"error": "unauthorized"})

    records = _query_all_reminders(TABLE, f"USER#{user_id}")
    return response(200, {"items": deleted_reminder_items(records)})


def restore_handler(event, _context):
    user_id = user_id_from_event(event)
    if not user_id:
        return response(401, {"error": "unauthorized"})
    try:
        payload = json.loads(event.get("body") or "{}")
        external_id = payload.get("externalId")
        if not isinstance(external_id, str) or not external_id.strip():
            raise ValueError("externalId is required")
    except (ValueError, json.JSONDecodeError, TypeError):
        return response(400, {"error": "invalid_request"})

    key = {"PK": f"USER#{user_id}", "SK": f"REMINDER#{external_id}"}
    existing = TABLE.get_item(Key=key).get("Item")
    if not existing or existing.get("status") != "DELETED":
        return response(404, {"error": "archived_reminder_not_found"})
    if existing.get("source") != "APPLE_REMINDERS":
        return response(409, {"error": "unsupported_reminder_source"})

    restored = dict(existing)
    restored["status"] = "ACTIVE"
    restored["missingSyncCount"] = 0
    restored.pop("missingSince", None)
    restored["expiresAt"] = int(datetime.now(timezone.utc).timestamp()) + ACTIVE_TTL_SECONDS
    restored["modifiedAt"] = now_iso()
    TABLE.put_item(Item=restored)
    return response(200, {"restored": True, "externalId": external_id})


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


def _header(event, name):
    headers = event.get("headers") or {}
    wanted = name.lower()
    return next((value for key, value in headers.items() if key.lower() == wanted), None)


def normalize_photon_create_text(text):
    """Strip the first explicit create command before storing the task."""
    import re

    match = re.match(r"^(?:create|add)\s+", text, flags=re.IGNORECASE)
    if not match:
        return text.strip()

    task_text = text[match.end():]
    task_text = re.sub(r"^(?:a|an|the)\s+", "", task_text, flags=re.IGNORECASE)
    task_text = re.sub(r"^(?:task|reminder|item)\s+", "", task_text, flags=re.IGNORECASE)
    task_text = re.sub(r"^(?:to|for)\s+", "", task_text, flags=re.IGNORECASE)
    return task_text.strip() or text.strip()


def is_photon_query(text):
    import re

    return bool(re.match(r"^(?:query|fetch|show|list)\b", text.strip(), flags=re.IGNORECASE))


def is_photon_help(text):
    import re

    return bool(re.match(r"^(?:help|commands|what can you do)\b", text.strip(), flags=re.IGNORECASE))


def is_photon_archived(text):
    import re

    return bool(re.match(r"^(?:archived|archive|history)\b", text.strip(), flags=re.IGNORECASE))


def is_photon_restore(text):
    import re

    return bool(re.match(r"^(?:restore|bring back)\s+", text.strip(), flags=re.IGNORECASE))


def is_photon_complete(text):
    import re

    return bool(re.match(r"^(?:complete|finish|done|mark done)\s+", text.strip(), flags=re.IGNORECASE))


def is_photon_daily(text):
    import re

    return bool(re.match(r"^(?:today|daily|what should i do)\b", text.strip(), flags=re.IGNORECASE))


def complete_handler(event, _context):
    user_id = user_id_from_event(event)
    if not user_id:
        return response(401, {"error": "unauthorized"})
    try:
        payload = json.loads(event.get("body") or "{}")
        external_id = payload.get("externalId")
        if not isinstance(external_id, str) or not external_id.strip():
            raise ValueError("externalId is required")
    except (ValueError, json.JSONDecodeError, TypeError):
        return response(400, {"error": "invalid_request"})

    key = {"PK": f"USER#{user_id}", "SK": f"REMINDER#{external_id}"}
    existing = TABLE.get_item(Key=key).get("Item")
    if not existing or existing.get("status") != "ACTIVE":
        return response(404, {"error": "active_reminder_not_found"})
    if existing.get("source") == "APPLE_REMINDERS":
        return response(409, {"error": "complete_in_apple_reminders"})

    completed = dict(existing)
    completed_at = now_iso()
    completed["status"] = "COMPLETED"
    completed["modifiedAt"] = completed_at
    TABLE.put_item(Item=completed)
    archive_history_event(
        user_id,
        "REMINDER_COMPLETED",
        completed_at,
        {"reminder": completed},
        external_id,
    )
    return response(200, {"completed": True, "externalId": external_id})


def verify_photon_signature(raw_body, timestamp, signature, secret, now=None):
    if not timestamp or not signature or not secret:
        return False
    try:
        timestamp_value = int(timestamp)
    except (TypeError, ValueError):
        return False
    current_timestamp = int((now or datetime.now(timezone.utc)).timestamp())
    if abs(current_timestamp - timestamp_value) > PHOTON_TIMESTAMP_TOLERANCE_SECONDS:
        return False
    expected = "v0=" + hmac.new(
        secret.encode("utf-8"),
        f"v0:{timestamp}:".encode("utf-8") + raw_body,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


def photon_webhook_handler(event, _context):
    raw_body = event.get("body") or ""
    try:
        raw_body = base64.b64decode(raw_body) if event.get("isBase64Encoded") else raw_body.encode("utf-8")
    except (ValueError, UnicodeEncodeError):
        return response(400, {"error": "invalid_request"})

    if not verify_photon_signature(
        raw_body,
        _header(event, "X-Spectrum-Timestamp"),
        _header(event, "X-Spectrum-Signature"),
        os.environ.get("PHOTON_WEBHOOK_SIGNING_SECRET", ""),
    ):
        return response(401, {"error": "invalid_signature"})

    try:
        payload = json.loads(raw_body.decode("utf-8"))
        message = payload.get("message", {})
        sender = message.get("sender", {})
        content = message.get("content", {})
        message_id = message.get("id")
        sender_id = sender.get("id")
        text = content.get("text")
        if payload.get("event") != "messages":
            return response(200, {"ignored": True})
        if not isinstance(message_id, str) or not message_id.strip():
            raise ValueError("message id is required")
        if sender_id != os.environ.get("PHOTON_ALLOWED_SENDER", ""):
            return response(403, {"error": "sender_not_allowed"})
        if content.get("type") != "text" or not isinstance(text, str) or not text.strip():
            return response(200, {"ignored": True})
        if is_photon_query(text) or is_photon_help(text) or is_photon_archived(text) or is_photon_restore(text) or is_photon_complete(text) or is_photon_daily(text):
            return response(200, {"ignored": True})
        if len(text) > MAX_TITLE_LENGTH:
            return response(400, {"error": "text_too_long"})
        user_id = os.environ.get("PHOTON_USER_ID", "")
        if not user_id:
            return response(503, {"error": "photon_user_not_configured"})
    except (AttributeError, TypeError, ValueError, json.JSONDecodeError, UnicodeDecodeError):
        return response(400, {"error": "invalid_request"})

    key = {"PK": f"USER#{user_id}", "SK": f"REMINDER#capture:photon:{message_id}"}
    if TABLE.get_item(Key=key).get("Item"):
        return response(200, {"captured": 0, "idempotent": True})

    captured_at = message.get("timestamp") or now_iso()
    text = normalize_photon_create_text(text)
    expires_at = int(datetime.now(timezone.utc).timestamp()) + ACTIVE_TTL_SECONDS
    TABLE.put_item(Item={
        **key,
        "entityType": "REMINDER",
        "text": text.strip(),
        "status": "ACTIVE",
        "createdAt": captured_at,
        "modifiedAt": captured_at,
        "dueAt": None,
        "priority": Decimal("0"),
        "expiresAt": expires_at,
        "source": "PHOTON",
        "photonMessageId": message_id,
        "schemaVersion": 1,
    })
    return response(200, {"captured": 1})


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
    completed_items = payload.get("completedItems", [])
    if not isinstance(completed_items, list) or len(completed_items) > MAX_ITEMS:
        raise ValueError("invalid completed item count")
    for item in completed_items:
        if not isinstance(item, dict) or not isinstance(item.get("externalId"), str):
            raise ValueError("invalid completed reminder")
        if not item["externalId"] or not isinstance(item.get("text"), str) or not item["text"].strip():
            raise ValueError("invalid completed reminder text")
        if not isinstance(item.get("completed"), bool) or not item["completed"]:
            raise ValueError("invalid completed reminder state")
        if len(item["text"]) > MAX_TITLE_LENGTH:
            raise ValueError("completed reminder text is too long")
    payload["completedItems"] = completed_items
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
            updated["deletedAt"] = synced_at
            updated["expiresAt"] = epoch_seconds(synced_at) + DELETED_TTL_SECONDS
        updates.append(updated)
    return updates


def archive_deleted_reminder(user_id, record, s3_client=None, bucket_name=None):
    external_id = record["SK"].removeprefix("REMINDER#")
    deleted_at = record["deletedAt"]
    archive_history_event(
        user_id,
        "REMINDER_DELETED",
        deleted_at,
        {"reminder": record},
        external_id,
        s3_client=s3_client,
        bucket_name=bucket_name,
        required=True,
    )


def archive_history_event(
    user_id,
    event_type,
    occurred_at,
    data,
    identifier,
    s3_client=None,
    bucket_name=None,
    required=False,
):
    bucket_name = bucket_name or HISTORY_BUCKET_NAME
    s3_client = s3_client or S3
    if not bucket_name or s3_client is None:
        if required:
            raise RuntimeError("History archive is not configured")
        return False

    date_key = occurred_at[:10]
    safe_identifier = quote(identifier, safe="")
    safe_occurred_at = quote(occurred_at, safe="")
    key = f"users/{user_id}/events/{date_key}/{event_type}/{safe_occurred_at}-{safe_identifier}.json"
    payload = {
        "eventType": event_type,
        "userId": user_id,
        "occurredAt": occurred_at,
        **data,
    }
    try:
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(payload, default=json_default, sort_keys=True).encode("utf-8"),
            ContentType="application/json",
            ServerSideEncryption="AES256",
        )
    except Exception:
        if required:
            raise
        return False
    return True


def handler(event, _context):
    if event.get("source") == "aws.scheduler" and event.get("detail-type") == "DailySelection":
        return scheduled_daily_handler(event, _context)
    route = event.get("routeKey") or event.get("rawPath") or ""
    if route in {"POST /photon/webhook", "/photon/webhook"}:
        return photon_webhook_handler(event, _context)
    if route in {"GET /reminders/daily", "/reminders/daily"}:
        return daily_handler(event, _context)
    if route in {"GET /reminders/active", "/reminders/active"}:
        return active_handler(event, _context)
    if route in {"GET /reminders/archived", "/reminders/archived"}:
        return archived_handler(event, _context)
    if route in {"POST /reminders/restore", "/reminders/restore"}:
        return restore_handler(event, _context)
    if route in {"POST /reminders/complete", "/reminders/complete"}:
        return complete_handler(event, _context)
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
    for item in payload.get("completedItems", []):
        archive_history_event(
            user_id,
            "REMINDER_COMPLETED",
            item.get("modifiedAt") or synced_at,
            {"reminder": item, "source": "APPLE_REMINDERS"},
            item["externalId"],
        )
    existing_reminders = TABLE.query(
        KeyConditionExpression=Key("PK").eq(partition_key) & Key("SK").begins_with("REMINDER#")
    ).get("Items", [])
    incoming_ids = {item["externalId"] for item in payload["items"]}
    for record in missing_record_updates(existing_reminders, incoming_ids, synced_at):
        if record.get("status") == "DELETED":
            archive_deleted_reminder(user_id, record)
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
