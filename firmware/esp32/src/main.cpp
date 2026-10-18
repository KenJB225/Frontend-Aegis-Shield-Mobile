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



// Pins for the current hardware wiring.

#define RAIN_PIN 16

#define LIMIT_SWITCH_EXTEND 23 // Left limit switch / closed position

#define LIMIT_SWITCH_RETRACT 22 // Right limit switch / open position

#define STEP_PIN 26

#define DIR_PIN 14

// GPIO23 is not ADC-capable on the classic ESP32 (esp32dev).
// Move the East LDR signal to an ADC1 pin before enabling analog tracking.



#define DHTPIN 4

#define DHTTYPE DHT22

// DHT VCC is intentionally fed from GPIO5 (expansion row 5 signal pin).

// This is the "staggered hack" wiring currently used on the physical build.

const int DHT_POWER_PIN = 5;

const unsigned long DHT_POWER_DELAY_MS = 1000;



// Motor stepping config

// Auto-move stepping (non-blocking)

const uint32_t AUTO_STEP_INTERVAL_US = 2000; // lower=faster. Start conservative.

const uint32_t STEP_PULSE_US = 4;            // A4988 needs a small HIGH pulse (>= ~1us).
const uint32_t MOVEMENT_TIMEOUT_MS = 10000;
const uint8_t LIMIT_SWITCH_ACTIVE_LEVEL = LOW;



// Limit switch edge detection (single-press detection)

bool lastLimitExtendState = HIGH;  // Previous state of extend limit switch

bool lastLimitRetractState = HIGH; // Previous state of retract limit switch

// Startup initialization

enum MotorTarget {

  MOTOR_STOPPED,

  MOTOR_EXTENDING,

  MOTOR_RETRACTING

};



MotorTarget motorTarget = MOTOR_STOPPED;

bool bootRetractComplete = false;

bool manualOverrideActive = false;

bool rainActionHandled = false;

bool bootCommandCleanupPending = false;

bool wifiConnectAttempted = false;

bool timeoutRecoveryActive = false;

bool timeoutReportPending = false;

const char* lastSettledRackStatus = "RETRACTED";
const char* faultRackStatus = nullptr;
unsigned long movementStartedAt = 0;



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

  Serial.printf("LIMIT_SWITCH_EXTEND: GPIO%d\n", LIMIT_SWITCH_EXTEND);

  Serial.printf("LIMIT_SWITCH_RETRACT: GPIO%d\n", LIMIT_SWITCH_RETRACT);

  Serial.printf("STEP_PIN: GPIO%d\n", STEP_PIN);

  Serial.printf("DIR_PIN: GPIO%d\n", DIR_PIN);

  Serial.printf("DHTPIN: GPIO%d\n", DHTPIN);

  Serial.printf("DHT power via GPIO%d: %s\n", DHT_POWER_PIN, SETUP_DHT_POWER_PIN ? "enabled" : "disabled");

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

  unsigned long start = millis();

  while (WiFi.status() != WL_CONNECTED) {

    delay(500);

    Serial.print('.');

    if (millis() - start > 20000) {

      Serial.println(" WiFi connect timeout, retrying");

      start = millis();

      WiFi.disconnect();

      WiFi.begin(WIFI_SSID, WIFI_PASS);

    }

  }

  Serial.println(" connected");

}



float readTemperature() { return dht.readTemperature(); }

float readHumidity() { return dht.readHumidity(); }

bool readRain() {

  // Match your previously-working sketch: LOW means wet.

  return digitalRead(RAIN_PIN) == LOW;

}



// State-based checks (current position)

bool limitOpen() {
  return digitalRead(LIMIT_SWITCH_RETRACT) == LIMIT_SWITCH_ACTIVE_LEVEL;
}

bool limitClosed() {
  return digitalRead(LIMIT_SWITCH_EXTEND) == LIMIT_SWITCH_ACTIVE_LEVEL;
}

bool limitSwitchConflict() {
  return limitClosed() && limitOpen();
}



// Edge detection: returns true if switch just transitioned from open (HIGH) to closed (LOW)

bool checkLimitExtendEdge() {

  bool currentState = digitalRead(LIMIT_SWITCH_EXTEND);

  if (lastLimitExtendState != LIMIT_SWITCH_ACTIVE_LEVEL &&
      currentState == LIMIT_SWITCH_ACTIVE_LEVEL) {

    lastLimitExtendState = currentState;

    return true; // Transition detected (single press)

  }

  lastLimitExtendState = currentState;

  return false;

}



bool checkLimitRetractEdge() {

  bool currentState = digitalRead(LIMIT_SWITCH_RETRACT);

  if (lastLimitRetractState != LIMIT_SWITCH_ACTIVE_LEVEL &&
      currentState == LIMIT_SWITCH_ACTIVE_LEVEL) {

    lastLimitRetractState = currentState;

    return true; // Transition detected (single press)

  }

  lastLimitRetractState = currentState;

  return false;

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
  if (limitSwitchConflict()) {
    faultRackStatus = "LIMIT_SWITCH_CONFLICT";
    return;
  }
  if (faultRackStatus != nullptr) return;
  if (motorTarget != MOTOR_EXTENDING) {

    Serial.printf("[MOTOR] extend: %s\n", reason);
    movementStartedAt = millis();

  }

  motorTarget = MOTOR_EXTENDING;

}



void startRetracting(const char* reason) {
  if (limitSwitchConflict()) {
    faultRackStatus = "LIMIT_SWITCH_CONFLICT";
    return;
  }
  if (faultRackStatus != nullptr) return;
  if (motorTarget != MOTOR_RETRACTING) {

    Serial.printf("[MOTOR] retract: %s\n", reason);
    movementStartedAt = millis();

  }

  motorTarget = MOTOR_RETRACTING;

}

const char* settledRackStatusFromLimits() {
  if (limitClosed()) {
    return "EXTENDED";
  }
  if (limitOpen()) {
    return "RETRACTED";
  }
  return lastSettledRackStatus;
}

const char* rackStatusForTelemetry() {
  if (faultRackStatus != nullptr) return faultRackStatus;
  return motorTarget == MOTOR_STOPPED ? settledRackStatusFromLimits() : "MOVING";
}

void clearFault() {
  faultRackStatus = nullptr;
  timeoutRecoveryActive = false;
}

void handleMovementTimeout() {
  const bool wasExtending = motorTarget == MOTOR_EXTENDING;
  stopMotor("movement timeout");
  if (timeoutRecoveryActive) {
    timeoutRecoveryActive = false;
    faultRackStatus = "RETURN_TIMEOUT";
    timeoutReportPending = true;
    return;
  }

  timeoutRecoveryActive = true;
  if (wasExtending) {
    startRetracting("timeout return to start");
    if (motorTarget == MOTOR_RETRACTING) {
      faultRackStatus = "FAILSAFE_RETRACTING";
    }
  } else {
    startExtending("timeout return to start");
    if (motorTarget == MOTOR_EXTENDING) {
      faultRackStatus = "FAILSAFE_EXTENDING";
    }
  }
  if (motorTarget == MOTOR_STOPPED) {
    timeoutRecoveryActive = false;
  }
}
String lastRowId = "";

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

  String url = String(SUPABASE_URL) + "/rest/v1/device_status?device_id=eq." + DEVICE_ID + "&select=command,id";



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



bool pushStatusToSupabase(float temp, float hum, bool raining, const char* rackStatus) {

  if (!ENABLE_HTTP || !ENABLE_PUSH_STATUS) {

    return false;

  }

  if (WiFi.status() != WL_CONNECTED) {

    Serial.println("Skipping status push: WiFi not connected");

    return false;

  }

  if (!hasConfiguredSupabaseKey()) {

    Serial.println("Skipping status push: Supabase key is not configured");

    return false;

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

  DynamicJsonDocument doc(256);

  doc["temperature_c"] = temp;

  doc["humidity"] = hum;

  doc["is_raining"] = raining;

  doc["rack_status"] = rackStatus;

  doc["heartbeat_ms"] = millis();

  doc["obstruction_event"] = false;

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

  return code >= 200 && code < 300;

}

void clearReportedTimeoutStatus(bool statusPushed) {
  if (!statusPushed || !timeoutReportPending) return;

  timeoutReportPending = false;
  if (faultRackStatus != nullptr && String(faultRackStatus) == "RETURNED_TO_START") {
    faultRackStatus = nullptr;
  }
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

  Serial.printf("[BOOT] limit closed GPIO%d=%d, limit open GPIO%d=%d (active=%d)\n",
                LIMIT_SWITCH_EXTEND,
                lastLimitExtendState,
                LIMIT_SWITCH_RETRACT,
                lastLimitRetractState,
                LIMIT_SWITCH_ACTIVE_LEVEL);

  const bool closedLimitActiveAtBoot = limitClosed();
  const bool openLimitActiveAtBoot = limitOpen();

  if (closedLimitActiveAtBoot && openLimitActiveAtBoot) {
    faultRackStatus = "LIMIT_SWITCH_CONFLICT";
    Serial.println("[BOOT] both limit switches are active; motor movement inhibited");
  } else if (closedLimitActiveAtBoot) {
    lastSettledRackStatus = "EXTENDED";
  } else if (openLimitActiveAtBoot) {
    lastSettledRackStatus = "RETRACTED";
  }



  if (!SENSOR_TEST_MODE) {

    bootCommandCleanupPending = true;

    if (faultRackStatus == nullptr && !openLimitActiveAtBoot) {
      startRetracting("boot homing");
    } else if (openLimitActiveAtBoot && !closedLimitActiveAtBoot) {
      bootRetractComplete = true;
      Serial.println("[BOOT] retract limit is active; rack is already retracted");
    }

  }

}



unsigned long lastPush = 0;

uint32_t lastAutoStepUs = 0;

bool lastAutoDir = false;



void loop() {

  float temp = ENABLE_DHT ? readTemperature() : NAN;

  float hum = ENABLE_DHT ? readHumidity() : NAN;

  bool raining = readRain();
  if (SENSOR_TEST_MODE) {
    delay(250);
    return;
  }

  if (!raining) {
    rainActionHandled = false;
  } else if (bootRetractComplete && !rainActionHandled) {
    rainActionHandled = true;
    if (!manualOverrideActive && !limitClosed()) {
      Serial.println("[RAIN] wet locally; extending without cloud command");
      startExtending("local rain sensor");
    }
  }

  const bool motorWasMoving = motorTarget != MOTOR_STOPPED;

  const char* rackStatus = rackStatusForTelemetry();



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

      const bool statusPushed = pushStatusToSupabase(temp, hum, raining, rackStatus);
      clearReportedTimeoutStatus(statusPushed);

    }

    lastPush = millis();

  }



  if (!wifiConnectAttempted && motorTarget == MOTOR_STOPPED) {

    wifiConnectAttempted = true;

    connectWiFi();

  }



  String cmd = motorTarget != MOTOR_STOPPED ? String() : fetchCommandFromSupabase();

  if (bootCommandCleanupPending && lastRowId.length() > 0) {
    if (cmd.length() > 0) {
      Serial.printf("[BOOT] discarding pending command after homing: %s\n", cmd.c_str());
    }
    if (clearCommandOnSupabase()) {
      bootCommandCleanupPending = false;
    }
    cmd = String();
  }

  if (cmd == "CLEAR_FAULT" || cmd == "RESET_FAULT") {
    clearFault();
    clearCommandOnSupabase();
  } else if (cmd == "DEPLOY") {

    manualOverrideActive = true;

    clearFault();

    startExtending("manual DEPLOY");

    if (clearCommandOnSupabase()) {

      Serial.println("Cleared command on Supabase");

    } else {

      Serial.println("Failed to clear command on Supabase");

    }

  } else if (cmd == "RETRACT") {

    manualOverrideActive = true;

    clearFault();

    startRetracting("manual RETRACT");

    if (clearCommandOnSupabase()) {

      Serial.println("Cleared command on Supabase");

    } else {

      Serial.println("Failed to clear command on Supabase");

    }

  }



  if (motorTarget != MOTOR_STOPPED && limitSwitchConflict()) {
    faultRackStatus = "LIMIT_SWITCH_CONFLICT";
    stopMotor("both limit switches active");
  }

  if (motorTarget == MOTOR_EXTENDING) {

    if (limitClosed() || checkLimitExtendEdge()) {

      if (timeoutRecoveryActive) {
        lastSettledRackStatus = "EXTENDED";
        timeoutRecoveryActive = false;
        faultRackStatus = "RETURNED_TO_START";
        timeoutReportPending = true;
        stopMotor("timeout return reached starting extend limit");
      } else {
        lastSettledRackStatus = "EXTENDED";
        stopMotor("extend limit clicked");
      }
      manualOverrideActive = false;

    } else if (millis() - movementStartedAt >= MOVEMENT_TIMEOUT_MS) {
      handleMovementTimeout();

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

      }

    }

  } else if (motorTarget == MOTOR_RETRACTING) {

    if (limitOpen() || checkLimitRetractEdge()) {

      bootRetractComplete = true;

      if (timeoutRecoveryActive) {
        lastSettledRackStatus = "RETRACTED";
        timeoutRecoveryActive = false;
        faultRackStatus = "RETURNED_TO_START";
        timeoutReportPending = true;
        stopMotor("timeout return reached starting retract limit");
      } else {
        lastSettledRackStatus = "RETRACTED";
        stopMotor("retract limit clicked");
      }
      manualOverrideActive = false;

    } else if (millis() - movementStartedAt >= MOVEMENT_TIMEOUT_MS) {
      handleMovementTimeout();
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

      }

    }

  }

  if (motorWasMoving && motorTarget == MOTOR_STOPPED) {

    const bool statusPushed = pushStatusToSupabase(temp, hum, raining, rackStatusForTelemetry());
    clearReportedTimeoutStatus(statusPushed);

    lastPush = millis();

  }



  // Small yield to keep the loop responsive.

  delay(2);

}
