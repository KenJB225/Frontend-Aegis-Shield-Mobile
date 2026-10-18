-- Migration: Store app-observed rack movement events for user analytics.
-- Firmware is intentionally unchanged; the mobile app records commands and
-- realtime device-state transitions.

create table if not exists rack_movement_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  owner_email text not null,
  device_id text not null,
  action text not null check (action in ('EXTEND', 'RETRACT')),
  trigger text not null check (trigger in ('MANUAL', 'RAIN_SENSOR', 'WEATHER_THRESHOLD', 'SYSTEM')),
  mode text not null check (mode in ('AUTO', 'MANUAL')),
  status text not null default 'COMPLETED' check (status in ('REQUESTED', 'COMPLETED', 'FAILED')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  duration_ms integer,
  details jsonb,
  created_at timestamptz not null default now()
);

create index if not exists rack_movement_events_user_date_idx
  on rack_movement_events (user_id, created_at desc);
create index if not exists rack_movement_events_device_date_idx
  on rack_movement_events (device_id, created_at desc);

alter table rack_movement_events enable row level security;

drop policy if exists rack_movement_events_select_own on rack_movement_events;
create policy rack_movement_events_select_own on rack_movement_events
  for select
  using (
    auth.role() = 'authenticated'
    and user_id = auth.uid()
    and lower(owner_email) = lower(auth.jwt() ->> 'email')
  );

drop policy if exists rack_movement_events_insert_own on rack_movement_events;
create policy rack_movement_events_insert_own on rack_movement_events
  for insert
  with check (
    auth.role() = 'authenticated'
    and user_id = auth.uid()
    and lower(owner_email) = lower(auth.jwt() ->> 'email')
  );

drop policy if exists rack_movement_events_update_own on rack_movement_events;
create policy rack_movement_events_update_own on rack_movement_events
  for update
  using (
    auth.role() = 'authenticated'
    and user_id = auth.uid()
    and lower(owner_email) = lower(auth.jwt() ->> 'email')
  )
  with check (
    auth.role() = 'authenticated'
    and user_id = auth.uid()
    and lower(owner_email) = lower(auth.jwt() ->> 'email')
  );

-- Demonstration history for the existing development account. These rows are
-- stored in Supabase, so the app exercises the same query path as live data.
-- New installations without this account simply start with an empty state.
insert into rack_movement_events (
  user_id,
  owner_email,
  device_id,
  action,
  trigger,
  mode,
  status,
  started_at,
  completed_at,
  duration_ms,
  created_at,
  details
)
select
  u.id,
  'paulineponon05@gmail.com',
  'ESP32_RACK_01',
  seed.action,
  seed.trigger,
  seed.mode,
  'COMPLETED',
  seed.started_at,
  seed.completed_at,
  seed.duration_ms,
  seed.created_at,
  jsonb_build_object(
    'source',
    'database_seed',
    'purpose',
    'analytics_demo',
    'note',
    'Seeded historical movements for the rack analytics preview'
  )
from auth.users u
cross join (
  values
    (
      'EXTEND',
      'MANUAL',
      'MANUAL',
      timestamptz '2026-08-18 07:12:00+08',
      timestamptz '2026-08-18 07:12:34+08',
      timestamptz '2026-08-18 07:12:40+08',
      34000
    ),
    (
      'RETRACT',
      'WEATHER_THRESHOLD',
      'AUTO',
      timestamptz '2026-08-18 16:45:00+08',
      timestamptz '2026-08-18 16:45:31+08',
      timestamptz '2026-08-18 16:45:40+08',
      31000
    ),
    (
      'EXTEND',
      'RAIN_SENSOR',
      'AUTO',
      timestamptz '2026-08-19 05:58:00+08',
      timestamptz '2026-08-19 05:58:36+08',
      timestamptz '2026-08-19 05:58:45+08',
      36000
    ),
    (
      'RETRACT',
      'MANUAL',
      'MANUAL',
      timestamptz '2026-08-20 13:24:00+08',
      timestamptz '2026-08-20 13:24:30+08',
      timestamptz '2026-08-20 13:24:39+08',
      30000
    ),
    (
      'EXTEND',
      'WEATHER_THRESHOLD',
      'AUTO',
      timestamptz '2026-08-22 17:10:00+08',
      timestamptz '2026-08-22 17:10:33+08',
      timestamptz '2026-08-22 17:10:42+08',
      33000
    ),
    (
      'RETRACT',
      'WEATHER_THRESHOLD',
      'AUTO',
      timestamptz '2026-08-23 06:02:00+08',
      timestamptz '2026-08-23 06:02:32+08',
      timestamptz '2026-08-23 06:02:41+08',
      32000
    )
) as seed(action, trigger, mode, started_at, completed_at, created_at, duration_ms)
where lower(u.email) = 'paulineponon05@gmail.com'
  and not exists (
    select 1
    from rack_movement_events existing
    where existing.user_id = u.id
      and existing.details ->> 'purpose' = 'analytics_demo'
  );
