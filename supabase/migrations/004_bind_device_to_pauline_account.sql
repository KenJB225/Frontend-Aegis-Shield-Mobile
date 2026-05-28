-- Migration: Bind the shared device row to a single owner account

alter table device_status
  add column if not exists owner_email text;

update device_status
set owner_email = 'paulineponon05@gmail.com'
where device_id = 'ESP32_RACK_01'
  and owner_email is null;

alter table device_status
  alter column owner_email set not null;

create unique index if not exists device_status_owner_email_idx on device_status (owner_email);

drop policy if exists auth_read_device_status on device_status;
create policy auth_read_device_status on device_status
  for select
  using (auth.role() = 'authenticated' and auth.jwt() ->> 'email' = owner_email);

drop policy if exists auth_update_control_fields on device_status;
create policy auth_update_control_fields on device_status
  for update
  using (auth.role() = 'authenticated' and auth.jwt() ->> 'email' = owner_email)
  with check (auth.role() = 'authenticated' and auth.jwt() ->> 'email' = owner_email);

drop policy if exists device_manage_own_row on device_status;
create policy device_manage_own_row on device_status
  for all
  using (current_setting('jwt.claims.device_id', true) = device_id and owner_email = 'paulineponon05@gmail.com')
  with check (current_setting('jwt.claims.device_id', true) = device_id and owner_email = 'paulineponon05@gmail.com');

drop policy if exists device_firmware_read_own_row on device_status;
create policy device_firmware_read_own_row on device_status
  for select
  using (auth.role() = 'anon' and device_id = 'ESP32_RACK_01' and owner_email = 'paulineponon05@gmail.com');

drop policy if exists device_firmware_update_own_row on device_status;
create policy device_firmware_update_own_row on device_status
  for update
  using (auth.role() = 'anon' and device_id = 'ESP32_RACK_01' and owner_email = 'paulineponon05@gmail.com')
  with check (auth.role() = 'anon' and device_id = 'ESP32_RACK_01' and owner_email = 'paulineponon05@gmail.com');