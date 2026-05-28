-- Migration: Add unique index on device_id and seed device row
-- Path: supabase/migrations/002_add_device_id_unique_and_seed.sql

-- Create a unique index on device_id so ON CONFLICT works safely
create unique index if not exists device_status_device_id_idx on device_status (device_id);

-- Seed a default device row (will do nothing if device_id already exists)
insert into device_status (device_id, rack_status, is_auto_mode)
values ('ESP32_RACK_01', 'CLOSED', true)
on conflict (device_id) do nothing;
