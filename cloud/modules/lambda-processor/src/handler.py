import json
import logging
import os
import time
import urllib.error
import urllib.request
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

WRITE_CLIENT = boto3.client("timestream-write")
QUERY_CLIENT = boto3.client("timestream-query")
SECRETS_CLIENT = boto3.client("secretsmanager")
IOT_DATA_CLIENT = boto3.client(
    "iot-data", endpoint_url=f"https://{os.environ['IOT_DATA_ENDPOINT']}"
)

TIMESTREAM_DATABASE = os.environ["TIMESTREAM_DATABASE"]
READINGS_TABLE = os.environ["READINGS_TABLE"]
EVENTS_TABLE = os.environ["EVENTS_TABLE"]
CONTROL_TOPIC = os.environ["CONTROL_TOPIC"]
DEVICE_ID = os.environ.get("DEVICE_ID", "washing-machine")
DISCORD_WEBHOOK_SECRET_ARN = os.environ.get("DISCORD_WEBHOOK_SECRET_ARN", "")

START_POWER_THRESHOLD = float(os.environ.get("START_POWER_THRESHOLD", "10"))
END_POWER_THRESHOLD = float(os.environ.get("END_POWER_THRESHOLD", "3"))
LOW_POWER_WINDOW_SECONDS = int(os.environ.get("LOW_POWER_WINDOW_SECONDS", "180"))

DISCORD_WEBHOOK_URL_CACHE: str | None = None


def lambda_handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    readings = _extract_readings(event)
    if not readings:
        return {"processed": 0, "events_emitted": 0}

    readings.sort(key=lambda item: item["ts_ms"])
    _write_readings(readings)

    cycle_state = _current_cycle_state()
    emitted_events: list[dict[str, Any]] = []

    if cycle_state == "idle":
        for reading in readings:
            if reading["power"] >= START_POWER_THRESHOLD:
                cycle_state = "running"
                emitted_events.append(
                    _emit_cycle_event(
                        event_type="cycle_start",
                        ts_ms=reading["ts_ms"],
                        action="cycle_started",
                    )
                )
                break

    latest_ts_ms = readings[-1]["ts_ms"]
    if cycle_state == "running" and _should_emit_cycle_end(latest_ts_ms):
        emitted_events.append(
            _emit_cycle_event(
                event_type="cycle_end",
                ts_ms=latest_ts_ms,
                action="buzzer_on",
            )
        )

    return {
        "processed": len(readings),
        "events_emitted": len(emitted_events),
        "latest_ts_ms": latest_ts_ms,
    }


def _extract_readings(event: dict[str, Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []

    for record in event.get("Records", []):
        try:
            body = json.loads(record.get("body", "{}"))
        except json.JSONDecodeError:
            logger.warning("Skipping malformed SQS payload")
            continue

        power = _extract_apower(body)
        if power is None:
            continue

        topic = str(body.get("mqtt_topic", "unknown"))
        ts_ms = _extract_timestamp_ms(body)

        logger.info(
            json.dumps(
                {
                    "kind": "reading",
                    "device_id": DEVICE_ID,
                    "power": power,
                    "topic": topic,
                    "ts": ts_ms,
                }
            )
        )

        result.append(
            {
                "power": power,
                "topic": topic,
                "ts_ms": ts_ms,
            }
        )

    return result


def _extract_apower(payload: dict[str, Any]) -> float | None:
    direct = payload.get("apower")
    if isinstance(direct, (int, float)):
        return float(direct)

    switch_zero = payload.get("switch:0")
    if isinstance(switch_zero, dict):
        nested = switch_zero.get("apower")
        if isinstance(nested, (int, float)):
            return float(nested)

    return None


def _extract_timestamp_ms(payload: dict[str, Any]) -> int:
    ts = payload.get("ingest_ts")
    if isinstance(ts, (int, float)):
        return int(ts)
    return int(time.time() * 1000)


def _write_readings(readings: list[dict[str, Any]]) -> None:
    records: list[dict[str, Any]] = []

    for reading in readings:
        records.append(
            {
                "Dimensions": [
                    {"Name": "device_id", "Value": DEVICE_ID},
                    {"Name": "mqtt_topic", "Value": reading["topic"]},
                    {"Name": "source", "Value": "shelly"},
                ],
                "MeasureName": "apower",
                "MeasureValue": str(reading["power"]),
                "MeasureValueType": "DOUBLE",
                "Time": str(reading["ts_ms"]),
                "TimeUnit": "MILLISECONDS",
            }
        )

        if len(records) == 100:
            _write_timestream_records(READINGS_TABLE, records)
            records = []

    if records:
        _write_timestream_records(READINGS_TABLE, records)


def _write_timestream_records(table_name: str, records: list[dict[str, Any]]) -> None:
    try:
        WRITE_CLIENT.write_records(
            DatabaseName=TIMESTREAM_DATABASE,
            TableName=table_name,
            Records=records,
        )
    except ClientError as exc:
        logger.error("Timestream write failed: %s", exc)
        raise


def _current_cycle_state() -> str:
    query = (
        f"SELECT event_type FROM \"{TIMESTREAM_DATABASE}\".\"{EVENTS_TABLE}\" "
        "WHERE measure_name = 'event_value' "
        f"AND device_id = '{_sql_escape(DEVICE_ID)}' "
        "AND event_type IN ('cycle_start', 'cycle_end') "
        "ORDER BY time DESC LIMIT 1"
    )

    rows = _query_rows(query)
    if not rows:
        return "idle"

    event_type = _scalar(rows[0], 0)
    return "running" if event_type == "cycle_start" else "idle"


def _should_emit_cycle_end(latest_ts_ms: int) -> bool:
    window_start_ms = latest_ts_ms - (LOW_POWER_WINDOW_SECONDS * 1000)

    query = (
        "SELECT "
        "MAX(measure_value::double) AS max_power, "
        "to_milliseconds(MIN(time)) AS first_seen_ms "
        f"FROM \"{TIMESTREAM_DATABASE}\".\"{READINGS_TABLE}\" "
        f"WHERE device_id = '{_sql_escape(DEVICE_ID)}' "
        "AND measure_name = 'apower' "
        f"AND time BETWEEN from_milliseconds({window_start_ms}) "
        f"AND from_milliseconds({latest_ts_ms})"
    )

    rows = _query_rows(query)
    if not rows:
        return False

    max_power_str = _scalar(rows[0], 0)
    first_seen_ms_str = _scalar(rows[0], 1)
    if max_power_str is None or first_seen_ms_str is None:
        return False

    try:
        max_power = float(max_power_str)
        first_seen_ms = int(first_seen_ms_str)
    except ValueError:
        return False

    return max_power <= END_POWER_THRESHOLD and first_seen_ms <= window_start_ms


def _emit_cycle_event(event_type: str, ts_ms: int, action: str) -> dict[str, Any]:
    event_payload = {
        "event_type": event_type,
        "action": action,
        "source": "lambda_processor",
        "device_id": DEVICE_ID,
        "ts": ts_ms,
    }

    logger.info(json.dumps({"kind": "event", **event_payload}))

    _write_timestream_records(
        EVENTS_TABLE,
        [
            {
                "Dimensions": [
                    {"Name": "device_id", "Value": DEVICE_ID},
                    {"Name": "event_type", "Value": event_type},
                    {"Name": "source", "Value": "lambda_processor"},
                ],
                "MeasureName": "event_value",
                "MeasureValue": "1",
                "MeasureValueType": "BIGINT",
                "Time": str(ts_ms),
                "TimeUnit": "MILLISECONDS",
            }
        ],
    )

    _publish_control_event(event_payload)
    _send_discord_notification(event_payload)
    return event_payload


def _publish_control_event(payload: dict[str, Any]) -> None:
    IOT_DATA_CLIENT.publish(
        topic=CONTROL_TOPIC,
        qos=1,
        payload=json.dumps(payload).encode("utf-8"),
    )


def _send_discord_notification(event_payload: dict[str, Any]) -> None:
    webhook_url = _discord_webhook_url()
    if not webhook_url:
        return

    if event_payload["event_type"] == "cycle_end":
        message = "Pralka zakonczyla cykl. Buzzer aktywny."
    elif event_payload["event_type"] == "cycle_start":
        message = "Pralka rozpoczela cykl."
    else:
        message = f"Wydarzenie: {event_payload['event_type']}"

    body = json.dumps({"content": message}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=5):
            return
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        logger.warning("Discord webhook send failed: %s", exc)


def _discord_webhook_url() -> str | None:
    global DISCORD_WEBHOOK_URL_CACHE

    if DISCORD_WEBHOOK_URL_CACHE is not None:
        return DISCORD_WEBHOOK_URL_CACHE

    if not DISCORD_WEBHOOK_SECRET_ARN:
        DISCORD_WEBHOOK_URL_CACHE = ""
        return None

    try:
        response = SECRETS_CLIENT.get_secret_value(SecretId=DISCORD_WEBHOOK_SECRET_ARN)
    except ClientError as exc:
        logger.warning("Unable to read Discord secret: %s", exc)
        DISCORD_WEBHOOK_URL_CACHE = ""
        return None

    secret_string = response.get("SecretString", "")
    if not secret_string:
        DISCORD_WEBHOOK_URL_CACHE = ""
        return None

    try:
        secret_json = json.loads(secret_string)
        if isinstance(secret_json, dict) and "url" in secret_json:
            DISCORD_WEBHOOK_URL_CACHE = str(secret_json["url"])
            return DISCORD_WEBHOOK_URL_CACHE
    except json.JSONDecodeError:
        pass

    DISCORD_WEBHOOK_URL_CACHE = secret_string
    return DISCORD_WEBHOOK_URL_CACHE


def _query_rows(query: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    next_token: str | None = None

    while True:
        if next_token:
            result = QUERY_CLIENT.query(QueryString=query, NextToken=next_token)
        else:
            result = QUERY_CLIENT.query(QueryString=query)

        rows.extend(result.get("Rows", []))
        next_token = result.get("NextToken")
        if not next_token:
            break

    return rows


def _scalar(row: dict[str, Any], index: int) -> str | None:
    try:
        value = row["Data"][index].get("ScalarValue")
    except (KeyError, IndexError, TypeError):
        return None
    return value


def _sql_escape(value: str) -> str:
    return value.replace("'", "''")
