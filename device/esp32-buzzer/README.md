# SCIR ESP32 buzzer/button firmware

Arduino IDE sketch for the Seeed Xiao ESP32-S3 board. The device subscribes to
the AWS IoT Core control topic over MQTT/mTLS, drives a buzzer when a washing
cycle ends, and publishes a `buzzer_silence` event when the user presses the
push-button.

## Files

- [`esp32-buzzer.ino`](esp32-buzzer.ino) - the sketch (compiled in Arduino IDE).
- [`secrets.h.example`](secrets.h.example) - template for `secrets.h`. Copy and
  fill in WiFi credentials, IoT endpoint and the three PEM blobs.
- `secrets.h` - gitignored; never commit.

## Hardware

| Function | Default pin | Notes |
| -------- | ----------- | ----- |
| Buzzer (active, SENV0005) | `D1` | Drive HIGH = sound on. Powered from 5 V if needed, signal from GPIO via current-limiting resistor. |
| Push-button (12 x 12 mm tact) | `D2` | Wired to GND, sketch uses `INPUT_PULLUP` (active-low). |
| GND / 5 V | - | Shared between modules. |

Override defaults by passing `-DBUZZER_PIN=...` / `-DBUTTON_PIN=...` via build
flags or by editing the `#ifndef` block at the top of the sketch.

## Required libraries

Install via Arduino IDE -> Tools -> Manage Libraries (or arduino-cli):

| Library | Tested version | Notes |
| ------- | -------------- | ----- |
| `esp32` board package by Espressif Systems | >= 3.0 | Provides `WiFi.h`, `WiFiClientSecure.h`. |
| `PubSubClient` by Nick O'Leary | >= 2.8 | MQTT client. |
| `ArduinoJson` by Benoit Blanchon | >= 7.0 | JSON parsing/serialisation. |

Board selection in Arduino IDE: `Tools -> Board -> esp32 -> XIAO_ESP32S3`.

## Fetching certificates and endpoint

The IoT Thing certificates and the data endpoint are managed by the Terragrunt
unit at [`cloud/environments/prod/iot`](../../cloud/environments/prod/iot).

Pre-requisites:

- AWS CLI configured with the `terraform` / `terraform_mfa` profiles described
  in [`cloud/README.md`](../../cloud/README.md) (`IAM user setup` section).
- A current MFA session (`AWS_PROFILE=terraform_mfa aws configure mfa-login`).

```bash
cd cloud/environments/prod/iot

# data-ATS endpoint -> MQTT_HOST
AWS_PROFILE=terraform terragrunt output -raw iot_data_endpoint

# Device cert + private key for the ESP32 IoT Thing (scir-prod-esp32-buzzer)
AWS_PROFILE=terraform terragrunt output -raw esp_certificate_pem
AWS_PROFILE=terraform terragrunt output -raw esp_private_key

# AWS-signed root CA used by IoT Core
curl -sSf https://www.amazontrust.com/repository/AmazonRootCA1.pem
```

Paste each PEM blob (including the `-----BEGIN .... -----END .....` lines) into
the matching `R"EOF( ... )EOF"` block in `secrets.h`. Set `MQTT_HOST` to the
endpoint value and keep `MQTT_CLIENT_ID = "scir-prod-esp32-buzzer"` - the IoT
policy in [`cloud/modules/iot-core/main.tf`](../../cloud/modules/iot-core/main.tf)
pins `iot:Connect` to that exact Thing name.

The same procedure applied to `shelly_certificate_pem` / `shelly_private_key`
yields the credentials needed by the Shelly plug (uploaded via its web UI, not
flashed onto the board).

## Build & upload

1. Open `esp32-buzzer.ino` in Arduino IDE.
2. Make sure `secrets.h` is present next to the `.ino` (the Arduino build
   automatically picks up sibling headers).
3. Select the Xiao ESP32-S3 board and the right serial port.
4. Click `Upload`. Open the serial monitor at `115200` baud to follow boot,
   WiFi association, NTP sync and MQTT connect logs (prefixed with `[scir]`).

## Behaviour summary

```
boot -> WiFi -> NTP -> WiFiClientSecure(CA+cert+key)
     -> MQTT connect to AWS IoT Core, port 8883
     -> subscribe scir/prod/washer/buzzer/events (QoS 1)
```

While running:

| Trigger | Action |
| ------- | ------ |
| MQTT msg `event_type == "cycle_end"` or `action == "buzzer_on"` | Buzzer ON |
| MQTT msg `event_type == "buzzer_silence"` or `action == "buzzer_off"` | Buzzer OFF |
| MQTT msg `event_type == "cycle_start"` | Logged, no buzzer change |
| Local button press (debounced, active-low) | Buzzer OFF immediately + publish `buzzer_silence` event with `source: "esp32"` on `scir/prod/washer/buzzer/events` |

Published payload:

```json
{
  "event_type": "buzzer_silence",
  "action": "buzzer_off",
  "source": "esp32",
  "device_id": "washing-machine",
  "ts": 1735689600000
}
```

## Troubleshooting

- `mqtt connect failed state=-2`: TLS handshake failed. Check that the clock
  was synced (NTP) and that all three PEM blocks decode without trailing
  whitespace or stray `\r`.
- Stuck on `connecting to wifi`: confirm 2.4 GHz SSID, `WIFI_SSID` / `WIFI_PASSWORD`
  values in `secrets.h`.
- Connects but no messages arrive: verify with `mosquitto_sub` from
  [`cloud/README.md`](../../cloud/README.md) (`Emulate the consumer board`).
- Connects but publish is rejected: confirm `MQTT_CLIENT_ID` equals the Thing
  name and that the ESP IoT policy in
  [`cloud/modules/iot-core/main.tf`](../../cloud/modules/iot-core/main.tf) was
  applied.
