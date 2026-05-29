-- ITEM 4 — rpc_requisition_attach_role.
--
-- Attaches a signed-off role version to an existing requisition.
-- This is the bridge between the new Team-Based Role Definition output
-- (CP3.4 produces a versioned role) and the existing requisition
-- pipeline.
--
-- Guards:
--   * Caller must hold requisition.write in the requisition's org
--   * Rationale >= 20 chars (audit-grade attribution)
--   * Cannot attach a template (is_template=true) — only versioned
--     instances; templates must go through role_instantiate_from_template
--     or a team-based definition run first
--   * Role's org_id must match requisition.org_id (unless role is a
--     global template, which the previous guard already blocked)
--
-- Writes a 'requisition.role_attached' audit row with before/after
-- (old vs new role_id) and a 200-char rationale excerpt.

create or replace function public.rpc_requisition_attach_role(
  p_requisition_id uuid,
  p_role_id uuid,
  p_rationale text
)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_caller   uuid := (select auth.uid());
  v_actor    uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_req      public.requisitions%rowtype;
  v_role     public.roles_catalog%rowtype;
  v_old_role uuid;
begin
  if v_caller is null then raise exception 'rpc_requisition_attach_role: not authenticated'; end if;
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'rpc_requisition_attach_role: rationale >=20 chars';
  end if;

  select * into v_req from public.requisitions where id = p_requisition_id for update;
  if not found then raise exception 'rpc_requisition_attach_role: requisition not found'; end if;

  if not public.has_permission(v_req.org_id, 'requisition.write') then
    raise exception 'rpc_requisition_attach_role: requires requisition.write in the requisition''s org';
  end if;

  select * into v_role from public.roles_catalog where id = p_role_id;
  if not found then raise exception 'rpc_requisition_attach_role: role not found'; end if;
  if v_role.is_template then
    raise exception 'rpc_requisition_attach_role: cannot attach a template; instantiate it first (role_instantiate_from_template or a team-based definition run)';
  end if;
  if v_role.org_id is not null and v_role.org_id <> v_req.org_id then
    raise exception 'rpc_requisition_attach_role: role belongs to a different org than the requisition';
  end if;

  v_old_role := v_req.role_id;
  if v_old_role = p_role_id then
    raise exception 'rpc_requisition_attach_role: role % is already attached to this requisition', p_role_id;
  end if;

  update public.requisitions set
    role_id = p_role_id,
    updated_at = now()
  where id = p_requisition_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (v_req.org_id, v_actor, 'requisition.role_attached', 'requisitions', p_requisition_id,
            jsonb_build_object('role_id', v_old_role),
            jsonb_build_object('role_id', p_role_id, 'role_version', v_role.version,
                               'role_title', v_role.title, 'rationale_excerpt', left(p_rationale, 200)));

  return jsonb_build_object(
    'requisition_id', p_requisition_id,
    'old_role_id', v_old_role,
    'new_role_id', p_role_id,
    'role_version', v_role.version
  );
end;
$$;
revoke execute on function public.rpc_requisition_attach_role(uuid, uuid, text) from public;
grant  execute on function public.rpc_requisition_attach_role(uuid, uuid, text) to authenticated, service_role;
