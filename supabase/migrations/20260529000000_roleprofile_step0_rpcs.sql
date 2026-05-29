-- Role Profile detail page — Step 0 RPCs + permissions.
-- Three RPCs that the page's action buttons route through, plus two
-- new RBAC permissions they need.
--
-- The roles_catalog.status table-level enum (draft|active|archived) is
-- LEFT ALONE to avoid breaking existing tests. The 4-state model in the
-- prompt (draft|under_review|signed_off|archived) is honored at the
-- JSON-level field definition_json.identity_and_governance.version_status,
-- per PHASE0-SPEC §2.7. The page renders the JSON-level pill as the
-- primary status indicator.

insert into public.rbac_permissions (key, description) values
  ('role.signoff', 'Sign off a Role Profile version (transitions version_status under_review -> signed_off)'),
  ('role.export',  'Trigger Annex IV / DPIA / FRIA / validity-dossier export scoped to one role')
on conflict (key) do nothing;

insert into public.rbac_role_permissions (role_id, permission_id)
  select r.id, p.id
    from public.rbac_roles r cross join public.rbac_permissions p
    where r.org_id is null and r.key in ('people_ops_admin','org_admin')
      and p.key in ('role.signoff','role.export','modeling.read','modeling.write')
on conflict do nothing;

create or replace function public.rpc_use_role_for_requisition(
  p_role_id uuid, p_requisition_id uuid, p_rationale text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1);
        v_role_org uuid; v_req_org uuid;
begin
  if v_caller is null then raise exception 'rpc_use_role_for_requisition: not authenticated'; end if;
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'rpc_use_role_for_requisition: rationale >=20 chars (audit-grade attribution)';
  end if;
  select org_id into v_role_org from public.roles_catalog where id = p_role_id;
  select org_id into v_req_org from public.requisitions where id = p_requisition_id;
  if v_role_org is null and not exists (select 1 from public.roles_catalog where id = p_role_id) then
    raise exception 'rpc_use_role_for_requisition: role not found';
  end if;
  if v_req_org is null then raise exception 'rpc_use_role_for_requisition: requisition not found'; end if;
  if v_role_org is not null and v_role_org <> v_req_org then
    raise exception 'rpc_use_role_for_requisition: role is owned by a different org and is not a template';
  end if;
  if not public.has_permission(v_req_org, 'requisition.write') then
    raise exception 'rpc_use_role_for_requisition: requires requisition.write in the requisition''s org';
  end if;
  update public.requisitions set role_id = p_role_id, updated_at = now() where id = p_requisition_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_req_org, v_actor, 'role.used_for_requisition', 'requisitions', p_requisition_id,
      jsonb_build_object('role_id', p_role_id, 'rationale_excerpt', left(p_rationale, 200)));
  return p_requisition_id;
end;
$$;
revoke execute on function public.rpc_use_role_for_requisition(uuid, uuid, text) from public;
grant  execute on function public.rpc_use_role_for_requisition(uuid, uuid, text) to authenticated, service_role;

create or replace function public.rpc_role_sign_off(p_role_id uuid, p_rationale text)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1);
        v_org uuid; v_def jsonb; v_vstatus text;
begin
  if v_caller is null then raise exception 'rpc_role_sign_off: not authenticated'; end if;
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'rpc_role_sign_off: rationale >=20 chars (audit-grade attribution)';
  end if;
  select org_id, definition_json into v_org, v_def from public.roles_catalog where id = p_role_id;
  if v_org is null then
    raise exception 'rpc_role_sign_off: signing off a global template is an admin-only action; out of scope here';
  end if;
  if not public.has_permission(v_org, 'role.signoff') then
    raise exception 'rpc_role_sign_off: requires role.signoff in the role''s org';
  end if;
  v_vstatus := coalesce(v_def -> 'identity_and_governance' ->> 'version_status', 'draft');
  if v_vstatus <> 'under_review' then
    raise exception 'rpc_role_sign_off: only roles with version_status=under_review can be signed off (got %)', v_vstatus;
  end if;
  update public.roles_catalog set
    definition_json = jsonb_set(
      jsonb_set(definition_json,
        '{identity_and_governance,version_status}', '"signed_off"'::jsonb, true),
      '{identity_and_governance,signed_off_at}', to_jsonb(now()::text), true),
    signed_off_by = v_actor,
    signed_off_at = now(),
    status = case when status = 'draft' then 'active'::public.role_status else status end,
    updated_at = now()
  where id = p_role_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'role.signed_off', 'roles_catalog', p_role_id,
      jsonb_build_object('version_status', 'signed_off', 'rationale_excerpt', left(p_rationale, 200)));
  return p_role_id;
end;
$$;
revoke execute on function public.rpc_role_sign_off(uuid, text) from public;
grant  execute on function public.rpc_role_sign_off(uuid, text) to authenticated, service_role;

create or replace function public.rpc_role_export_assemble(
  p_role_id uuid, p_kind text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1);
        v_org uuid; v_artifact_id uuid; v_role_title text;
begin
  if v_caller is null then raise exception 'rpc_role_export_assemble: not authenticated'; end if;
  if p_kind not in ('annex_iv_technical_doc','dpia','fria','validity_dossier','fairness_audit_report') then
    raise exception 'rpc_role_export_assemble: invalid kind %', p_kind;
  end if;
  select org_id, title into v_org, v_role_title from public.roles_catalog where id = p_role_id;
  if v_org is null then raise exception 'rpc_role_export_assemble: role not found or is a global template (use org-level export)'; end if;
  if not public.has_permission(v_org, 'role.export') then
    raise exception 'rpc_role_export_assemble: requires role.export';
  end if;
  v_artifact_id := public.compliance_artifact_assemble(
    v_org, p_kind, 'role_' || p_role_id::text || '_' || p_kind || '_' || extract(epoch from now())::text,
    jsonb_build_object('role_id', p_role_id, 'role_title', v_role_title));
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'role.export_assembled', 'roles_catalog', p_role_id,
      jsonb_build_object('kind', p_kind, 'compliance_artifact_id', v_artifact_id));
  return v_artifact_id;
end;
$$;
revoke execute on function public.rpc_role_export_assemble(uuid, text) from public;
grant  execute on function public.rpc_role_export_assemble(uuid, text) to authenticated, service_role;
