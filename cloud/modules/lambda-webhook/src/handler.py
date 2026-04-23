import json
import logging
import os
import time
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SECRETS_CLIENT = boto3.client("secretsmanager")
IOT_DATA_CLIENT = boto3.client(
    "iot-data", endpoint_url=f"https://{os.environ['IOT_DATA_ENDPOINT']}"
)

CONTROL_TOPIC = os.environ["CONTROL_TOPIC"]
AUTH_SECRET_ARN = os.environ["AUTH_SECRET_ARN"]
DEVICE_ID = os.environ.get("DEVICE_ID", "washing-machine")

AUTH_TOKEN_CACHE: str | None = None


def lambda_handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    headers = _normalize_headers(event.get("headers", {}))
    provided_token = headers.get("x-scir-token", "")
    expected_token = _read_auth_token()

    if not expected_token or provided_token != expected_token:
        return _response(401, {"message": "Unauthorized"})

    body = _parse_body(event.get("body"))
    device_id = str(body.get("device_id", DEVICE_ID))
    timestamp_ms = int(time.time() * 1000)

    payload = {
        "event_type": "buzzer_silence",
        "action": "buzzer_off",
        "source": "api_webhook",
        "device_id": device_id,
        "ts": timestamp_ms,
    }

    IOT_DATA_CLIENT.publish(
        topic=CONTROL_TOPIC,
        qos=1,
        payload=json.dumps(payload).encode("utf-8"),
    )

    logger.info(json.dumps({"kind": "event", **payload}))
    return _response(200, {"status": "ok", "published": payload})


def _parse_body(raw_body: Any) -> dict[str, Any]:
    if raw_body is None:
        return {}

    if isinstance(raw_body, str):
        if not raw_body.strip():
            return {}
        try:
            parsed = json.loads(raw_body)
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            return {}

    if isinstance(raw_body, dict):
        return raw_body

    return {}


def _normalize_headers(headers: Any) -> dict[str, str]:
    if not isinstance(headers, dict):
        return {}
    return {str(k).lower(): str(v) for k, v in headers.items()}


def _read_auth_token() -> str | None:
    global AUTH_TOKEN_CACHE

    if AUTH_TOKEN_CACHE is not None:
        return AUTH_TOKEN_CACHE

    try:
        result = SECRETS_CLIENT.get_secret_value(SecretId=AUTH_SECRET_ARN)
    except ClientError as exc:
        logger.warning("Failed reading auth token secret: %s", exc)
        AUTH_TOKEN_CACHE = ""
        return None

    secret_string = result.get("SecretString", "")
    if not secret_string:
        AUTH_TOKEN_CACHE = ""
        return None

    try:
        secret_json = json.loads(secret_string)
        if isinstance(secret_json, dict) and "token" in secret_json:
            AUTH_TOKEN_CACHE = str(secret_json["token"])
            return AUTH_TOKEN_CACHE
    except json.JSONDecodeError:
        pass

    AUTH_TOKEN_CACHE = secret_string
    return AUTH_TOKEN_CACHE


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
