# Database Schema (Supabase / PostgreSQL)

## Overview
The Aegis-Dry system uses **Supabase** as the backend-as-a-service (BaaS) provider, leveraging PostgreSQL for data persistence. Supabase provides built-in authentication, real-time capabilities, and row-level security policies to protect user data.

**For comprehensive Supabase setup instructions**, see [supabase_setup.instructions.md](supabase_setup.instructions.md).

---

## Table: `users` (auth.users)
Managed securely by Supabase Authentication—automated and read-only from the application.
* `id` (UUID, Primary Key)
* `email` (String, Unique)
* `encrypted_password` (String, Supabase managed)
* `email_confirmed_at` (Timestamp)
* `phone` (String, nullable)
* `confirmed_at` (Timestamp)
* `last_sign_in_at` (Timestamp)
* `created_at` (Timestamp)
* `updated_at` (Timestamp)

## Table: `devices`
Stores the current state and configuration of the Aegis-Dry docking stations.
* `device_id` (UUID, Primary Key)
* `user_id` (UUID, Foreign Key -> users.id)
* `mac_address` (String, Unique)
* `status` (Enum: 'EXTENDED', 'DOCKED')
* `rain_threshold` (Integer, Default: 75) - *User adjustable via mobile app (0-100%)*
* `mode` (Enum: 'AUTO', 'MANUAL')
* `system_health_status` (Enum: 'Safe', 'Warning', 'Critical')
* `last_checked_at` (Timestamp) - *Tracks the last time system status was verified*
* `updated_at` (Timestamp)

## Table: `event_logs`
Historical data for capstone testing and user review.
* `log_id` (UUID, Primary Key)
* `device_id` (UUID, Foreign Key -> devices.device_id)
* `event_type` (Enum: 'SENSOR_TRIGGER', 'API_TRIGGER', 'MANUAL_OVERRIDE', 'SYSTEM_SELF_TEST', 'SENSOR_SYNC', 'ROUTINE_BACKUP', 'FIRMWARE_UPDATE', 'THRESHOLD_UPDATED')
* `action_taken` (String: e.g., 'Retracted', 'Extended', 'Config Updated')
* `details` (JSON: Stores additional context like sensor readings, configuration changes)
* `timestamp` (Timestamp)

## Table: `sensor_readings`
Stores real-time and historical sensor data for monitoring and analytics.
* `reading_id` (UUID, Primary Key)
* `device_id` (UUID, Foreign Key -> devices.device_id)
* `sensor_type` (Enum: 'RAIN', 'TEMPERATURE', 'HUMIDITY', 'SOIL_MOISTURE')
* `value` (Float: The actual sensor reading)
* `unit` (String: e.g., '%', '°C', '%RH')
* `battery_level` (Integer: Battery percentage of the sensor)
* `signal_strength` (Enum: 'Excellent', 'Good', 'Fair', 'Poor')
* `status` (Enum: 'Online', 'Offline', 'LinkLost')
* `timestamp` (Timestamp)

## Table: `user_profiles`
Extended user profile data linked to authentication.
* `id` (UUID, Primary Key)
* `user_id` (UUID, Foreign Key -> auth.users(id))
* `full_name` (String)
* `phone` (String, nullable)
* `company_name` (String, nullable)
* `profile_picture_url` (String, nullable)
* `role` (String: 'USER', 'SUPER_ADMIN')
* `is_active` (Boolean, Default: true)
* `created_at` (Timestamp)
* `updated_at` (Timestamp)

## Table: `activity_logs` (Admin Panel)
Audit trail for all administrative actions and user activities in the super admin panel.
* `id` (UUID, Primary Key)
* `actor_id` (UUID, Foreign Key -> auth.users(id))
* `action` (String: Describe the action taken)
* `resource_type` (String: e.g., 'USER', 'DEVICE', 'SYSTEM')
* `resource_id` (String, nullable: ID of affected resource)
* `changes` (JSONB, nullable: Store before/after changes for auditing)
* `ip_address` (String, nullable)
* `user_agent` (String, nullable)
* `created_at` (Timestamp)

---

## Row Level Security (RLS) Policies

All tables have Row Level Security enabled to ensure users can only access their own data. Refer to [supabase_setup.instructions.md](supabase_setup.instructions.md#row-level-security-rls-policies) for detailed RLS policy configuration.

### Key Policies
1. **Users** can only view and edit their own `user_profiles` and `devices`
2. **Users** can view `event_logs` and `sensor_readings` only for their devices
3. **Service Role** (Next.js + Supabase Edge backend) can insert/update logs and sensor data
4. **Super Admin** can view all `activity_logs` for auditing

---

## Realtime Subscriptions

The following tables are configured for Supabase Realtime:
- `devices` - Mobile app listens for device status updates
- `sensor_readings` - Mobile app listens for new sensor data
- `event_logs` - Mobile app listens for event log updates

See [supabase_setup.instructions.md](supabase_setup.instructions.md#realtime-configuration) for Realtime setup.

---

## Data Relationships

```
auth.users (Supabase managed)
    ├── user_profiles (1:1 relationship)
    │   └── devices (1:N relationship)
    │       ├── event_logs (1:N relationship)
    │       └── sensor_readings (1:N relationship)
    └── activity_logs (audit trail)
```

---

## Environment Variables Required

See [supabase_setup.instructions.md](supabase_setup.instructions.md#environment-variables-setup) for complete environment variable configuration.

**Minimum required for mobile app (Flutter):**
- `NEXT_PUBLIC_API_URL` (or `MOBILE_API_BASE_URL`) - Next.js API base URL
- `SUPABASE_URL` - Required when mobile uses Supabase Auth/Realtime channels
- `SUPABASE_ANON_KEY` - Required when mobile uses Supabase Auth/Realtime channels

**Minimum required for web backend (Next.js):**
- `NEXT_PUBLIC_SUPABASE_URL` - Project URL (public)
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` - Anon key (public)
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key (server-only, never expose)