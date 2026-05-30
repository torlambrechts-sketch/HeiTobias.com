-- Public Surfaces Phase 5 — in-app feedback submissions.
--
-- The "send feedback" action in the in-app help panel writes here.
-- platform_admin reads. Authenticated users submit (anon feedback would
-- be a spam magnet; the help panel only exists inside the authed app).

create table if not exists public.feedback_submissions (
  id            uuid primary key default extensions.gen_random_uuid(),
  person_id     uuid references public.people(id) on delete set null,
  org_id        uuid references public.organizations(id) on delete set null,
  page_path     text,
  category      text not null default 'general'
                  check (category in ('general', 'bug', 'idea', 'data_concern')),
  message       text not null,
  created_at    timestamptz not null default now(),
  status        text not null default 'new' check (status in ('new', 'triaged', 'closed'))
);
create index if not exists feedback_created_idx on public.feedback_submissions (created_at desc);

alter table public.feedback_submissions enable row level security;
alter table public.feedback_submissions force  row level security;

-- Submitter can read their own; platform_admin reads all.
drop policy if exists feedback_self_read on public.feedback_submissions;
create policy feedback_self_read on public.feedback_submissions
  for select to authenticated using (public.is_self(person_id) or public.is_platform_admin());

create or replace function public.feedback_submit(
  p_message  text,
  p_category text default 'general',
  p_page_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pid uuid := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
  v_org uuid;
  v_id  uuid;
begin
  if v_pid is null then raise exception 'unauthenticated'; end if;
  if char_length(coalesce(p_message, '')) < 3 then raise exception 'message_required'; end if;
  if p_category not in ('general', 'bug', 'idea', 'data_concern') then raise exception 'invalid_category'; end if;

  select org_id into v_org from public.memberships
   where person_id = v_pid and status = 'active' order by created_at asc limit 1;

  insert into public.feedback_submissions (person_id, org_id, page_path, category, message)
  values (v_pid, v_org, p_page_path, p_category, p_message)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;
revoke execute on function public.feedback_submit(text, text, text) from public;
grant  execute on function public.feedback_submit(text, text, text) to authenticated;

-- Platform status snapshot (anon-readable). DELIBERATELY does not read
-- monitoring_incidents — those are PER-ORG ML-monitoring records, and
-- surfacing them publicly would leak customer data (e.g. "org X has a
-- bias incident"). Platform *infrastructure* status (uptime, error rate)
-- lives in the external uptime monitor + Sentry, which this function
-- cannot query.
--
-- So this returns a platform-operator-controlled banner: by default
-- 'operational', with an optional override stored in platform_settings.
-- A platform_admin sets the override during a real infra incident. No
-- per-org data is ever exposed here.
--
-- The override lives in platform_settings.settings-style columns added
-- inline (status_override + status_message) so this stays a single
-- source of truth the operator controls.
alter table public.platform_settings
  add column if not exists status_override text
    check (status_override is null or status_override in ('operational', 'degraded', 'maintenance', 'outage')),
  add column if not exists status_message  text,
  add column if not exists status_updated_at timestamptz;

create or replace function public.platform_status_public()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'status', coalesce((select status_override from public.platform_settings where id), 'operational'),
    'message', (select status_message from public.platform_settings where id),
    'status_updated_at', (select status_updated_at from public.platform_settings where id),
    'as_of', now()
  );
$$;
revoke execute on function public.platform_status_public() from public;
grant  execute on function public.platform_status_public() to anon, authenticated;

-- platform_admin sets/clears the public status banner.
create or replace function public.platform_status_set(
  p_status text default null,   -- null clears the override (back to operational)
  p_message text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_actor uuid := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
begin
  if not public.is_platform_admin() then raise exception 'forbidden'; end if;
  if p_status is not null and p_status not in ('operational', 'degraded', 'maintenance', 'outage') then
    raise exception 'invalid_status';
  end if;
  update public.platform_settings
     set status_override = p_status, status_message = p_message, status_updated_at = now()
   where id = true;
  insert into public.platform_admin_investigation_log (actor_person_id, action, target_org_id, payload_json)
  values (v_actor, 'platform_status.set', null, jsonb_build_object('status', p_status));
end;
$$;
revoke execute on function public.platform_status_set(text, text) from public;
grant  execute on function public.platform_status_set(text, text) to authenticated;
