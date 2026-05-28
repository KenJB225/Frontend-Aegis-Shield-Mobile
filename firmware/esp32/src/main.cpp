/*
  ESP32 Firmware Example (PlatformIO / Arduino)
  - Reads DHT22, rain sensor, limit switches
  - Pushes status to Supabase REST endpoints
  - Polls Supabase for commands and runs stepper via A4988

  IMPORTANT: Replace placeholders for WiFi and Supabase settings.
*/

#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <ArduinoJson.h>
#include <math.h>

// === Configure these via platformio.ini build_flags ===
#ifndef WIFI_SSID_VALUE
#define WIFI_SSID_VALUE "YOUR_SSID"
#endif

#ifndef WIFI_PASS_VALUE
#define WIFI_PASS_VALUE "YOUR_WIFI_PASS"
#endif

#ifndef SUPABASE_URL_VALUE
#define SUPABASE_URL_VALUE "https://gxztdpxeuxshvnolpvdr.supabase.co"
#endif

#ifndef SUPABASE_ANON_KEY_VALUE
#define SUPABASE_ANON_KEY_VALUE "YOUR_SUPABASE_ANON_KEY"
#endif

const char* WIFI_SSID = WIFI_SSID_VALUE;
const char* WIFI_PASS = WIFI_PASS_VALUE;
const char* SUPABASE_URL = SUPABASE_URL_VALUE;
// Use a minimal key allowed by your RLS policies. Avoid embedding service_role in firmware when possible.
const char* SUPABASE_ANON_KEY = SUPABASE_ANON_KEY_VALUE;
const char* DEVICE_ID = "ESP32_RACK_01";
const char* DEVICE_ROW_ID = ""; // optional: uuid of the device_status row

// Set true when validating sensors on a breadboard. Disables HTTP + motor actions.
const bool SENSOR_TEST_MODE = false;

const bool ENABLE_HTTP = !SENSOR_TEST_MODE;
const bool ENABLE_FETCH_COMMAND = !SENSOR_TEST_MODE;
const bool ENABLE_PUSH_STATUS = !SENSOR_TEST_MODE;
const bool ENABLE_CLEAR_COMMAND = !SENSOR_TEST_MODE;
const bool ENABLE_PIN_SETUP = true;
const bool ENABLE_DHT = true;
const bool SETUP_DHT_POWER_PIN = true;
const bool SETUP_RAIN_PIN = true;
const bool SETUP_LIMIT_EXTEND_PIN = true;
const bool SETUP_LIMIT_RETRACT_PIN = true;
const bool SETUP_STEP_PIN = true;
const bool SETUP_DIR_PIN = true;

// Pins (updated expansion-board + breadboard wiring layout)
#define RAIN_PIN 18
#define LIMIT_SWITCH_EXTEND 23
#define LIMIT_SWITCH_RETRACT 22
#define STEP_PIN 26
#define DIR_PIN 14

#define DHTPIN 21
#define DHTTYPE DHT22
// DHT VCC is intentionally fed from GPIO5 (expansion row 5 signal pin).
// This is the "staggered hack" wiring currently used on the physical build.
const int DHT_POWER_PIN = 5;
const unsigned long DHT_POWER_DELAY_MS = 1000;

// Motor stepping config
const int STEP_DELAY_US = 800; // legacy: used by blocking moveToOpen/moveToClosed
const long MAX_STEPS_PER_MOVE = 5000; // legacy: safety cap for blocking moves

// Auto-move stepping (non-blocking)
const uint32_t AUTO_STEP_INTERVAL_US = 2000; // lower=faster. Start conservative.
const uint32_t STEP_PULSE_US = 4;            // A4988 needs a small HIGH pulse (>= ~1us).
const unsigned long COMMAND_POLL_INTERVAL_MS = 750;         // A4988 needs a small HIGH pulse (>= ~1us).

// Limit switch edge detection (single-press detection)
bool lastLimitExtendState = HIGH;  // Previous state of extend limit switch
bool lastLimitRetractState = HIGH; // Previous state of retract limit switch
bool limitExtendPressed = false;   // Triggered when extend limit transitions HIGH->LOW
bool limitRetractPressed = false;  // Triggered when retract limit transitions HIGH->LOW

// Startup initialization
enum MotorTarget {
  MOTOR_STOPPED,
  MOTOR_EXTENDING,
  MOTOR_RETRACTING
};

MotorTarget motorTarget = MOTOR_STOPPED;
bool bootRetractComplete = false;
bool manualOverrideActive = false;
bool wifiConnectAttempted = false;

DHT dht(DHTPIN, DHTTYPE);

void logHeap(const char* label) {
  Serial.printf("[HEAP] %s free=%u min=%u maxAlloc=%u\n",
                label,
                ESP.getFreeHeap(),
                ESP.getMinFreeHeap(),
                ESP.getMaxAllocHeap());
}

bool hasConfiguredWifi() {
  return String(WIFI_SSID) != "YOUR_SSID" && String(WIFI_PASS) != "YOUR_WIFI_PASS";
}

bool hasConfiguredSupabaseKey() {
  return String(SUPABASE_ANON_KEY) != "YOUR_SUPABASE_ANON_KEY";
}

void printConfigSummary() {
  Serial.println("=== CONFIG SUMMARY ===");
  Serial.printf("WiFi configured: %s\n", hasConfiguredWifi() ? "yes" : "no");
  Serial.printf("Supabase key configured: %s\n", hasConfiguredSupabaseKey() ? "yes" : "no");
  Serial.printf("Device ID: %s\n", DEVICE_ID);
  Serial.printf("Sensor test mode: %s\n", SENSOR_TEST_MODE ? "ON" : "OFF");
  Serial.printf("RAIN_PIN: GPIO%d\n", RAIN_PIN);
  Serial.printf("DHTPIN: GPIO%d\n", DHTPIN);
  Serial.printf("DHT power via GPIO%d: %s\n", DHT_POWER_PIN, SETUP_DHT_POWER_PIN ? "enabled" : "disabled");
}

void connectWiFi() {
  if (!hasConfiguredWifi()) {
    Serial.println("WiFi credentials are still placeholders; firmware cannot reach the database yet.");
    return;
  }

void connectWiFi() {
  if (!hasConfiguredWifi()) {
    Serial.println("WiFi credentials are still placeholders; firmware cannot reach the database yet.");
    return;
  }

  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true);
  delay(250);
  Serial.println("[WiFi] scanning nearby networks...");
  int networkCount = WiFi.scanNetworks();
  bool targetFound = false;
  for (int i = 0; i < networkCount; i++) {
    String foundSsid = WiFi.SSID(i);
    if (foundSsid == WIFI_SSID) {
      targetFound = true;
      Serial.printf("[WiFi] found %s RSSI=%d channel=%d\n", foundSsid.c_str(), WiFi.RSSI(i), WiFi.channel(i));
    }
  }
  if (!targetFound) {
    Serial.printf("[WiFi] SSID not visible to ESP32: %s\n", WIFI_SSID);
    Serial.println("[WiFi] ESP32 only supports 2.4GHz WiFi; check router/AP band settings.");
  }

  Serial.print("Connecting to WiFi...");
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.println(" connected");
}

float readTemperature() { return dht.readTemperature(); }
float readHumidity() { return dht.readHumidity(); }
bool readRain() {
  // Match your previously-working sketch: LOW means wet.
  return digitalRead(RAIN_PIN) == LOW;
}

// State-based checks (current position)
bool limitOpen() { return digitalRead(LIMIT_SWITCH_RETRACT) == LOW; }
bool limitClosed() { return digitalRead(LIMIT_SWITCH_EXTEND) == LOW; }

// Edge detection: returns true if switch just transitioned from open (HIGH) to closed (LOW)
bool checkLimitExtendEdge() {
  bool currentState = digitalRead(LIMIT_SWITCH_EXTEND);
  if (lastLimitExtendState == HIGH && currentState == LOW) {
    lastLimitExtendState = currentState;
    return true; // Transition detected (single press)
  }
  lastLimitExtendState = currentState;
  return false;
}

bool checkLimitRetractEdge() {
  bool currentState = digitalRead(LIMIT_SWITCH_RETRACT);
  if (lastLimitRetractState == HIGH && currentState == LOW) {
    lastLimitRetractState = currentState;
    return true; // Transition detected (single press)
  }
  lastLimitRetractState = currentState;
  return false;
}

void stepOnce(bool dir) {
  digitalWrite(DIR_PIN, dir ? HIGH : LOW);
  digitalWrite(STEP_PIN, HIGH);
  delayMicroseconds(STEP_DELAY_US);
  digitalWrite(STEP_PIN, LOW);
  delayMicroseconds(STEP_DELAY_US);
}

void stepPulse() {
  digitalWrite(STEP_PIN, HIGH);
  delayMicroseconds(STEP_PULSE_US);
  digitalWrite(STEP_PIN, LOW);
}

void stopMotor(const char* reason) {
  if (motorTarget != MOTOR_STOPPED) {
    Serial.printf("[MOTOR] stop: %s\n", reason);
  }
  motorTarget = MOTOR_STOPPED;
}

void startExtending(const char* reason) {
  if (limitClosed()) {
    stopMotor("extend limit already pressed");
    return;
  }
  if (motorTarget != MOTOR_EXTENDING) {
    Serial.printf("[MOTOR] extend: %s\n", reason);
  }
  motorTarget = MOTOR_EXTENDING;
}

void startRetracting(const char* reason) {
  if (limitOpen()) {
    stopMotor("retract limit already pressed");
    bootRetractComplete = true;
    return;
  }
  if (motorTarget != MOTOR_RETRACTING) {
    Serial.printf("[MOTOR] retract: %s\n", reason);
  }
  motorTarget = MOTOR_RETRACTING;
}

void moveToClosed() {
  Serial.println("Moving to CLOSED until extend limit switch triggers (single press)");
  long steps = 0;
  // Reset edge detection so we don't immediately detect a previous press
  checkLimitExtendEdge(); // Clear any pending transition
  while (steps < MAX_STEPS_PER_MOVE) {
    if (checkLimitExtendEdge()) {
      Serial.println("Closed position reached (extend limit edge detected)");
      return; // Exit immediately on edge detection
    }
    stepOnce(false); // direction depends on wiring; test carefully
    delay(2);
    steps++;
  }
  Serial.println("Closed move timed out; check motor wiring or the extend limit switch");
}

void moveToOpen() {
  Serial.println("Moving to OPEN until retract limit switch triggers (single press)");
  long steps = 0;
  // Reset edge detection so we don't immediately detect a previous press
  checkLimitRetractEdge(); // Clear any pending transition
  while (steps < MAX_STEPS_PER_MOVE) {
    if (checkLimitRetractEdge()) {
      Serial.println("Open position reached (retract limit edge detected)");
      return; // Exit immediately on edge detection
    }
    stepOnce(true);
    delay(2);
    steps++;
  }
  Serial.println("Open move timed out; check motor wiring or the retract limit switch");
}

String lastRowId = "";
bool lastAutoMode = true;

String fetchCommandFromSupabase() {
  if (!ENABLE_HTTP || !ENABLE_FETCH_COMMAND) {
    return String();
  }
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Skipping command fetch: WiFi not connected");
    return String();
  }
  if (!hasConfiguredSupabaseKey()) {
    Serial.println("Skipping command fetch: Supabase key is not configured");
    return String();
  }
  Serial.println("[HTTP] fetch command begin");
  logHeap("fetch begin");
  HTTPClient http;
  String url = String(SUPABASE_URL) + "/rest/v1/device_status?device_id=eq." + DEVICE_ID + "&select=command,is_auto_mode,id";

  // Retry loop for transient failures
  const int maxRetries = 3;
  for (int attempt = 0; attempt < maxRetries; ++attempt) {
    http.begin(url);
    http.setTimeout(5000);
    http.addHeader("apikey", SUPABASE_ANON_KEY);
    http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
    int code = http.GET();
    if (code == 200) {
      String body = http.getString();
      if (body == "[]") {
        Serial.println("[HTTP] fetch empty: device_id not found");
      }
      Serial.printf("[HTTP] fetch ok code=%d bytes=%d\n", code, body.length());
      // Keep JSON buffer modest to avoid heap pressure on ESP32
      DynamicJsonDocument doc(1024);
      DeserializationError err = deserializeJson(doc, body);
      if (!err && doc.size() > 0) {
        JsonObject row = doc[0];
        const char* cmdC = row["command"];
        lastAutoMode = row["is_auto_mode"] | true;
        const char* idC = row["id"];
        if (idC) lastRowId = String(idC);
        if (cmdC) {
          String cmd = String(cmdC);
          http.end();
          return cmd;
        }
      }
      http.end();
      return String();
    }
    Serial.printf("Command fetch HTTP %d\n", code);
    Serial.printf("[HTTP] fetch error code=%d\n", code);
    http.end();
    delay(500 * (attempt + 1));
  }
  logHeap("fetch end");
  return String();
}

bool clearCommandOnSupabase() {
  if (!ENABLE_HTTP || !ENABLE_CLEAR_COMMAND) {
    return false;
  }
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Skipping command clear: WiFi not connected");
    return false;
  }
  if (lastRowId.length() == 0) return false;
  if (!hasConfiguredSupabaseKey()) {
    Serial.println("Skipping command clear: Supabase key is not configured");
    return false;
  }
  Serial.println("[HTTP] clear command begin");
  logHeap("clear begin");
  HTTPClient http;
  String url = String(SUPABASE_URL) + "/rest/v1/device_status?id=eq." + lastRowId;
  // Send an explicit JSON body to set command to null to avoid ArduinoJson heap churn
  String body = "{\"command\":null}";

  const int maxRetries = 3;
  for (int attempt = 0; attempt < maxRetries; ++attempt) {
    http.begin(url);
    http.setTimeout(5000);
    http.addHeader("apikey", SUPABASE_ANON_KEY);
    http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
    http.addHeader("Content-Type", "application/json");
    int code = http.PATCH(body);
    if (code >= 200 && code < 300) {
      Serial.printf("[HTTP] clear ok code=%d\n", code);
      http.end();
      return true;
    }
    Serial.printf("Command clear HTTP %d\n", code);
    Serial.printf("[HTTP] clear error code=%d\n", code);
    http.end();
    delay(400 * (attempt + 1));
  }
  logHeap("clear end");
  return false;
}

void pushStatusToSupabase(float temp, float hum, bool raining, const char* rackStatus) {
  if (!ENABLE_HTTP || !ENABLE_PUSH_STATUS) {
    return;
  }
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Skipping status push: WiFi not connected");
    return;
  }
  if (!hasConfiguredSupabaseKey()) {
    Serial.println("Skipping status push: Supabase key is not configured");
    return;
  }
  Serial.println("[HTTP] push status begin");
  logHeap("push begin");
  HTTPClient http;
  String url = String(SUPABASE_URL) + "/rest/v1/device_status?device_id=eq." + DEVICE_ID;
  http.begin(url);
  http.addHeader("apikey", SUPABASE_ANON_KEY);
  http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Prefer", "return=representation");

  // Keep JSON payload small and avoid sending client-side timestamps
  DynamicJsonDocument doc(192);
  doc["temperature_c"] = temp;
  doc["humidity"] = hum;
  doc["is_raining"] = raining;
  doc["rack_status"] = rackStatus;
  String body;
  serializeJson(doc, body);
  http.setTimeout(5000);
  int code = http.PATCH(body);
  String response = http.getString();
  if (code >= 200 && code < 300) {
    Serial.println("Status updated");
  } else {
    Serial.print("Status update failed: "); Serial.println(code);
  }
  Serial.printf("[HTTP] push done code=%d bytes=%d\n", code, response.length());
  if (response.length() == 0) {
    Serial.println("[HTTP] push empty response; check device_id or RLS");
  }
  logHeap("push end");
  http.end();
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("[BOOT] setup start");
  logHeap("setup start");
  Serial.printf("[BOOT] sensor test mode: %s\n", SENSOR_TEST_MODE ? "ON" : "OFF");
  if (ENABLE_PIN_SETUP) {
    if (SETUP_DHT_POWER_PIN && DHT_POWER_PIN >= 0) {
      pinMode(DHT_POWER_PIN, OUTPUT);
      // Keep it simple: provide steady VCC before dht.begin().
      digitalWrite(DHT_POWER_PIN, HIGH);
      delay(DHT_POWER_DELAY_MS);
    }
    if (SETUP_RAIN_PIN) {
      // Many LM393-based rain modules have an open-collector D0 output.
      // INPUT_PULLUP prevents a floating input when D0 is disconnected.
      pinMode(RAIN_PIN, INPUT_PULLUP);
    }
    if (SETUP_LIMIT_EXTEND_PIN) {
      pinMode(LIMIT_SWITCH_EXTEND, INPUT_PULLUP);
    }
    if (SETUP_LIMIT_RETRACT_PIN) {
      pinMode(LIMIT_SWITCH_RETRACT, INPUT_PULLUP);
    }
    if (SETUP_STEP_PIN) {
      pinMode(STEP_PIN, OUTPUT);
    }
    if (SETUP_DIR_PIN) {
      pinMode(DIR_PIN, OUTPUT);
    }
  } else {
    Serial.println("[BOOT] pin setup disabled");
  }
  if (ENABLE_DHT) {
    dht.begin();
    if (SETUP_DHT_POWER_PIN) {
      Serial.printf("[BOOT] DHT22 enabled on GPIO%d, VCC sourced from GPIO%d\n", DHTPIN, DHT_POWER_PIN);
    } else {
      Serial.printf("[BOOT] DHT22 enabled on GPIO%d with direct 3.3V power\n", DHTPIN);
    }
  } else {
    Serial.println("[BOOT] DHT disabled");
  }
  printConfigSummary();

  lastLimitExtendState = digitalRead(LIMIT_SWITCH_EXTEND);
  lastLimitRetractState = digitalRead(LIMIT_SWITCH_RETRACT);

  if (!SENSOR_TEST_MODE) {
    startRetracting("boot homing");
  }
}

unsigned long lastPush = 0;
unsigned long lastAutoMoveMs = 0;
uint32_t lastAutoStepUs = 0;
bool lastAutoDir = false;

void loop() {
  float temp = ENABLE_DHT ? readTemperature() : NAN;
  float hum = ENABLE_DHT ? readHumidity() : NAN;
  bool raining = readRain();
  const char* rackStatus = limitClosed() ? "CLOSED" : (limitOpen() ? "OPEN" : "MOVING");

  const bool motorIsMoving = motorTarget != MOTOR_STOPPED;

  if (millis() - lastPush > 8000) {
    if (ENABLE_DHT) {
      if (isnan(temp) || isnan(hum)) {
        Serial.println("[DHT] read failed");
      } else {
        Serial.printf("[DHT] temp=%.1fC hum=%.1f%%\n", temp, hum);
      }
    }
    Serial.printf("[RAIN] wet=%s raw=%d rack=%s\n", raining ? "YES" : "NO", digitalRead(RAIN_PIN), rackStatus);
    // Avoid pausing the stepper mid-move due to blocking network calls.
    if (!motorIsMoving) {
      pushStatusToSupabase(temp, hum, raining, rackStatus);
    }
    lastPush = millis();
  }

  if (SENSOR_TEST_MODE) {
    delay(250);
    return;
  }

  if (!wifiConnectAttempted && motorTarget == MOTOR_STOPPED) {
    wifiConnectAttempted = true;
    connectWiFi();
  }

  if (lastAutoMode && raining) {
    manualOverrideActive = false;
    startExtending("rain detected");
  }

  String cmd = motorTarget != MOTOR_STOPPED ? String() : fetchCommandFromSupabase();
  if (cmd == "DEPLOY") {
    manualOverrideActive = true;
    startExtending("manual DEPLOY");
    if (clearCommandOnSupabase()) {
      Serial.println("Cleared command on Supabase");
    } else {
      Serial.println("Failed to clear command on Supabase");
    }
  } else if (cmd == "RETRACT") {
    manualOverrideActive = true;
    startRetracting("manual RETRACT");
    if (clearCommandOnSupabase()) {
      Serial.println("Cleared command on Supabase");
    } else {
      Serial.println("Failed to clear command on Supabase");
    }
  }

  if (motorTarget == MOTOR_EXTENDING) {
    if (limitClosed() || checkLimitExtendEdge()) {
      stopMotor("extend limit clicked");
    } else {
      const bool dirForExtend = false;
      if (lastAutoDir != dirForExtend) {
        digitalWrite(DIR_PIN, dirForExtend ? HIGH : LOW);
        lastAutoDir = dirForExtend;
      }
      const uint32_t nowUs = micros();
      if ((uint32_t)(nowUs - lastAutoStepUs) >= AUTO_STEP_INTERVAL_US) {
        lastAutoStepUs = nowUs;
        stepPulse();
        lastAutoMoveMs = millis();
      }
    }
  } else if (motorTarget == MOTOR_RETRACTING) {
    if (limitOpen() || checkLimitRetractEdge()) {
      bootRetractComplete = true;
      stopMotor("retract limit clicked");
    } else {
      const bool dirForRetract = true;
      if (lastAutoDir != dirForRetract) {
        digitalWrite(DIR_PIN, dirForRetract ? HIGH : LOW);
        lastAutoDir = dirForRetract;
      }
      const uint32_t nowUs = micros();
      if ((uint32_t)(nowUs - lastAutoStepUs) >= AUTO_STEP_INTERVAL_US) {
        lastAutoStepUs = nowUs;
        stepPulse();
        lastAutoMoveMs = millis();
      }
    }
  }

  // Small yield to keep the loop responsive.
  delay(2);
}
