-- Store obstruction incidents independently from the rack's current position.
-- Firmware sets obstruction_event=true; this trigger timestamps the event and
-- resets the one-shot flag so the mobile app can detect each incident.

alter table device_status
  add column if not exists heartbeat_ms bigint,
  add column if not exists obstruction_event boolean not null default false,
  add column if not exists obstruction_event_at timestamptz;

create or replace function update_device_status_heartbeat()
returns trigger
language plpgsql
as $$
begin
  if NEW.obstruction_event then
    NEW.obstruction_event_at = now();
    NEW.obstruction_event = false;
  end if;

  if NEW.temperature_c is distinct from OLD.temperature_c
     or NEW.humidity is distinct from OLD.humidity
     or NEW.is_raining is distinct from OLD.is_raining
     or NEW.rack_status is distinct from OLD.rack_status
     or NEW.heartbeat_ms is distinct from OLD.heartbeat_ms then
    NEW.last_updated = now();
  end if;
  return NEW;
end;
$$;

drop trigger if exists device_status_heartbeat on device_status;
create trigger device_status_heartbeat
before update on device_status
for each row
execute function update_device_status_heartbeat();
