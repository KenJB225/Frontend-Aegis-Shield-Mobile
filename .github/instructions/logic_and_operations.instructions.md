# System Logic and Operations

## System Initialization Flow
1.  **App Launch:** Flutter app initializes and displays the Initialization screen with progress indicator.
2.  **Sensor Check:** App verifies that all physical sensors are online and responding.
3.  **Cloud Connection:** App establishes API connectivity with Next.js routes and verifies auth/session against Supabase.
4.  **Configuration Load:** App fetches device configuration, current status, and sensor readings from Next.js endpoints backed by Supabase Edge Functions.
5.  **Location Gate:** App verifies user location is configured. If missing, app routes user to Set Location before Home access.
6.  **Home Screen Ready:** Once initialized (100%) and location is set, app transitions to the Home screen.

## Dual-Layer Protection Flow

### Layer 1: Proactive Logic (Cloud/API Driven)
1.  **Deep Sleep Wake:** The ESP32 wakes up every 15 minutes.
2.  **Fetch Command:** ESP32 makes a `GET` request to the Next.js API (`/api/device/instructions`).
3.  **Backend Processing:** * Next.js route validates the request, including location coordinates.
    * Next.js invokes Supabase Edge Function logic.
    * Edge Function checks the user's `rain_threshold` from the database.
    * Edge Function fetches the OpenWeatherMap forecast for the configured user location.
    * If `Forecast % >= rain_threshold`, Next.js responds with `COMMAND: DOCK`.
4.  **Action:** ESP32 runs the stepper motor to retract the rack, updates the backend with its new status, and goes back to sleep.



### Layer 2: Reactive Failsafe (Hardware Driven)
*Note: Because the ESP32 is in Deep Sleep, the Raindrop Sensor must be wired to an RTC GPIO pin configured as an external wakeup source (EXT0).*
1.  **Hardware Interrupt:** A raindrop hits the physical sensor while the ESP32 is sleeping.
2.  **Instant Wake:** The ESP32 wakes up immediately (bypassing the 15-minute timer).
3.  **Action:** The ESP32 immediately drives the stepper motor to retract the rack into the enclosure.
4.  **Sync:** ESP32 connects to Wi-Fi, sends a `POST` to the Next.js API; the API triggers edge backend logging/state updates to 'DOCKED' with reason 'SENSOR_TRIGGER', then ESP32 returns to sleep.