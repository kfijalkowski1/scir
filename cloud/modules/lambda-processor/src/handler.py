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
DEVICE_ID = os.environ["DEVICE_ID"]
DISCORD_WEBHOOK_SECRET_ARN = os.environ["DISCORD_WEBHOOK_SECRET_ARN"]
WEBHOOK_AUTH_TOKEN = os.environ["WEBHOOK_AUTH_TOKEN"]
API_SILENCE_ENDPOINT = os.environ["API_SILENCE_ENDPOINT"]
START_POWER_THRESHOLD = float(os.environ["START_POWER_THRESHOLD"])
END_POWER_THRESHOLD = float(os.environ["END_POWER_THRESHOLD"])
LOW_POWER_WINDOW_SECONDS = int(os.environ["LOW_POWER_WINDOW_SECONDS"])

EVENT_CODE_BY_TYPE = {
    "cycle_start": 1,
    "cycle_end": 2,
    "buzzer_silence": 3,
}

DISCORD_WEBHOOK_URL_CACHE: str | None = None
API_TOKEN_CACHE: str | None = None


def lambda_handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    logger.info("Received event: %s", json.dumps(event))
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
    if cycle_state == "running" and _should_emit_cycle_end(latest_ts_ms, readings):
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
    
    if "Records" not in event:
        raise ValueError("Event does not contain 'Records'")

    records = event["Records"]
    if not records:
        raise ValueError("Event 'Records' array is empty")

    for record in records:
        body_str = record.get("body")
        if not body_str:
            raise ValueError("SQS record missing 'body'")

        try:
            body = json.loads(body_str)
        except json.JSONDecodeError as exc:
            raise ValueError(f"Malformed JSON in SQS body: {exc}")

        power = _extract_apower(body)
        if power is None:
            raise ValueError(f"Payload missing apower measurement: {body}")

        topic = str(body.get("mqtt_topic", "unknown"))
        if topic == "unknown":
            raise ValueError("Payload missing mqtt_topic")
            
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


def _should_emit_cycle_end(latest_ts_ms: int, readings: list[dict[str, Any]]) -> bool:
    window_start_ms = latest_ts_ms - (LOW_POWER_WINDOW_SECONDS * 1000)
    
    recent_readings = [r for r in readings if r["ts_ms"] >= window_start_ms]
    if recent_readings:
        max_recent = max(r["power"] for r in recent_readings)
        if max_recent > END_POWER_THRESHOLD:
            return False

    oldest_recent_ts = min(r["ts_ms"] for r in recent_readings) if recent_readings else latest_ts_ms
    cw_end_ms = oldest_recent_ts
    
    if cw_end_ms > window_start_ms:
        points = _get_metric_points(
            metric_name=READINGS_METRIC_NAME,
            start_ts_ms=window_start_ms,
            end_ts_ms=cw_end_ms,
            period_seconds=60,
            stat="Maximum",
        )
        if points:
            max_cw = max(value for _ts_ms, value in points)
            if max_cw > END_POWER_THRESHOLD:
                return False
        elif not recent_readings:
            return False

    return True


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

        try:
            response = CLOUDWATCH_CLIENT.get_metric_data(**params)
        except ClientError as exc:
            raise RuntimeError(f"Failed to get metric data: {exc}")

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
    try:
        IOT_DATA_CLIENT.publish(
            topic=CONTROL_TOPIC,
            qos=1,
            payload=json.dumps(payload).encode("utf-8"),
        )
    except ClientError as exc:
        raise RuntimeError(f"IoT publish control event failed: {exc}")


def _send_discord_notification(event_payload: dict[str, Any]) -> None:
    webhook_url = _discord_webhook_url()
    if not webhook_url:
        raise ValueError("Discord webhook URL not configured")

    if event_payload["event_type"] == "cycle_end":
        message = ":robot: Washing cycle ended."
    elif event_payload["event_type"] == "cycle_start":
        message = ":robot: Washing cycle started."
    else:
        message = f":robot: Event: {event_payload['event_type']}"

    body = json.dumps({"content": message}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=body,
        headers={
            "Content-Type": "application/json",
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/35.0.1916.47 Safari/537.36'
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=5):
            return
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        raise RuntimeError(f"Discord webhook send failed: {exc}")


def _discord_webhook_url() -> str | None:
    global DISCORD_WEBHOOK_URL_CACHE

    if DISCORD_WEBHOOK_URL_CACHE is not None:
        return DISCORD_WEBHOOK_URL_CACHE

    if not DISCORD_WEBHOOK_SECRET_ARN:
        raise ValueError("Discord webhook secret ARN not configured")

    try:
        response = SECRETS_CLIENT.get_secret_value(SecretId=DISCORD_WEBHOOK_SECRET_ARN)
    except ClientError as exc:
        raise RuntimeError(f"Unable to read Discord secret: {exc}")

    secret_string = response.get("SecretString", "")
    if not secret_string:
        raise ValueError("Discord secret has no SecretString")

    try:
        secret_json = json.loads(secret_string)
        if isinstance(secret_json, dict) and "url" in secret_json:
            DISCORD_WEBHOOK_URL_CACHE = str(secret_json["url"])
            return DISCORD_WEBHOOK_URL_CACHE
        else:
            raise ValueError("Discord secret JSON does not contain 'url' key")
    except json.JSONDecodeError as e:
        raise ValueError(f"Discord secret string is not valid JSON: {repr(e)}")
