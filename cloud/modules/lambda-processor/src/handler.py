import json
import logging
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CLOUDWATCH_CLIENT = boto3.client("cloudwatch")
SECRETS_CLIENT = boto3.client("secretsmanager")
IOT_DATA_CLIENT = boto3.client(
    "iot-data", endpoint_url=f"https://{os.environ['IOT_DATA_ENDPOINT']}"
)

METRICS_NAMESPACE = os.environ["METRICS_NAMESPACE"]
READINGS_METRIC_NAME = os.environ["READINGS_METRIC_NAME"]
EVENTS_METRIC_NAME = os.environ["EVENTS_METRIC_NAME"]
CONTROL_TOPIC = os.environ["CONTROL_TOPIC"]
DEVICE_ID = os.environ.get("DEVICE_ID", "washing-machine")
DISCORD_WEBHOOK_SECRET_ARN = os.environ.get("DISCORD_WEBHOOK_SECRET_ARN", "")

START_POWER_THRESHOLD = float(os.environ.get("START_POWER_THRESHOLD", "10"))
END_POWER_THRESHOLD = float(os.environ.get("END_POWER_THRESHOLD", "3"))
LOW_POWER_WINDOW_SECONDS = int(os.environ.get("LOW_POWER_WINDOW_SECONDS", "180"))

EVENT_CODE_BY_TYPE = {
    "cycle_start": 1,
    "cycle_end": 2,
    "buzzer_silence": 3,
}

DISCORD_WEBHOOK_URL_CACHE: str | None = None


def lambda_handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    readings = _extract_readings(event)
    if not readings:
        return {"processed": 0, "events_emitted": 0}

    readings.sort(key=lambda item: item["ts_ms"])
    _put_reading_metrics(readings)

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


def _put_reading_metrics(readings: list[dict[str, Any]]) -> None:
    metric_data: list[dict[str, Any]] = []

    for reading in readings:
        metric_data.append(
            {
                "MetricName": READINGS_METRIC_NAME,
                "Dimensions": [{"Name": "device_id", "Value": DEVICE_ID}],
                "Timestamp": _to_datetime(reading["ts_ms"]),
                "Value": reading["power"],
                "Unit": "None",
            }
        )

    _put_metric_data(metric_data)


def _put_event_metric(event_type: str, ts_ms: int) -> None:
    event_code = float(EVENT_CODE_BY_TYPE.get(event_type, 0))
    metric_data = [
        {
            "MetricName": EVENTS_METRIC_NAME,
            "Dimensions": [{"Name": "device_id", "Value": DEVICE_ID}],
            "Timestamp": _to_datetime(ts_ms),
            "Value": event_code,
            "Unit": "Count",
        }
    ]
    _put_metric_data(metric_data)


def _put_metric_data(metric_data: list[dict[str, Any]]) -> None:
    if not metric_data:
        return

    try:
        for idx in range(0, len(metric_data), 20):
            CLOUDWATCH_CLIENT.put_metric_data(
                Namespace=METRICS_NAMESPACE,
                MetricData=metric_data[idx : idx + 20],
            )
    except ClientError as exc:
        logger.error("CloudWatch put_metric_data failed: %s", exc)
        raise


def _current_cycle_state() -> str:
    now = int(time.time() * 1000)
    lookback_start = now - (24 * 60 * 60 * 1000)
    points = _get_metric_points(
        metric_name=EVENTS_METRIC_NAME,
        start_ts_ms=lookback_start,
        end_ts_ms=now,
        period_seconds=60,
        stat="Maximum",
    )

    for _ts_ms, value in points:
        event_code = int(round(value))
        if event_code == EVENT_CODE_BY_TYPE["cycle_start"]:
            return "running"
        if event_code == EVENT_CODE_BY_TYPE["cycle_end"]:
            return "idle"

    return "idle"


def _should_emit_cycle_end(latest_ts_ms: int) -> bool:
    window_start_ms = latest_ts_ms - (LOW_POWER_WINDOW_SECONDS * 1000)
    points = _get_metric_points(
        metric_name=READINGS_METRIC_NAME,
        start_ts_ms=window_start_ms,
        end_ts_ms=latest_ts_ms,
        period_seconds=60,
        stat="Maximum",
    )
    if not points:
        return False

    max_power = max(value for _ts_ms, value in points)
    first_seen_ms = min(ts_ms for ts_ms, _value in points)
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

    _put_event_metric(event_type, ts_ms)

    _publish_control_event(event_payload)
    _send_discord_notification(event_payload)
    return event_payload


def _get_metric_points(
    metric_name: str,
    start_ts_ms: int,
    end_ts_ms: int,
    period_seconds: int,
    stat: str,
) -> list[tuple[int, float]]:
    points: list[tuple[int, float]] = []
    next_token: str | None = None

    while True:
        query = {
            "Id": "m1",
            "MetricStat": {
                "Metric": {
                    "Namespace": METRICS_NAMESPACE,
                    "MetricName": metric_name,
                    "Dimensions": [{"Name": "device_id", "Value": DEVICE_ID}],
                },
                "Period": period_seconds,
                "Stat": stat,
            },
            "ReturnData": True,
        }

        params: dict[str, Any] = {
            "MetricDataQueries": [query],
            "StartTime": _to_datetime(start_ts_ms),
            "EndTime": _to_datetime(end_ts_ms),
            "ScanBy": "TimestampDescending",
            "MaxDatapoints": 500,
        }
        if next_token:
            params["NextToken"] = next_token

        response = CLOUDWATCH_CLIENT.get_metric_data(**params)
        results = response.get("MetricDataResults", [])
        if results:
            timestamps = results[0].get("Timestamps", [])
            values = results[0].get("Values", [])
            for ts, value in zip(timestamps, values):
                ts_ms = int(ts.replace(tzinfo=timezone.utc).timestamp() * 1000)
                points.append((ts_ms, float(value)))

        next_token = response.get("NextToken")
        if not next_token:
            break

    points.sort(key=lambda item: item[0], reverse=True)
    return points


def _to_datetime(ts_ms: int) -> datetime:
    return datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc)


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


