import base64
import json
import os

EXPECTED_USERNAME: str = os.environ["EXPECTED_USERNAME"]
EXPECTED_PASSWORD: str = os.environ["EXPECTED_PASSWORD"]
ACCOUNT_ID: str = os.environ["ACCOUNT_ID"]
AWS_REGION: str = os.environ["AWS_REGION_NAME"]
THING_NAME: str = os.environ["THING_NAME"]
PUBLISH_TOPIC: str = os.environ["PUBLISH_TOPIC"]


def lambda_handler(event: dict, _context: object) -> dict:
    mqtt = event.get("protocolData", {}).get("mqtt", {})

    # Strip the authorizer query string appended by the client, e.g.
    # "mydevice?x-amzn-iot-custom-auth-authorizer-name=foo" → "mydevice"
    raw_username: str = mqtt.get("username", "")
    username = raw_username.split("?")[0]

    password_b64: str = mqtt.get("password", "")
    try:
        password = base64.b64decode(password_b64).decode("utf-8")
    except Exception:
        password = ""

    if username != EXPECTED_USERNAME or password != EXPECTED_PASSWORD:
        print(f"auth denied: username_match={username == EXPECTED_USERNAME} password_match={password == EXPECTED_PASSWORD}")
        return {"isAuthenticated": False, "principalId": "unauthorized", "policyDocuments": []}

    principal_id = "".join(c for c in THING_NAME if c.isalnum())
    response = {
        "isAuthenticated": True,
        "principalId": principal_id,
        "disconnectAfterInSeconds": 86400,
        "refreshAfterInSeconds": 300,
        "policyDocuments": [
            {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": ["iot:Connect"],
                        "Resource": f"arn:aws:iot:{AWS_REGION}:{ACCOUNT_ID}:client/{THING_NAME}",
                    },
                    {
                        "Effect": "Allow",
                        "Action": ["iot:Publish"],
                        "Resource": f"arn:aws:iot:{AWS_REGION}:{ACCOUNT_ID}:topic/{PUBLISH_TOPIC}",
                    },
                ],
            }
        ],
    }
    return response
