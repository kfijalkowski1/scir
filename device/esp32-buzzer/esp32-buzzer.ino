// SCIR - ESP32 buzzer/button consumer for AWS IoT Core
//
// Target board: Seeed Xiao ESP32-S3 (board package: esp32 by Espressif Systems)
// Communication: MQTT over mTLS (port 8883), broker = AWS IoT Core Data-ATS endpoint.
//
// All host / credential / certificate material lives in secrets.h, which is
// gitignored. Copy secrets.h.example to secrets.h and fill the values from
// `terragrunt output` in cloud/environments/prod/iot/.

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <time.h>
#include <driver/gpio.h>

#include "secrets.h"

// ---- Hardware pin mapping (Xiao ESP32-S3 silk-screen labels) ----------------
// Match the working breadboard wiring: buzzer on D4/GPIO5, button on D5/GPIO6.
#ifndef BUZZER_PIN
#define BUZZER_PIN 5
#endif

#ifndef BUTTON_PIN
#define BUTTON_PIN 6
#endif

// Set to 1 if the buzzer sounds when the pin is LOW (inverted / sinking drive).
#ifndef BUZZER_ACTIVE_LOW
#define BUZZER_ACTIVE_LOW 0
#endif

// ---- Protocol-level constants (must match cloud/root.hcl) -------------------
static const char* CONTROL_TOPIC = "scir/prod/washer/buzzer/events";
static const char* DEVICE_ID     = "washing-machine";

// ---- Reconnect / debounce tuning -------------------------------------------
static const unsigned long WIFI_RETRY_INTERVAL_MS  = 500;
static const unsigned long MQTT_RETRY_INTERVAL_MS  = 5000;
static const unsigned long BUTTON_DEBOUNCE_MS      = 50;
static const size_t        MQTT_BUFFER_SIZE        = 512;

// ---- Globals ---------------------------------------------------------------
WiFiClientSecure secureClient;
PubSubClient     mqttClient(secureClient);

static bool          buzzerOn           = false;
static bool          userSilenced       = false;
static bool          lastButtonReading  = HIGH;
static bool          stableButtonState  = HIGH;
static unsigned long lastButtonChangeMs = 0;
static unsigned long lastMqttAttemptMs  = 0;

// ---- Forward declarations --------------------------------------------------
static void initHardwarePins();
static void configureButtonInput();
static void applyBuzzerOutput();
static void connectWifi();
static void syncClock();
static void onMqttMessage(char* topic, byte* payload, unsigned int length);
static bool reconnectMqtt();
static void handleButton();
static void setBuzzer(bool on);
static void publishSilenceEvent();

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("[scir] boot");
  Serial.printf("[scir] pins buzzer=%d button=%d\n", BUZZER_PIN, BUTTON_PIN);

  initHardwarePins();

  connectWifi();
  initHardwarePins();

  syncClock();
  initHardwarePins();

  // mTLS material from secrets.h.
  secureClient.setCACert(AWS_ROOT_CA_PEM);
  secureClient.setCertificate(DEVICE_CERT_PEM);
  secureClient.setPrivateKey(DEVICE_PRIVATE_KEY_PEM);

  mqttClient.setBufferSize(MQTT_BUFFER_SIZE);
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setKeepAlive(60);
  mqttClient.setCallback(onMqttMessage);
}

void loop() {
  handleButton();

  if (WiFi.status() != WL_CONNECTED) {
    connectWifi();
  }

  if (!mqttClient.connected()) {
    unsigned long now = millis();
    if (now - lastMqttAttemptMs >= MQTT_RETRY_INTERVAL_MS) {
      lastMqttAttemptMs = now;
      if (reconnectMqtt()) {
        initHardwarePins();
      }
    }
  } else {
    mqttClient.loop();
  }

  if (!buzzerOn) {
    applyBuzzerOutput();
  }

  handleButton();
}

// ----------------------------------------------------------------------------
// Wi-Fi & clock
// ----------------------------------------------------------------------------

static void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  Serial.printf("[scir] connecting to wifi: %s\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  while (WiFi.status() != WL_CONNECTED) {
    handleButton();
    delay(WIFI_RETRY_INTERVAL_MS);
    Serial.print('.');
  }

  Serial.println();
  Serial.print("[scir] wifi connected, ip=");
  Serial.println(WiFi.localIP());
}

static void syncClock() {
  // TLS verification requires a plausible system time. Use NTP and block until
  // the clock is at least past 2024-01-01 UTC (epoch >= 1704067200).
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("[scir] syncing clock");
  time_t now = time(nullptr);
  while (now < 1704067200) {
    handleButton();
    delay(500);
    Serial.print('.');
    now = time(nullptr);
  }
  Serial.println();
  Serial.printf("[scir] clock synced, epoch=%ld\n", (long)now);
}

// ----------------------------------------------------------------------------
// MQTT
// ----------------------------------------------------------------------------

static bool reconnectMqtt() {
  Serial.printf("[scir] mqtt connect %s:%d as %s\n", MQTT_HOST, MQTT_PORT, MQTT_CLIENT_ID);

  if (!mqttClient.connect(MQTT_CLIENT_ID)) {
    int state = mqttClient.state();
    int tlsErr = secureClient.lastError(nullptr, 0);
    Serial.printf("[scir] mqtt connect failed state=%d tls_err=%d\n", state, tlsErr);
    return false;
  }

  // QoS 1 is mandatory: AWS IoT does not retain QoS 2, and the control topic
  // emits idempotent events that we want delivered at-least-once.
  if (!mqttClient.subscribe(CONTROL_TOPIC, 1)) {
    Serial.println("[scir] mqtt subscribe failed");
    mqttClient.disconnect();
    return false;
  }

  Serial.printf("[scir] mqtt subscribed to %s\n", CONTROL_TOPIC);
  return true;
}

static void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  Serial.printf("[scir] msg topic=%s len=%u\n", topic, length);

  StaticJsonDocument<384> doc;
  DeserializationError err = deserializeJson(doc, payload, length);
  if (err) {
    Serial.printf("[scir] json parse failed: %s\n", err.c_str());
    return;
  }

  const char* eventType = doc["event_type"] | "";
  const char* action    = doc["action"]     | "";
  const char* source    = doc["source"]     | "";

  Serial.printf("[scir] event_type=%s action=%s source=%s\n", eventType, action, source);

  if (strcmp(eventType, "cycle_start") == 0) {
    userSilenced = false;
    return;
  }

  if (userSilenced &&
      (strcmp(eventType, "cycle_end") == 0 || strcmp(action, "buzzer_on") == 0)) {
    Serial.println("[scir] ignoring buzzer_on (silenced locally)");
    return;
  }

  if (strcmp(eventType, "cycle_end") == 0 || strcmp(action, "buzzer_on") == 0) {
    setBuzzer(true);
  } else if (strcmp(eventType, "buzzer_silence") == 0 || strcmp(action, "buzzer_off") == 0) {
    setBuzzer(false);
  }
}

static void publishSilenceEvent() {
  if (!mqttClient.connected()) {
    Serial.println("[scir] silence press ignored: mqtt not connected");
    return;
  }

  StaticJsonDocument<192> doc;
  doc["event_type"] = "buzzer_silence";
  doc["action"]     = "buzzer_off";
  doc["source"]     = "esp32";
  doc["device_id"]  = DEVICE_ID;
  doc["ts"]         = (uint64_t)time(nullptr) * 1000ULL;

  char buffer[192];
  size_t n = serializeJson(doc, buffer, sizeof(buffer));

  bool ok = mqttClient.publish(CONTROL_TOPIC, (const uint8_t*)buffer, n, false);
  Serial.printf("[scir] published silence event (%u B) ok=%d\n", (unsigned)n, (int)ok);
}

// ----------------------------------------------------------------------------
// Hardware helpers
// ----------------------------------------------------------------------------

static int buzzerDriveLevel(bool soundOn) {
#if BUZZER_ACTIVE_LOW
  return soundOn ? 0 : 1;
#else
  return soundOn ? 1 : 0;
#endif
}

static void applyBuzzerOutput() {
  const gpio_num_t pin = (gpio_num_t)BUZZER_PIN;

  Wire.end();
  gpio_reset_pin(pin);
  gpio_set_direction(pin, GPIO_MODE_OUTPUT);
  gpio_set_pull_mode(pin, GPIO_FLOATING);
  gpio_set_level(pin, buzzerDriveLevel(buzzerOn));
}

static void configureButtonInput() {
  const gpio_num_t pin = (gpio_num_t)BUTTON_PIN;

  gpio_reset_pin(pin);
  gpio_set_direction(pin, GPIO_MODE_INPUT);
  gpio_set_pull_mode(pin, GPIO_PULLUP_ONLY);
}

static void initHardwarePins() {
  applyBuzzerOutput();
  configureButtonInput();

  int reading = gpio_get_level((gpio_num_t)BUTTON_PIN);
  lastButtonReading = reading;
  stableButtonState = reading;
  lastButtonChangeMs = millis();

  Serial.printf(
    "[scir] hw init buzzer_on=%d buzzer_gpio=%d button_gpio=%d\n",
    (int)buzzerOn,
    gpio_get_level((gpio_num_t)BUZZER_PIN),
    reading
  );
}

static void setBuzzer(bool on) {
  buzzerOn = on;
  digitalWrite(BUZZER_PIN, buzzerOn ? HIGH : LOW);
  Serial.printf(
    "[scir] buzzer=%s gpio_level=%d\n",
    on ? "ON" : "OFF",
    gpio_get_level((gpio_num_t)BUZZER_PIN)
  );
}

static void handleButton() {
  configureButtonInput();
  int reading = gpio_get_level((gpio_num_t)BUTTON_PIN);

  if (reading != lastButtonReading) {
    lastButtonChangeMs = millis();
  }

  if (millis() - lastButtonChangeMs > BUTTON_DEBOUNCE_MS) {
    if (reading != stableButtonState) {
      stableButtonState = reading;
      // Active-low: pull-up means LOW == pressed.
      if (stableButtonState == LOW) {
        Serial.println("[scir] button pressed");
        userSilenced = true;
        setBuzzer(false);
        publishSilenceEvent();
      }
    }
  }

  lastButtonReading = reading;
}
