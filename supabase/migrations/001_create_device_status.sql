-- Migration: Create device_status table
-- Path: supabase/migrations/001_create_device_status.sql

-- Create table to store device telemetry and control commands
create table if not exists device_status (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  temperature_c double precision,
  humidity double precision,
  is_raining boolean,
  rack_status text,
  is_auto_mode boolean default true,
  command text,
  last_updated timestamptz default now()
);

-- Insert a default device row for development/testing (optional)
-- Insert a default device row for development/testing (optional)
-- Use INSERT ... SELECT ... WHERE NOT EXISTS to avoid requiring a unique constraint
insert into device_status (device_id, rack_status, is_auto_mode)
select 'ESP32_RACK_01', 'CLOSED', true
where not exists (select 1 from device_status where device_id = 'ESP32_RACK_01');

-- Example: Enable Realtime replication for this table via Supabase UI or config
-- Note: Realtime is typically configured in Supabase dashboard; keep migrations focused on schema.

-- Example RLS policies (recommended):
-- Adjust role names and conditions to your auth model. These examples assume
-- authenticated users use the "authenticated" role and device/service accounts
-- use a separate role or service key.

-- Enable Row Level Security
alter table device_status enable row level security;

-- Policy: Allow authenticated users to SELECT (read) device status
create policy "auth_read_device_status" on device_status
  for select
  using (auth.role() = 'authenticated');

-- Policy: Allow authenticated users to update only the `is_auto_mode` and `command` fields
create policy "auth_update_control_fields" on device_status
  for update
  with check (
    auth.role() = 'authenticated' and (
      (is_auto_mode is not distinct from device_status.is_auto_mode) or
      (command is not distinct from device_status.command)
    )
  );

-- Policy: Allow the device (identified by a service role or JWT claim) to INSERT/UPDATE its own row
-- Example assumes devices authenticate with a JWT containing `device_id` claim.
create policy "device_write_own_row" on device_status
  for all
  using (auth.role() = 'authenticated' or (current_setting('jwt.claims.device_id', true) = device_id))
  with check (current_setting('jwt.claims.device_id', true) = device_id);

-- Note: Supabase's `auth.role()` and `jwt.claims` usage depends on your configuration.
-- Test these policies in a staging environment before production.
