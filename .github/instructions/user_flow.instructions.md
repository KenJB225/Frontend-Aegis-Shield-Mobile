# Mobile App User Flow

## 1. System Initialization
1.  User opens the Flutter app after launching Aegis-Dry for the first time.
2.  Initialization screen displays with progress bar (0-100%).
3.  System checks: "SENSORS ONLINE" and "CLOUD LINKED" status indicators.
4.  Once initialization is complete, app transitions to Home screen.

## 2. Onboarding & Authentication
1.  User registers or logs in via Supabase Auth (if not already authenticated).
2.  User connects a new Aegis-Dry device by inputting the ESP32's unique Device ID or MAC Address.

## 3. Home Screen
1.  **System Status Card:** Displays current system state (e.g., "Safe" with security percentage, "Last checked: 2 minutes ago").
2.  **Environmental Metrics:** Real-time display of:
     * Temperature (e.g., 72°F)
     * Current weather condition (e.g., Clear)
     * Local forecast data
3.  **Quick Stats:** Shows current humidity and air quality readings.
4.  **Quick Actions:** 
     * "Open Dashboard" button (navigates to detailed device view).
     * "Manual Control" option (navigates to manual override screen).

## 4. Dashboard View
1.  **Device Status Section:** Current system status and last check timestamp.
2.  **Environmental Metrics:** Temperature, humidity percentage, and rain probability.
3.  **Activity Log:** Recent system events (Self-Test, Sensor Sync, Backups) with timestamps.

## 5. Device Control
1.  **Network Status:** Shows online/offline status and number of active sensors.
2.  **Active Sensors Panel:** Lists each sensor with current readings:
     * Rain Sensor (% Dry)
     * Temperature Sensor (°C or °F)
     * Humidity Sensor (% RH)
     * Soil Moisture Sensor (status and last sync)
3.  **System Health:** Battery percentage and signal strength indicators.

## 6. Manual Override
1.  User navigates to the Manual Override screen.
2.  **System Status Alert:** Displays current rack position (e.g., "50% Extended" or "Retracted").
3.  **Safety Protocols:** Lists active safety checks (e.g., "Clear area of obstacles", "Verify weight limit", "Stable power connection").
4.  **Control Buttons:**
     * "Extend Rack" button (teal/green).
     * "Retract Rack" button (blue).
     * "EMERGENCY STOP" button (red) - Disengages all hydraulic power immediately.
5.  If system is moving, displays "SYSTEM MOVING..." with progress percentage.

## 7. Alerts Section
1.  User navigates to the Alerts view.
2.  Displays all system notifications and alerts in chronological order (Today, Yesterday, etc.):
     * "Rain detected — rack automatically retracted"
     * "Rack successfully extended"
     * "High rain probability detected"
     * "System Firmware Updated"
3.  Each alert shows timestamp and can be marked as read.

## 8. Activity History
1.  User navigates to Activity History Logs.
2.  **Search & Filter:** Search by log text or filter by type (All, Sensors, System, Manual).
3.  **Log Entries:** Each entry shows:
     * Event icon (sensor trigger, manual action, system event, etc.)
     * Event description
     * Timestamp
     * System response (if applicable)

## 9. Settings & Configuration
1.  User navigates to Settings.
2.  **Preferences:** Dark mode toggle, notification settings (Push Notifications, Email Alerts).
3.  **Device Calibration:**
     * Sensor Calibration: Adjust humidity and temperature offsets.
     * Threshold Configuration: Access the main settings panel.
4.  **Threshold Configuration Panel:**
     * Displays instructions: "Set the rain probability at which the laundry rack should automatically retract to protect your clothes."
     * **Rain Probability Threshold:** Slider set to a default value (e.g., 75%).
     * **Current Local Forecast:** Shows the current rain probability from the local forecast (e.g., "Rain probability for the next 2 hours is 12%").
     * "Save Settings" button sends a `PUT` request to the Next.js API to update the `devices.rain_threshold` field in Supabase.
5.  **Application Info:** App version, About section, Sign Out button.

## 10. Automated Notification Flow
1.  ESP32 detects rain via the raindrop sensor OR Next.js backend detects API threshold met.
2.  Database `status` updates to 'DOCKED'.
3.  Supabase triggers a notification payload to the user.
4.  Notification appears in the Alerts section with timestamp and system response details.