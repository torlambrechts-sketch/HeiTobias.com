-- Step B — multi-role membership: attach/detach primitives. Both
-- org.manage_all gated + audited. Refuses to detach the last remaining
-- role (use org_deactivate_user instead).

create or replace function public.org_role_attach(p_membership_id uuid, p_rbac_role_key text)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1);
        v_org uuid; v_role uuid;
begin
  select org_id into v_org from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_role_attach: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_role_attach: requires org.manage_all';
  end if;
  select id into v_role from public.rbac_roles where org_id is null and key = p_rbac_role_key;
  if v_role is null then raise exception 'org_role_attach: unknown rbac role key %', p_rbac_role_key; end if;
  insert into public.membership_roles (membership_id, rbac_role_id) values (p_membership_id, v_role) on conflict do nothing;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.role_attached', 'memberships', p_membership_id, jsonb_build_object('attached_role', p_rbac_role_key));
  return p_membership_id;
end;
$$;
revoke execute on function public.org_role_attach(uuid, text) from public;
grant  execute on function public.org_role_attach(uuid, text) to authenticated, service_role;

create or replace function public.org_role_detach(p_membership_id uuid, p_rbac_role_key text)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1);
        v_org uuid; v_role uuid; v_remaining int;
begin
  select org_id into v_org from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_role_detach: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_role_detach: requires org.manage_all';
  end if;
  select id into v_role from public.rbac_roles where org_id is null and key = p_rbac_role_key;
  if v_role is null then raise exception 'org_role_detach: unknown rbac role key %', p_rbac_role_key; end if;
  select count(*) into v_remaining from public.membership_roles where membership_id = p_membership_id and rbac_role_id <> v_role;
  if v_remaining = 0 then
    raise exception 'org_role_detach: cannot detach the last role on a membership (use org_deactivate_user instead)';
  end if;
  delete from public.membership_roles where membership_id = p_membership_id and rbac_role_id = v_role;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.role_detached', 'memberships', p_membership_id, jsonb_build_object('detached_role', p_rbac_role_key));
  return p_membership_id;
end;
$$;
revoke execute on function public.org_role_detach(uuid, text) from public;
grant  execute on function public.org_role_detach(uuid, text) to authenticated, service_role;
