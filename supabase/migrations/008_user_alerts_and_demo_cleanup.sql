create table if not exists user_alerts (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  timestamp timestamptz not null default now(),
  right_label text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists user_alerts_user_timestamp_idx
  on user_alerts (user_id, timestamp desc);

alter table user_alerts enable row level security;

drop policy if exists user_alerts_select_own on user_alerts;
create policy user_alerts_select_own on user_alerts
  for select
  using (auth.uid() = user_id);

drop policy if exists user_alerts_insert_own on user_alerts;
create policy user_alerts_insert_own on user_alerts
  for insert
  with check (auth.uid() = user_id);

drop policy if exists user_alerts_update_own on user_alerts;
create policy user_alerts_update_own on user_alerts
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update on user_alerts to authenticated;

delete from rack_movement_events
where details ->> 'purpose' = 'analytics_demo';