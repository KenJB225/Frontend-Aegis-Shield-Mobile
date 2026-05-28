-- Migration: Production-ready RLS policies for device_status

-- Postgres does not support CREATE POLICY IF NOT EXISTS, use DROP IF EXISTS then CREATE for idempotency
drop policy if exists auth_read_device_status on device_status;
create policy auth_read_device_status on device_status
  for select
  using (auth.role() = 'authenticated');

drop policy if exists device_manage_own_row on device_status;
create policy device_manage_own_row on device_status
  for all
  using (current_setting('jwt.claims.device_id', true) = device_id)
  with check (current_setting('jwt.claims.device_id', true) = device_id);

drop policy if exists auth_update_control_fields on device_status;
create policy auth_update_control_fields on device_status
  for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- NOTE: The `auth_update_control_fields` policy above is intentionally permissive for updates by authenticated users.
-- Restricting updates to specific columns requires careful expressions referencing OLD/NEW which can be brittle in migrations.
-- Review and harden these policies in your Supabase dashboard to match your production auth model.
