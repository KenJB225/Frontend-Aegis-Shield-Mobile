# Tech Stack & Architecture

## Overview
The Aegis-Dry system utilizes a decoupled architecture: the Flutter mobile app connects directly to Supabase, while Next.js API middleware handles web superadmin and device/server workflows.

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

### Architecture
The backend is a **Next.js application** with API Routes that act as middleware for the web superadmin panel and device/server workflows against Supabase. It handles:
- Device communication and command processing
- Weather forecast evaluation and decision logic
- Data aggregation and transformation
- Admin operations and audit logging
- Real-time event broadcasting

### Technology Stack
* **Framework:** Next.js (v13+ with App Router)
* **Runtime:** Node.js (v16+)
* **Language:** TypeScript (recommended) or JavaScript
* **Database Client:** @supabase/supabase-js
* **External APIs:** OpenWeatherMap API
* **Deployment:** Vercel (native Next.js hosting, recommended) or self-hosted Node.js
* **Authentication:** Supabase Auth + JWT tokens
* **CORS:** Enabled for web dashboard and device clients that access API routes

### Project Structure
```
aegis-dry-backend/
├── src/app/
│   ├── layout.tsx
│   ├── page.tsx
│   └── api/
│       ├── health/route.ts              # Health check endpoint
│       ├── device/
│       │   ├── instructions/route.ts    # ESP32 command endpoint
│       │   └── [deviceId]/
│       │       ├── status/route.ts
│       │       ├── sensors/route.ts
│       │       ├── logs/route.ts
│       │       ├── threshold/route.ts
│       │       └── manual-override/route.ts
│       ├── sensor/
│       │   └── [deviceId]/
│       │       ├── latest/route.ts
│       │       └── history/route.ts
│       └── admin/
│           ├── users/route.ts
│           ├── activity-logs/route.ts
│           └── dashboard/route.ts
├── lib/
│   ├── supabase/
│   │   └── client.ts                    # Supabase client initialization
│   ├── middleware/
│   │   ├── auth.ts                      # JWT verification
│   │   └── errorHandler.ts              # Error handling utilities
│   └── services/
│       ├── deviceService.ts             # Device business logic
│       ├── weatherService.ts            # OpenWeatherMap integration
│       └── auditService.ts              # Audit logging
├── types/
│   └── index.ts                         # TypeScript types/interfaces
├── .env.local                           # Environment variables (not committed)
├── .env.example                         # Example env template
├── next.config.js                       # Next.js configuration
├── tsconfig.json                        # TypeScript configuration
├── package.json
└── README.md
```

### API Endpoints

#### Device Endpoints

**GET /api/device/instructions**
- **Purpose:** ESP32 queries for commands based on weather threshold
- **Request:** Device ID (from header or query)
- **Response:** `{ command: 'DOCK' | 'EXTEND', reason: string, threshold: number }`
- **Called By:** ESP32 (every 15 minutes)

**GET /api/device/:deviceId/status**
- **Purpose:** Retrieve current device state for admin monitoring and integrations
- **Response:** `{ status: 'DOCKED' | 'EXTENDED', health: 'Safe' | 'Warning' | 'Critical', mode: 'AUTO' | 'MANUAL' }`
- **Called By:** Web dashboard

**GET /api/device/:deviceId/sensors**
- **Purpose:** Retrieve latest sensor readings
- **Response:** `[ { sensorType: string, value: number, unit: string, timestamp: date, status: string } ]`
- **Called By:** Web dashboard

**GET /api/device/:deviceId/logs**
- **Purpose:** Retrieve activity/event logs with pagination
- **Query Params:** `page=1&limit=50&filter=SENSOR_TRIGGER`
- **Response:** `{ logs: [], total: number, page: number }`
- **Called By:** Web dashboard

**PUT /api/device/:deviceId/threshold**
- **Purpose:** Update rain probability threshold (0-100%)
- **Body:** `{ rain_threshold: number }`
- **Response:** `{ success: true, updated_at: date }`
- **Called By:** Web dashboard or internal admin tooling

**POST /api/device/:deviceId/manual-override**
- **Purpose:** Send manual control commands
- **Body:** `{ action: 'DOCK' | 'EXTEND', reason: string }`
- **Response:** `{ success: true, command_id: uuid }`
- **Called By:** Web dashboard or internal admin tooling

**POST /api/device/:deviceId/log**
- **Purpose:** ESP32 sends event logs and sensor data
- **Body:** `{ event_type: string, action_taken: string, details: object, sensors: array }`
- **Response:** `{ logged: true, log_id: uuid }`
- **Called By:** ESP32

#### Sensor Endpoints

**GET /api/sensor/:deviceId/latest**
- **Purpose:** Get latest readings from all sensors
- **Response:** `{ rain: number, temperature: number, humidity: number, soilMoisture: number, battery: number, signal: string }`
- **Called By:** Web dashboard

**GET /api/sensor/:deviceId/history**
- **Purpose:** Get historical sensor data for charts/analytics
- **Query Params:** `sensorType=RAIN&days=7`
- **Response:** `[ { timestamp: date, value: number, unit: string } ]`
- **Called By:** Web dashboard

#### Admin Panel Endpoints

**GET /api/admin/users**
- **Purpose:** List all users with pagination and filters
- **Query Params:** `page=1&limit=20&status=ACTIVE&search=email`
- **Response:** `{ users: array, total: number, page: number }`
- **Auth:** Super Admin only

**GET /api/admin/users/:userId**
- **Purpose:** Get detailed user information
- **Response:** `{ id, email, fullName, status, createdAt, devices: [...] }`
- **Auth:** Super Admin only

**PUT /api/admin/users/:userId/status**
- **Purpose:** Enable/disable user account
- **Body:** `{ is_active: boolean }`
- **Response:** `{ success: true, updated_at: date }`
- **Auth:** Super Admin only

**GET /api/admin/activity-logs**
- **Purpose:** Retrieve audit logs with filters
- **Query Params:** `page=1&limit=50&actor=userId&resource=DEVICE`
- **Response:** `{ logs: array, total: number }`
- **Auth:** Super Admin only

**GET /api/admin/dashboard/stats**
- **Purpose:** Dashboard summary statistics
- **Response:** `{ totalUsers: number, activeUsers: number, inactiveUsers: number, totalDevices: number, criticalAlerts: number }`
- **Auth:** Super Admin only

### Core Responsibilities

1. **Weather Integration**
   - Fetch forecasts from OpenWeatherMap API
   - Evaluate rain probability vs user threshold
   - Send DOCK/EXTEND commands to devices

2. **Device Management**
   - Track device status and health
   - Store configuration (thresholds, modes)
   - Handle manual overrides safely

3. **Data Aggregation**
   - Collect sensor readings from ESP32
   - Store event logs with context
   - Calculate system health status

4. **Real-time Broadcasting**
   - Publish data changes for web/admin consumers and integrations
   - Notify dashboard of critical events
   - Maintain connection state

5. **Admin Operations**
   - User and device management
   - Activity audit logging
   - System health monitoring

6. **Authentication & Security**
   - Verify JWT tokens from requests
   - Enforce row-level access control
   - Log sensitive operations

## Database & Authentication
* **Service:** Supabase (PostgreSQL)
* **Capabilities Used:**
    * **Auth:** Secure user registration and login via email or OAuth.
    * **Database:** Storing user profiles, device states, event logs, and sensor readings.
    * **Realtime:** Broadcasting database changes to mobile app instantly.
    * **Row Level Security:** Ensuring users access only their own data.
* **Setup Guide:** See [supabase_setup.instructions.md](supabase_setup.instructions.md)

### API Keys & Access
- **Anon Key:** For client-side access (mobile app) - subject to RLS policies
- **Service Role Key:** For backend server only (Next.js) - bypasses RLS
- Never expose Service Role Key in client-side code

## Frontend: Web Superadmin Panel
* **Framework:** React (with Vite or Next.js)
* **Target Platform:** Desktop browsers (Chrome, Firefox, Safari, Edge)
* **State Management:** Context API / Redux Toolkit
* **UI Library:** Material-UI or React Bootstrap
* **HTTP Client:** Fetch API or Axios
* **Authentication:** Supabase Auth + JWT tokens
* **Main Pages:**
    * **Login Page** - Super admin authentication
    * **Dashboard** - System overview with key metrics and recent activity
    * **Users Management** - View, search, filter, enable/disable user accounts
    * **Activity Logs** - Audit trail of all system actions for compliance
    * **Settings** - Theme preferences, admin profile, system info
* **Responsibilities:**
    * Authenticating super admin users securely
    * Displaying system-wide metrics and user statistics
    * Managing user accounts (enable/disable, view details)
    * Viewing and auditing activity logs for compliance
    * Providing system configuration and settings
    * Enforcing role-based access control
* **Backend Integration:** Communicates exclusively with Next.js backend via REST API endpoints (see Admin Panel Endpoints above)

## Hardware
* **Microcontroller:** ESP32 (programmed via C++/Arduino IDE).
* **Sensors/Actuators:** Raindrop Sensor, DHT22, Nema 17 Stepper Motor.
