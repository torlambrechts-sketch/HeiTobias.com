-- phase2_step4_collaborator_scope — Model 2 (shared workspace).
--
-- The employer invites an agency as a SCOPED collaborator on a single
-- requisition. The agency sees ONLY that requisition + its candidates;
-- nothing else in the employer org.
--
-- Phase 0 already has requisitions.collaborating_org_id + the
-- requisitions_select policy that honors it. This migration:
--   1. Extends requisition_candidates_select so a collaborator can see
--      the candidates on the shared requisition (the gap that made
--      Model 2 unusable today — they could see the req row but not its
--      candidates).
--   2. Adds RPCs to invite + remove a collaborator (employer-side action).
--   3. Adds a helper for the UI to surface the collaboration on a
--      requisition.
--
-- CRITICAL framing held: NO new cross-org data path. Model 2 is purely
-- RBAC + RLS — no rows move between orgs. Cross-org data movement
-- remains the Phase 0 placement_execute RPC.

-- ---- helper: is the caller a collaborator on this requisition? ----
create or replace function public.is_requisition_collaborator(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.requisitions r
    where r.id = p_requisition_id
      and r.collaborating_org_id is not null
      and public.has_permission(r.collaborating_org_id, 'requisition.read')
  );
$$;
revoke execute on function public.is_requisition_collaborator(uuid) from public;
grant  execute on function public.is_requisition_collaborator(uuid) to authenticated, service_role, anon;

-- ---- requisition_candidates_select: extend to honor collaborator ----
drop policy if exists requisition_candidates_select on public.requisition_candidates;
create policy requisition_candidates_select on public.requisition_candidates
  for select using (
    public.has_permission(org_id, 'requisition.read')
    or public.is_requisition_collaborator(requisition_id)
  );

-- ---- requisition_invite_collaborator(req_id, agency_org_id) ----
-- Employer adds a SCOPED collaborator to a requisition. Caller must hold
-- requisition.write in the requisition's owning org (i.e. the employer).
-- Idempotent: setting the same collaborator returns the existing.
create or replace function public.requisition_invite_collaborator(
  p_requisition_id   uuid,
  p_collaborator_org_id uuid
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_req    public.requisitions%rowtype;
  v_org    public.organizations%rowtype;
  v_actor  uuid;
begin
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then raise exception 'requisition_invite_collaborator: requisition not found'; end if;
  if v_caller is not null and not public.has_permission(v_req.org_id, 'requisition.write') then
    raise exception 'requisition_invite_collaborator: caller lacks requisition.write in the requisition''s org';
  end if;
  select * into v_org from public.organizations where id = p_collaborator_org_id;
  if not found then raise exception 'requisition_invite_collaborator: collaborator org not found'; end if;
  if v_org.id = v_req.org_id then
    raise exception 'requisition_invite_collaborator: collaborator must be a different org';
  end if;

  -- Idempotent.
  if v_req.collaborating_org_id is not null and v_req.collaborating_org_id = p_collaborator_org_id then
    return v_req.id;
  end if;

  update public.requisitions
    set collaborating_org_id = p_collaborator_org_id, updated_at = now()
    where id = p_requisition_id;

  select id into v_actor from public.people where auth_user_id = v_caller limit 1;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (v_req.org_id, v_actor, 'requisition.collaborator_invited', 'requisitions', p_requisition_id,
      jsonb_build_object('collaborating_org_id', v_req.collaborating_org_id),
      jsonb_build_object('collaborating_org_id', p_collaborator_org_id));
  return p_requisition_id;
end;
$$;
revoke execute on function public.requisition_invite_collaborator(uuid, uuid) from public;
grant  execute on function public.requisition_invite_collaborator(uuid, uuid) to authenticated, service_role;
comment on function public.requisition_invite_collaborator(uuid, uuid) is
  'Employer-side: invite an agency org as a scoped collaborator on a single requisition. RLS extends visibility (req + candidates only). AuthZ: requisition.write in the requisition''s org.';

-- ---- requisition_remove_collaborator(req_id) ----
create or replace function public.requisition_remove_collaborator(p_requisition_id uuid)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_req    public.requisitions%rowtype;
  v_actor  uuid;
begin
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then raise exception 'requisition_remove_collaborator: requisition not found'; end if;
  if v_caller is not null and not public.has_permission(v_req.org_id, 'requisition.write') then
    raise exception 'requisition_remove_collaborator: caller lacks requisition.write';
  end if;
  if v_req.collaborating_org_id is null then
    return p_requisition_id;
  end if;
  update public.requisitions
    set collaborating_org_id = null, updated_at = now()
    where id = p_requisition_id;
  select id into v_actor from public.people where auth_user_id = v_caller limit 1;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (v_req.org_id, v_actor, 'requisition.collaborator_removed', 'requisitions', p_requisition_id,
      jsonb_build_object('collaborating_org_id', v_req.collaborating_org_id),
      jsonb_build_object('collaborating_org_id', null));
  return p_requisition_id;
end;
$$;
revoke execute on function public.requisition_remove_collaborator(uuid) from public;
grant  execute on function public.requisition_remove_collaborator(uuid) to authenticated, service_role;
comment on function public.requisition_remove_collaborator(uuid) is
  'Employer-side: revoke a collaborator from a requisition. The agency immediately loses visibility (RLS predicates re-evaluate).';
