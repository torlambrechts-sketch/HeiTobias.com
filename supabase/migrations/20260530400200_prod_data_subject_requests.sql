-- Production hardening: GDPR data-subject-request infrastructure.
--
-- Article 15 (Right of access) and Article 17 (Right to erasure) require:
--   * The subject can obtain a copy of their personal data on request.
--   * The subject can request erasure; we must comply unless an
--     overriding legal basis (e.g. unfinished placement, statutory
--     retention) blocks it — in which case the response is a *refusal
--     with reason*, logged.
--
-- Architecture:
--   * `data_subject_requests` table — the request ledger. The subject (or
--     their org admin acting on their behalf) opens a row; a privileged
--     operator (or scheduled job) fulfils it; the audit_log captures both.
--   * `data_subject_request_kind` enum — `export` | `erase`.
--   * `data_subject_request_status` enum — `pending` | `fulfilled` |
--     `refused` | `partially_fulfilled`.
--   * RPC `dsr_open(kind)` — the subject (or an admin with the right
--     permission) opens a request against their own person_id. Default-deny
--     for everyone else.
--   * RPC `dsr_fulfil(request_id, payload_jsonb, status)` — privileged
--     operator records the outcome. Audited.
--   * RPC `dsr_export_my_data()` — returns the export payload synchronously
--     for the calling person (Article 15 fast-path). For complex orgs the
--     async ledger is the durable path; this RPC is the "I want my data
--     now" path for the data subject themselves.
--
-- These RPCs are SECURITY DEFINER with `set search_path = ''` per the
-- hardening discipline. Every consequential mutation writes to audit_log.

-- ─── Helper: caller's person_id (or NULL if unauthenticated) ───────
create or replace function public.current_person_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.people where auth_user_id = (select auth.uid()) limit 1;
$$;
revoke execute on function public.current_person_id() from public;
grant  execute on function public.current_person_id() to authenticated, anon, service_role;

-- ─── Enums ──────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_type where typname = 'data_subject_request_kind') then
    create type public.data_subject_request_kind as enum ('export', 'erase');
  end if;
  if not exists (select 1 from pg_type where typname = 'data_subject_request_status') then
    create type public.data_subject_request_status as enum (
      'pending', 'fulfilled', 'refused', 'partially_fulfilled'
    );
  end if;
end $$;

-- ─── Ledger table ───────────────────────────────────────────────────
create table if not exists public.data_subject_requests (
  id              uuid primary key default gen_random_uuid(),
  person_id       uuid not null references public.people(id) on delete restrict,
  org_id          uuid references public.organizations(id) on delete set null,
  kind            public.data_subject_request_kind not null,
  status          public.data_subject_request_status not null default 'pending',
  opened_by       uuid not null references public.people(id) on delete restrict,
  opened_at       timestamptz not null default now(),
  fulfilled_by    uuid references public.people(id) on delete set null,
  fulfilled_at    timestamptz,
  refusal_reason  text,
  evidence_ref    text,            -- link to the export blob or erasure receipt
  notes           jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists data_subject_requests_person_idx
  on public.data_subject_requests (person_id, opened_at desc);
create index if not exists data_subject_requests_status_idx
  on public.data_subject_requests (status, opened_at desc)
  where status = 'pending';

-- updated_at trigger
create or replace function public.tg_data_subject_requests_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_data_subject_requests_touch on public.data_subject_requests;
create trigger trg_data_subject_requests_touch
  before update on public.data_subject_requests
  for each row execute function public.tg_data_subject_requests_touch();

alter table public.data_subject_requests enable row level security;
alter table public.data_subject_requests force row level security;

-- Default deny is implicit; we add narrow allow policies.
-- The subject themselves can see their own requests.
drop policy if exists dsr_select_subject on public.data_subject_requests;
create policy dsr_select_subject on public.data_subject_requests
  for select
  using (person_id = public.current_person_id());

-- Org admins with the dsr.read permission can see DSRs for people in their org.
drop policy if exists dsr_select_admin on public.data_subject_requests;
create policy dsr_select_admin on public.data_subject_requests
  for select
  using (org_id is not null and public.has_permission(org_id, 'dsr.read'));

-- ─── RPC: open a DSR ────────────────────────────────────────────────
create or replace function public.dsr_open(
  p_kind public.data_subject_request_kind,
  p_org_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_self uuid := public.current_person_id();
  v_id   uuid;
begin
  if v_self is null then
    raise exception 'unauthenticated';
  end if;

  insert into public.data_subject_requests (person_id, org_id, kind, opened_by)
  values (v_self, p_org_id, p_kind, v_self)
  returning id into v_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
  values (
    p_org_id,
    v_self,
    'dsr.open',
    'data_subject_requests',
    v_id,
    jsonb_build_object('kind', p_kind)
  );

  return v_id;
end;
$$;

revoke all on function public.dsr_open(public.data_subject_request_kind, uuid) from public;
grant execute on function public.dsr_open(public.data_subject_request_kind, uuid) to authenticated;

-- ─── RPC: fulfil a DSR ──────────────────────────────────────────────
-- Privileged. The caller must hold dsr.fulfil in the org of the request.
create or replace function public.dsr_fulfil(
  p_request_id uuid,
  p_status public.data_subject_request_status,
  p_evidence_ref text default null,
  p_refusal_reason text default null,
  p_notes jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_self uuid := public.current_person_id();
  v_org  uuid;
begin
  if v_self is null then
    raise exception 'unauthenticated';
  end if;

  select org_id into v_org from public.data_subject_requests where id = p_request_id;

  if v_org is null then
    raise exception 'dsr.org_required_for_fulfilment';
  end if;

  if not public.has_permission(v_org, 'dsr.fulfil') then
    raise exception 'forbidden';
  end if;

  if p_status not in ('fulfilled', 'refused', 'partially_fulfilled') then
    raise exception 'invalid_terminal_status: %', p_status;
  end if;

  update public.data_subject_requests
     set status = p_status,
         fulfilled_by = v_self,
         fulfilled_at = now(),
         evidence_ref = coalesce(p_evidence_ref, evidence_ref),
         refusal_reason = coalesce(p_refusal_reason, refusal_reason),
         notes = notes || coalesce(p_notes, '{}'::jsonb)
   where id = p_request_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
  values (
    v_org,
    v_self,
    'dsr.fulfil',
    'data_subject_requests',
    p_request_id,
    jsonb_build_object('status', p_status, 'refusal_reason', p_refusal_reason)
  );
end;
$$;

revoke all on function public.dsr_fulfil(uuid, public.data_subject_request_status, text, text, jsonb) from public;
grant execute on function public.dsr_fulfil(uuid, public.data_subject_request_status, text, text, jsonb) to authenticated;

-- ─── RPC: export-my-data fast path ──────────────────────────────────
-- Returns a JSONB bundle of the caller's own personal data. The subject
-- always has the right to this; no permission check beyond authentication.
-- Audited.
create or replace function public.dsr_export_my_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_self uuid := public.current_person_id();
  v_out  jsonb;
begin
  if v_self is null then
    raise exception 'unauthenticated';
  end if;

  -- Pull rows from the tables that hold personal data about this person.
  -- This is deliberately conservative: extend as new personal-data
  -- tables are added (the test suite will flag unenumerated tables).
  select jsonb_build_object(
    'person', (select to_jsonb(p) from public.people p where p.id = v_self),
    'memberships', coalesce(
      (select jsonb_agg(to_jsonb(m)) from public.memberships m where m.person_id = v_self),
      '[]'::jsonb
    ),
    'consent_grants', coalesce(
      (select jsonb_agg(to_jsonb(c)) from public.consent_grants c where c.person_id = v_self),
      '[]'::jsonb
    ),
    'profiles', coalesce(
      (select jsonb_agg(to_jsonb(pr)) from public.profiles pr where pr.person_id = v_self),
      '[]'::jsonb
    ),
    'assessment_sessions', coalesce(
      (select jsonb_agg(to_jsonb(s)) from public.assessment_sessions s where s.person_id = v_self),
      '[]'::jsonb
    ),
    'requisition_candidates', coalesce(
      (select jsonb_agg(to_jsonb(rc)) from public.requisition_candidates rc where rc.person_id = v_self),
      '[]'::jsonb
    ),
    'exported_at', now()
  ) into v_out;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
  values (null, v_self, 'dsr.export_my_data', 'people', v_self, '{}'::jsonb);

  return v_out;
end;
$$;

revoke all on function public.dsr_export_my_data() from public;
grant execute on function public.dsr_export_my_data() to authenticated;

-- ─── Retention sweep ledger ─────────────────────────────────────────
-- Scheduled retention runs record their actions here. The scheduler itself
-- is documented in docs/RETENTION.md; the table exists so the job's writes
-- have a typed destination from day one.
create table if not exists public.retention_runs (
  id            uuid primary key default gen_random_uuid(),
  policy_key    text not null,
  ran_at        timestamptz not null default now(),
  rows_scanned  int  not null default 0,
  rows_affected int  not null default 0,
  status        text not null default 'noop'  -- 'noop' | 'applied' | 'failed'
                check (status in ('noop', 'applied', 'failed')),
  detail        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);

alter table public.retention_runs enable row level security;
alter table public.retention_runs force row level security;

-- Only org admins (org.manage_all) can read the retention ledger for their
-- org. The scheduler writes via service-role; reads are tenant-scoped via
-- the existing RBAC permission. We treat retention as org-scoped operational
-- data; rows without an org_id are platform-level and only visible to
-- people who hold org.manage_all anywhere — keep that conservative.
drop policy if exists retention_runs_admin_select on public.retention_runs;
create policy retention_runs_admin_select on public.retention_runs
  for select
  using (
    exists (
      select 1
      from public.memberships m
      join public.membership_roles mr on mr.membership_id = m.id
      join public.rbac_role_permissions rrp on rrp.role_id = mr.rbac_role_id
      join public.rbac_permissions rp on rp.id = rrp.permission_id
      where m.person_id = public.current_person_id()
        and m.status = 'active'
        and rp.key = 'org.manage_all'
    )
  );

-- ─── RBAC: seed dsr.* permissions ───────────────────────────────────
insert into public.rbac_permissions (key, description) values
  ('dsr.read',   'Read data-subject-request rows for people in this org.'),
  ('dsr.fulfil', 'Fulfil or refuse a data-subject request. Privileged.')
on conflict (key) do nothing;

-- Grant dsr.* to org_admin and people_ops_admin by default. Other roles
-- get no DSR access; the data subject still has direct visibility on
-- their own requests via the dsr_select_subject policy.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id
from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null
  and r.key in ('org_admin', 'people_ops_admin')
  and p.key in ('dsr.read', 'dsr.fulfil')
on conflict do nothing;
