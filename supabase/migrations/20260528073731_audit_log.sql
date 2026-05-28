-- audit_log — immutable, insert-only log of consequential mutations.
--
-- Writes come from two paths:
--   1. _audit_row trigger attached to every domain table (except audit_log itself).
--   2. audit_log_event(...) RPC for non-row events (sign-ins, exports, RPC calls).
--
-- Reads: blocked by RLS default-deny in Step 4; Step 6 adds a SELECT policy
-- gated on `audit.read`.
--
-- Updates / deletes: blocked by (a) RLS default-deny and (b) defense-in-depth
-- triggers that raise on UPDATE / DELETE even for owner roles.

create table public.audit_log (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid references public.organizations(id) on delete restrict,
  actor_person_id uuid references public.people(id) on delete set null,
  action          text not null,
  entity_type     text not null,
  entity_id       uuid,
  before_json     jsonb,
  after_json      jsonb,
  at              timestamptz not null default now(),
  request_id      text
);
create index audit_log_org_idx    on public.audit_log (org_id);
create index audit_log_entity_idx on public.audit_log (entity_type, entity_id);
create index audit_log_at_idx     on public.audit_log (at desc);

comment on table public.audit_log is
  'Immutable insert-only log of consequential mutations. Written by triggers on every domain table and by audit_log_event(). Step 6 adds a SELECT policy gated on audit.read.';

-- ---- Immutability triggers ----------------------------------------------
create or replace function public._audit_log_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_log is immutable: % not allowed', TG_OP;
end;
$$;
create trigger trg_audit_log_no_update
  before update on public.audit_log
  for each row execute function public._audit_log_immutable();
create trigger trg_audit_log_no_delete
  before delete on public.audit_log
  for each row execute function public._audit_log_immutable();

alter table public.audit_log enable row level security;

-- ---- Generic row-audit trigger function ---------------------------------
create or replace function public._audit_row()
returns trigger
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_old    jsonb := null;
  v_new    jsonb := null;
  v_org_id uuid;
  v_entity uuid;
  v_actor  uuid;
begin
  if TG_OP <> 'INSERT' then v_old := to_jsonb(old); end if;
  if TG_OP <> 'DELETE' then v_new := to_jsonb(new); end if;

  -- entity_id: try the row's id column (composite-PK tables have no id; null is fine).
  v_entity := nullif(coalesce(v_new->>'id', v_old->>'id'), '')::uuid;

  -- org_id resolution: explicit org_id, fall back to from_org_id (for placements).
  v_org_id := nullif(coalesce(v_new->>'org_id', v_old->>'org_id'), '')::uuid;
  if v_org_id is null then
    v_org_id := nullif(coalesce(v_new->>'from_org_id', v_old->>'from_org_id'), '')::uuid;
  end if;

  -- Actor: resolve auth.uid() to a people row, if any (null for service role / no JWT).
  select id into v_actor
    from public.people
    where auth_user_id = (select auth.uid())
    limit 1;

  insert into public.audit_log (
    org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json
  ) values (
    v_org_id, v_actor, lower(TG_OP), TG_TABLE_NAME, v_entity, v_old, v_new
  );

  return case when TG_OP = 'DELETE' then old else new end;
end;
$$;

-- ---- Attach to every domain table (NOT audit_log itself) ----------------
create trigger trg_audit_organizations          after insert or update or delete on public.organizations          for each row execute function public._audit_row();
create trigger trg_audit_people                 after insert or update or delete on public.people                 for each row execute function public._audit_row();
create trigger trg_audit_memberships            after insert or update or delete on public.memberships            for each row execute function public._audit_row();
create trigger trg_audit_departments            after insert or update or delete on public.departments            for each row execute function public._audit_row();
create trigger trg_audit_teams                  after insert or update or delete on public.teams                  for each row execute function public._audit_row();
create trigger trg_audit_team_members           after insert or update or delete on public.team_members           for each row execute function public._audit_row();
create trigger trg_audit_roles_catalog          after insert or update or delete on public.roles_catalog          for each row execute function public._audit_row();
create trigger trg_audit_positions              after insert or update or delete on public.positions              for each row execute function public._audit_row();
create trigger trg_audit_profiles               after insert or update or delete on public.profiles               for each row execute function public._audit_row();
create trigger trg_audit_assessments            after insert or update or delete on public.assessments            for each row execute function public._audit_row();
create trigger trg_audit_requisitions           after insert or update or delete on public.requisitions           for each row execute function public._audit_row();
create trigger trg_audit_requisition_candidates after insert or update or delete on public.requisition_candidates for each row execute function public._audit_row();
create trigger trg_audit_placements             after insert or update or delete on public.placements             for each row execute function public._audit_row();
create trigger trg_audit_consent_grants         after insert or update or delete on public.consent_grants         for each row execute function public._audit_row();
create trigger trg_audit_rbac_roles             after insert or update or delete on public.rbac_roles             for each row execute function public._audit_row();
create trigger trg_audit_rbac_permissions       after insert or update or delete on public.rbac_permissions       for each row execute function public._audit_row();
create trigger trg_audit_rbac_role_permissions  after insert or update or delete on public.rbac_role_permissions  for each row execute function public._audit_row();
create trigger trg_audit_membership_roles       after insert or update or delete on public.membership_roles       for each row execute function public._audit_row();

-- ---- audit_log_event RPC (app-emitted events) ---------------------------
create or replace function public.audit_log_event(
  p_org_id      uuid,
  p_action      text,
  p_entity_type text,
  p_entity_id   uuid    default null,
  p_before_json jsonb   default null,
  p_after_json  jsonb   default null,
  p_request_id  text    default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_actor  uuid;
  v_id     uuid;
  v_caller uuid := (select auth.uid());
begin
  -- If invoked from a user JWT, require org.read in target org. Service role
  -- (no auth.uid()) is trusted and skips the check.
  if p_org_id is not null and v_caller is not null then
    if not public.has_permission(p_org_id, 'org.read') then
      raise exception 'audit_log_event: caller lacks org.read in target org';
    end if;
  end if;

  -- Caller cannot set actor; it's always resolved from the JWT.
  select id into v_actor from public.people where auth_user_id = v_caller limit 1;

  insert into public.audit_log (
    org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json, request_id
  ) values (
    p_org_id, v_actor, p_action, p_entity_type, p_entity_id, p_before_json, p_after_json, p_request_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.audit_log_event(uuid, text, text, uuid, jsonb, jsonb, text) from public;
grant  execute on function public.audit_log_event(uuid, text, text, uuid, jsonb, jsonb, text) to authenticated, service_role;

comment on function public.audit_log_event(uuid, text, text, uuid, jsonb, jsonb, text) is
  'Emit a manual audit event. Caller cannot set actor; resolved from auth.uid(). Org.read required when invoked from a user JWT.';
