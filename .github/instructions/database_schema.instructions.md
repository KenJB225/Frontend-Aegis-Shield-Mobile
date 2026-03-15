# Database Schema (Supabase / PostgreSQL)

## Table: `users`
Managed securely by Supabase Authentication.
* `id` (UUID, Primary Key)
* `email` (String)
* `created_at` (Timestamp)

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