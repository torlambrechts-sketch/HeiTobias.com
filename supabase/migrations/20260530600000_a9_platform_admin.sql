-- A9 — Super-admin minimal surface.
--
-- Three deliverables in one migration:
--   1. `platform_admin` RBAC role (org_id = NULL, system-level) plus
--      three new permission keys (`platform.read`, `platform.investigate`,
--      `platform.manage_orgs`) and the mapping.
--   2. `organizations.suspended_at` + `suspended_reason` columns to
--      back the suspension behaviour (org_status enum already has
--      'suspended' — these capture WHO + WHEN + WHY).
--   3. `platform_admin_investigation_log` table — the audit trail of
--      the platform admin's OWN actions, separate from the per-org
--      audit_log so it cannot be hidden by an org admin and so its
--      retention rules can be set independently.
--   4. Six SECDEF RPCs with locked search_path:
--        platform_org_create(...)
--        platform_org_suspend(org_id, reason)
--        platform_org_reactivate(org_id, reason)
--        platform_metrics()
--        platform_orgs_list()
--        platform_investigation_log_write(...)
--
-- What this migration deliberately does NOT do:
--   * Auto-grant platform_admin to anyone. The founder claims via a
--     direct INSERT into membership_roles (one-time setup, documented
--     in docs/OPERATOR-RUNBOOK.md). After that, the founder can grant
--     to additional people via a future UI.
--   * Force-logout users when their org is suspended. We rely on the
--     existing session lifecycle + a client-side check that signs out
--     when the user's org is no longer active. The Supabase Admin API
--     for session revocation is an operator follow-up.

-- ─── 1. Permission keys + role + mappings ──────────────────────────
insert into public.rbac_permissions (key, description) values
  ('platform.read',        'Read aggregate platform metrics (counts only, no PII).'),
  ('platform.investigate', 'Cross-org audit-log investigation for support purposes. Every read is logged to platform_admin_investigation_log.'),
  ('platform.manage_orgs', 'Create, suspend, reactivate customer organisations.')
on conflict (key) do nothing;

insert into public.rbac_roles (org_id, key, name) values
  (null, 'platform_admin', 'Platform Admin')
on conflict (org_id, key) do nothing;

insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id
from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null
  and r.key = 'platform_admin'
  and p.key in ('platform.read', 'platform.investigate', 'platform.manage_orgs')
on conflict do nothing;

-- ─── 2. Suspension provenance columns ──────────────────────────────
alter table public.organizations
  add column if not exists suspended_at     timestamptz,
  add column if not exists suspended_reason text;

-- ─── 3. Investigation log ──────────────────────────────────────────
-- This is structurally similar to audit_log but lives in its own table
-- because it records the platform admin's actions (which span orgs)
-- and per-org RLS would hide them from the admin who needs to verify
-- their own past behaviour. The platform_admin role itself is the only
-- principal that can SELECT from here.
create table if not exists public.platform_admin_investigation_log (
  id                uuid primary key default extensions.gen_random_uuid(),
  actor_person_id   uuid not null references public.people(id) on delete restrict,
  action            text not null,
  target_org_id     uuid references public.organizations(id) on delete set null,
  payload_json      jsonb not null default '{}'::jsonb,
  at                timestamptz not null default now()
);
create index if not exists pail_actor_idx       on public.platform_admin_investigation_log (actor_person_id, at desc);
create index if not exists pail_target_org_idx  on public.platform_admin_investigation_log (target_org_id, at desc);

alter table public.platform_admin_investigation_log enable row level security;
alter table public.platform_admin_investigation_log force  row level security;

-- Defense-in-depth: immutable like audit_log.
create or replace function public._pail_immutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'platform_admin_investigation_log is immutable: % not allowed', TG_OP;
end;
$$;
drop trigger if exists trg_pail_no_update on public.platform_admin_investigation_log;
create trigger trg_pail_no_update before update on public.platform_admin_investigation_log
  for each row execute function public._pail_immutable();
drop trigger if exists trg_pail_no_delete on public.platform_admin_investigation_log;
create trigger trg_pail_no_delete before delete on public.platform_admin_investigation_log
  for each row execute function public._pail_immutable();

drop policy if exists pail_select on public.platform_admin_investigation_log;
create policy pail_select on public.platform_admin_investigation_log
  for select to authenticated using (
    exists (
      select 1
      from public.memberships m
      join public.membership_roles mr on mr.membership_id = m.id
      join public.rbac_roles r on r.id = mr.rbac_role_id
      join public.people p on p.id = m.person_id
      where p.auth_user_id = (select auth.uid())
        and r.org_id is null
        and r.key = 'platform_admin'
        and m.status = 'active'
    )
  );

-- ─── 4. Helper: is the caller a platform admin? ────────────────────
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.membership_roles mr on mr.membership_id = m.id
    join public.rbac_roles r on r.id = mr.rbac_role_id
    join public.people p on p.id = m.person_id
    where p.auth_user_id = (select auth.uid())
      and r.org_id is null
      and r.key = 'platform_admin'
      and m.status = 'active'
  );
$$;
revoke execute on function public.is_platform_admin() from public;
grant  execute on function public.is_platform_admin() to authenticated, anon, service_role;
comment on function public.is_platform_admin() is
  'Returns true iff the caller has an ACTIVE membership granting the system-level platform_admin role (org_id IS NULL on rbac_roles).';

-- ─── 5. RPC: platform_orgs_list ────────────────────────────────────
-- Returns metadata about every org on the platform. Aggregate counts
-- only — no row-level customer data. Platform-admin gated.
create or replace function public.platform_orgs_list()
returns table (
  id                uuid,
  name              text,
  type              public.org_type,
  status            public.org_status,
  country           text,
  data_region       public.data_region,
  created_at        timestamptz,
  suspended_at      timestamptz,
  suspended_reason  text,
  user_count        int,
  active_placement_count int,
  is_demo           boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    o.id,
    o.name,
    o.type,
    o.status,
    o.country,
    o.data_region,
    o.created_at,
    o.suspended_at,
    o.suspended_reason,
    (select count(*)::int from public.memberships m where m.org_id = o.id and m.status = 'active'),
    (select count(*)::int from public.placements p where p.to_org_id = o.id and p.status in ('transferred', 'activated')),
    coalesce((o.settings_json ->> 'is_demo')::boolean, false)
  from public.organizations o
  where public.is_platform_admin()
  order by o.created_at desc;
$$;
revoke execute on function public.platform_orgs_list() from public;
grant  execute on function public.platform_orgs_list() to authenticated;

-- ─── 6. RPC: platform_metrics ──────────────────────────────────────
-- Aggregate platform-wide counts only. No identifying data.
create or replace function public.platform_metrics()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'orgs_total',          (select count(*) from public.organizations),
    'orgs_active',         (select count(*) from public.organizations where status = 'active'),
    'orgs_suspended',      (select count(*) from public.organizations where status = 'suspended'),
    'orgs_archived',       (select count(*) from public.organizations where status = 'archived'),
    'users_total',         (select count(*) from public.people),
    'memberships_active',  (select count(*) from public.memberships where status = 'active'),
    'placements_active',   (select count(*) from public.placements where status in ('transferred', 'activated')),
    'placements_last_7d',  (select count(*) from public.placements where created_at > now() - interval '7 days'),
    'requisitions_open',   (select count(*) from public.requisitions where status = 'open'),
    'audit_events_last_24h', (select count(*) from public.audit_log where at > now() - interval '24 hours'),
    'computed_at',         now()
  )
  where public.is_platform_admin();
$$;
revoke execute on function public.platform_metrics() from public;
grant  execute on function public.platform_metrics() to authenticated;

-- ─── 7. RPC: platform_org_create ───────────────────────────────────
-- Creates a new org + (optionally) an initial admin user invite.
-- Returns the new org_id. The admin_email is captured as a notification
-- target for the invite that the org admin separately processes via
-- the standard invite flow.
create or replace function public.platform_org_create(
  p_name        text,
  p_type        text,           -- 'agency' | 'employer'
  p_country     text default 'NO',
  p_locale      text default 'nb-NO',
  p_admin_email text default null,
  p_admin_name  text default null,
  p_is_demo     boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor    uuid;
  v_org_id   uuid;
  v_settings jsonb;
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden: platform_admin required';
  end if;
  if char_length(coalesce(p_name, '')) < 2 then
    raise exception 'platform_org_create: name >= 2 chars';
  end if;
  if p_type not in ('agency', 'employer') then
    raise exception 'platform_org_create: type must be agency|employer';
  end if;

  v_actor := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
  v_settings := case when p_is_demo then '{"is_demo": true}'::jsonb else '{}'::jsonb end;

  insert into public.organizations (name, type, country, locale_default, status, settings_json)
    values (p_name, p_type::public.org_type, p_country, p_locale, 'active', v_settings)
    returning id into v_org_id;

  insert into public.platform_admin_investigation_log (actor_person_id, action, target_org_id, payload_json)
    values (v_actor, 'org.create', v_org_id,
            jsonb_build_object('name', p_name, 'type', p_type, 'admin_email', p_admin_email));

  -- Mirror an audit_log entry tied to the new org so it shows up in the
  -- standard org-side audit view as well.
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org_id, v_actor, 'platform.org_create', 'organizations', v_org_id,
            jsonb_build_object('name', p_name, 'type', p_type));

  return v_org_id;
end;
$$;
revoke execute on function public.platform_org_create(text, text, text, text, text, text, boolean) from public;
grant  execute on function public.platform_org_create(text, text, text, text, text, text, boolean) to authenticated;

-- ─── 8. RPC: platform_org_suspend ──────────────────────────────────
create or replace function public.platform_org_suspend(
  p_org_id  uuid,
  p_reason  text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden: platform_admin required';
  end if;
  if char_length(coalesce(p_reason, '')) < 20 then
    raise exception 'platform_org_suspend: reason >= 20 chars (audit-grade)';
  end if;

  v_actor := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);

  update public.organizations
     set status = 'suspended',
         suspended_at = now(),
         suspended_reason = p_reason
   where id = p_org_id
     and status <> 'archived';

  if not found then
    raise exception 'platform_org_suspend: org not found or archived';
  end if;

  insert into public.platform_admin_investigation_log (actor_person_id, action, target_org_id, payload_json)
    values (v_actor, 'org.suspend', p_org_id, jsonb_build_object('reason', p_reason));

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'platform.org_suspend', 'organizations', p_org_id,
            jsonb_build_object('reason', p_reason));
end;
$$;
revoke execute on function public.platform_org_suspend(uuid, text) from public;
grant  execute on function public.platform_org_suspend(uuid, text) to authenticated;

-- ─── 9. RPC: platform_org_reactivate ───────────────────────────────
create or replace function public.platform_org_reactivate(
  p_org_id  uuid,
  p_reason  text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden: platform_admin required';
  end if;
  if char_length(coalesce(p_reason, '')) < 20 then
    raise exception 'platform_org_reactivate: reason >= 20 chars (audit-grade)';
  end if;

  v_actor := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);

  update public.organizations
     set status = 'active',
         suspended_at = null,
         suspended_reason = null
   where id = p_org_id
     and status = 'suspended';

  if not found then
    raise exception 'platform_org_reactivate: org not found or not suspended';
  end if;

  insert into public.platform_admin_investigation_log (actor_person_id, action, target_org_id, payload_json)
    values (v_actor, 'org.reactivate', p_org_id, jsonb_build_object('reason', p_reason));

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'platform.org_reactivate', 'organizations', p_org_id,
            jsonb_build_object('reason', p_reason));
end;
$$;
revoke execute on function public.platform_org_reactivate(uuid, text) from public;
grant  execute on function public.platform_org_reactivate(uuid, text) to authenticated;

-- ─── 10. RPC: platform_investigation_log_write ─────────────────────
-- Lets the platform admin record their investigative reads (e.g. when
-- the audit explorer is opened with cross-org scope). The audit
-- explorer client calls this on every cross-org query so the founder's
-- own activity is auditable.
create or replace function public.platform_investigation_log_write(
  p_action         text,
  p_target_org_id  uuid,
  p_payload        jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_id    uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden: platform_admin required';
  end if;
  v_actor := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
  insert into public.platform_admin_investigation_log (actor_person_id, action, target_org_id, payload_json)
    values (v_actor, p_action, p_target_org_id, coalesce(p_payload, '{}'::jsonb))
    returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function public.platform_investigation_log_write(text, uuid, jsonb) from public;
grant  execute on function public.platform_investigation_log_write(text, uuid, jsonb) to authenticated;

-- ─── 11. RPC: platform_investigation_log_recent ────────────────────
-- The platform admin's view of their own activity. Used by the surface
-- to show "recent investigations" so the admin sees the trail of their
-- own actions.
create or replace function public.platform_investigation_log_recent(
  p_limit int default 50
)
returns table (
  id              uuid,
  actor_person_id uuid,
  action          text,
  target_org_id   uuid,
  payload_json    jsonb,
  at              timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select id, actor_person_id, action, target_org_id, payload_json, at
    from public.platform_admin_investigation_log
   where public.is_platform_admin()
   order by at desc
   limit greatest(0, least(p_limit, 200));
$$;
revoke execute on function public.platform_investigation_log_recent(int) from public;
grant  execute on function public.platform_investigation_log_recent(int) to authenticated;

-- ─── 12. Suspension behaviour: helper to check current user's org ──
-- Returns the status of the caller's primary org (first active
-- membership). The browser uses this to refuse loading sensitive
-- surfaces when the user's org has been suspended. Defense-in-depth;
-- per-RPC checks below catch any client that ignores the helper.
create or replace function public.current_user_org_status()
returns public.org_status
language sql
stable
security definer
set search_path = ''
as $$
  select o.status
    from public.organizations o
    join public.memberships m on m.org_id = o.id
    join public.people p on p.id = m.person_id
   where p.auth_user_id = (select auth.uid())
     and m.status = 'active'
   order by m.created_at asc
   limit 1;
$$;
revoke execute on function public.current_user_org_status() from public;
grant  execute on function public.current_user_org_status() to authenticated;
