# Tech Stack & Architecture

## Overview
The Aegis-Dry system utilizes a decoupled architecture, separating the client-side mobile application, the server-side API middleware, and the hardware microcontroller. 

## Frontend: Mobile Application
* **Framework:** Flutter (Dart)
* **Target Platforms:** Android & iOS
* **State Management:** Riverpod (or Provider) for handling real-time IoT state changes and UI updates.
* **Main Screens:**
    * Initialization Screen (progress tracking, sensor/cloud checks)
    * Home Screen (system status, environmental metrics, quick stats, quick actions)
    * Dashboard View (detailed device status, environmental metrics, activity log)
    * Device Control (network status, active sensors list, system health)
    * Manual Override (rack position, safety protocols, control buttons, emergency stop)
    * Alerts (notification history with timestamps and system responses)
    * Activity History Logs (searchable and filterable event log)
    * Settings (preferences, device calibration, threshold configuration, app info)
* **Responsibilities:**
    * Displaying system status (Safe/Warning/Critical) and real-time environmental metrics.
    * Displaying individual sensor readings and health indicators (battery, signal strength).
    * Providing manual override controls with safety protocol verification.
    * Allowing users to configure the precipitation threshold (0-100%).
    * Displaying activity logs and alerts in chronological order.
    * Receiving and displaying push notifications via Firebase Cloud Messaging (FCM) or Supabase.
    * Real-time updates via Supabase Realtime Database listener.

## Backend: API & Middleware
* **Framework:** Next.js (React / Node.js API Routes)
* **Hosting:** Vercel (Recommended) or standalone Node server.
* **API Endpoints:**
    * `GET /api/device/instructions` - ESP32 queries for commands based on weather threshold.
    * `GET /api/device/:deviceId/status` - Flutter app retrieves current device status.
    * `GET /api/device/:deviceId/sensors` - Flutter app retrieves sensor readings.
    * `GET /api/device/:deviceId/logs` - Flutter app retrieves activity history.
    * `PUT /api/device/:deviceId/threshold` - Flutter app updates rain probability threshold.
    * `POST /api/device/:deviceId/manual-override` - Flutter app sends manual control commands.
    * `POST /api/device/:deviceId/log` - ESP32 sends event logs and sensor data.
* **Responsibilities:**
    * Serving RESTful API endpoints for the ESP32 and Flutter App.
    * Fetching and processing data from the OpenWeatherMap API.
    * Evaluating the user-defined precipitation threshold against real-time weather data.
    * Recording and storing event logs with sensor context.
    * Managing system health status calculations based on sensor data.
    * Broadcasting real-time updates to connected Flutter clients via Supabase Realtime.
    * Handling firmware update notifications and delivery.

## Database & Authentication
* **Service:** Supabase (PostgreSQL)
* **Capabilities Used:**
    * **Auth:** Secure user registration and login.
    * **Database:** Storing user preferences, device states, and event logs.
    * **Realtime:** Broadcasting database changes to the Flutter app instantly.

## Hardware
* **Microcontroller:** ESP32 (programmed via C++/Arduino IDE).
* **Sensors/Actuators:** Raindrop Sensor, DHT22, Nema 17 Stepper Motor.