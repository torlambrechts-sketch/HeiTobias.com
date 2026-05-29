-- Phase B notifications — in-app bell + per-user preferences.
--
-- The notifications outbox table already exists (Gap-closure Step 1).
-- It models OUTBOUND dispatch (queue → dispatched → delivered) for
-- email/slack/teams/calendar. The `in_app` channel writes to the same
-- row; for those, "delivered" means "the user has seen it in the
-- bell." We add:
--
--   * notifications.seen_at  — when the recipient first viewed the row
--   * notifications.read_at  — when they explicitly marked it read
--   * notification_preferences — per-person opt-in / opt-out per
--                                (channel, kind) + quiet-hours window.
--   * Three RPCs the bell + preferences UI call:
--       notifications_unread_count()
--       notifications_recent_for_me(limit, offset)
--       notifications_mark_read(id)  /  notifications_mark_all_read()
--
-- RLS on notifications is already self-recipient-only for SELECT; the
-- new RPCs read/write through that same scope (no privilege
-- escalation). preferences are also self-only.

-- ─── 1. Outbox columns ──────────────────────────────────────────────
alter table public.notifications
  add column if not exists seen_at timestamptz,
  add column if not exists read_at timestamptz;

create index if not exists notifications_recipient_unread_idx
  on public.notifications (recipient_person_id, channel)
  where channel = 'in_app' and read_at is null;

-- ─── 2. Preferences table ───────────────────────────────────────────
create table if not exists public.notification_preferences (
  id                  uuid primary key default extensions.gen_random_uuid(),
  person_id           uuid not null references public.people(id) on delete cascade,
  -- The pair (channel, kind) identifies a notification class. Kind is
  -- free-form text rather than an enum because new notification kinds
  -- (e.g. 'team_def.divergence_ready') land alongside their feature
  -- without a schema migration.
  channel             public.notification_channel not null,
  kind                text not null,
  enabled             boolean not null default true,
  -- Quiet hours are stored as (start_minute, end_minute) in the
  -- person's locale. Email sends inside the window get held until the
  -- window closes; in-app notifications are not affected (the bell is
  -- pull, not push).
  quiet_hours_start_min int,
  quiet_hours_end_min   int,
  locale              text,
  updated_at          timestamptz not null default now(),
  unique (person_id, channel, kind)
);

create index if not exists notification_preferences_person_idx
  on public.notification_preferences (person_id);

alter table public.notification_preferences enable row level security;
alter table public.notification_preferences force  row level security;

-- Self-only RLS — a person manages their own preferences. No org
-- admin override; preferences are personal.
drop policy if exists notification_preferences_self_select on public.notification_preferences;
create policy notification_preferences_self_select on public.notification_preferences
  for select to authenticated using (public.is_self(person_id));

drop policy if exists notification_preferences_self_write on public.notification_preferences;
create policy notification_preferences_self_write on public.notification_preferences
  for all to authenticated
  using (public.is_self(person_id))
  with check (public.is_self(person_id));

-- ─── 3. RPCs ────────────────────────────────────────────────────────
create or replace function public.notifications_unread_count_for_me()
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int from public.notifications n
   where n.recipient_person_id =
         (select id from public.people where auth_user_id = (select auth.uid()) limit 1)
     and n.channel = 'in_app'
     and n.read_at is null;
$$;
revoke execute on function public.notifications_unread_count_for_me() from public;
grant  execute on function public.notifications_unread_count_for_me() to authenticated;

create or replace function public.notifications_recent_for_me(
  p_limit int default 30,
  p_offset int default 0
)
returns table (
  id           uuid,
  org_id       uuid,
  subject      text,
  body         text,
  payload_json jsonb,
  created_at   timestamptz,
  read_at      timestamptz,
  seen_at      timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select n.id, n.org_id, n.subject, n.body, n.payload_json, n.created_at, n.read_at, n.seen_at
    from public.notifications n
   where n.recipient_person_id =
         (select id from public.people where auth_user_id = (select auth.uid()) limit 1)
     and n.channel = 'in_app'
   order by n.created_at desc
   limit greatest(0, least(p_limit, 100))
  offset greatest(0, p_offset);
$$;
revoke execute on function public.notifications_recent_for_me(int, int) from public;
grant  execute on function public.notifications_recent_for_me(int, int) to authenticated;

create or replace function public.notifications_mark_read(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
begin
  if v_me is null then raise exception 'unauthenticated'; end if;
  update public.notifications
     set read_at = coalesce(read_at, now()),
         seen_at = coalesce(seen_at, now())
   where id = p_id
     and recipient_person_id = v_me;
end;
$$;
revoke execute on function public.notifications_mark_read(uuid) from public;
grant  execute on function public.notifications_mark_read(uuid) to authenticated;

create or replace function public.notifications_mark_all_read_for_me()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
  v_n  int := 0;
begin
  if v_me is null then raise exception 'unauthenticated'; end if;
  update public.notifications
     set read_at = now(), seen_at = coalesce(seen_at, now())
   where recipient_person_id = v_me
     and channel = 'in_app'
     and read_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke execute on function public.notifications_mark_all_read_for_me() from public;
grant  execute on function public.notifications_mark_all_read_for_me() to authenticated;
