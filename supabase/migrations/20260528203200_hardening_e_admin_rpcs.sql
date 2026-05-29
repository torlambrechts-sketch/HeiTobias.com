-- hardening_e_admin_rpcs — §E Workspace Admin scope. Strict scope:
-- org profile, user management (invite/role-change/deactivate),
-- compliance read view (consent counts + audit + module toggles),
-- data-export request. Admin-RBAC gated; audited.

create table public.data_export_requests (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  requested_by    uuid not null references public.people(id),
  requested_at    timestamptz not null default now(),
  status          text not null default 'pending' check (status in ('pending','in_progress','delivered','rejected')),
  scope_json      jsonb not null default '{}'::jsonb,
  notes           text,
  fulfilled_at    timestamptz,
  fulfilled_by    uuid references public.people(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create trigger trg_touch_data_export_requests before update on public.data_export_requests for each row execute function public.set_updated_at();
create trigger trg_audit_data_export_requests after insert or update or delete on public.data_export_requests for each row execute function public._audit_row();
alter table public.data_export_requests enable row level security;
alter table public.data_export_requests force row level security;
create policy data_export_requests_select on public.data_export_requests for select to authenticated using (public.has_permission(org_id, 'org.manage_all'));
create policy data_export_requests_write  on public.data_export_requests for all to authenticated
  using (public.has_permission(org_id, 'org.manage_all'))
  with check (public.has_permission(org_id, 'org.manage_all'));

create or replace function public.org_settings_update(
  p_org_id uuid, p_display_name text default null, p_legal_name text default null,
  p_accent_color text default null, p_logo_url text default null, p_dpa_url text default null
)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_new jsonb;
begin
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'org_settings_update: requires org.manage_all';
  end if;
  update public.organizations set
    name = coalesce(p_display_name, name),
    settings_json = settings_json
      || (case when p_legal_name   is not null then jsonb_build_object('legal_name', p_legal_name) else '{}'::jsonb end)
      || (case when p_accent_color is not null then jsonb_build_object('accent_color', p_accent_color) else '{}'::jsonb end)
      || (case when p_logo_url     is not null then jsonb_build_object('logo_url', p_logo_url) else '{}'::jsonb end)
      || (case when p_dpa_url      is not null then jsonb_build_object('dpa_url', p_dpa_url) else '{}'::jsonb end),
    updated_at = now()
  where id = p_org_id
  returning jsonb_build_object('id', id, 'name', name, 'settings', settings_json) into v_new;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'org.settings_updated', 'organizations', p_org_id, v_new);
  return v_new;
end;
$$;
revoke execute on function public.org_settings_update(uuid, text, text, text, text, text) from public;
grant  execute on function public.org_settings_update(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function public.org_invite_user(
  p_org_id uuid, p_email text, p_rbac_role_key text, p_full_name text default null
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1);
        v_person uuid; v_membership uuid; v_role uuid;
begin
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'org_invite_user: requires org.manage_all';
  end if;
  if p_email is null or position('@' in p_email) < 2 then
    raise exception 'org_invite_user: invalid email';
  end if;
  select id into v_role from public.rbac_roles where org_id is null and key = p_rbac_role_key;
  if v_role is null then raise exception 'org_invite_user: unknown rbac role key %', p_rbac_role_key; end if;
  select id into v_person from public.people where primary_email = lower(p_email) limit 1;
  if v_person is null then
    insert into public.people (full_name, primary_email) values (coalesce(p_full_name, split_part(p_email,'@',1)), lower(p_email)) returning id into v_person;
  end if;
  select id into v_membership from public.memberships where org_id = p_org_id and person_id = v_person limit 1;
  if v_membership is null then
    insert into public.memberships (org_id, person_id, status) values (p_org_id, v_person, 'invited') returning id into v_membership;
  else
    update public.memberships set status = 'invited' where id = v_membership and status <> 'invited';
  end if;
  insert into public.membership_roles (membership_id, rbac_role_id) values (v_membership, v_role) on conflict do nothing;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'org.user_invited', 'memberships', v_membership,
      jsonb_build_object('email', p_email, 'role', p_rbac_role_key, 'person_id', v_person));
  return v_membership;
end;
$$;
revoke execute on function public.org_invite_user(uuid, text, text, text) from public;
grant  execute on function public.org_invite_user(uuid, text, text, text) to authenticated, service_role;

create or replace function public.org_change_role(p_membership_id uuid, p_new_rbac_role_key text)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_org uuid; v_role uuid;
begin
  select org_id into v_org from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_change_role: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_change_role: requires org.manage_all';
  end if;
  select id into v_role from public.rbac_roles where org_id is null and key = p_new_rbac_role_key;
  if v_role is null then raise exception 'org_change_role: unknown rbac role key %', p_new_rbac_role_key; end if;
  delete from public.membership_roles where membership_id = p_membership_id;
  insert into public.membership_roles (membership_id, rbac_role_id) values (p_membership_id, v_role);
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.role_changed', 'memberships', p_membership_id, jsonb_build_object('new_role', p_new_rbac_role_key));
  return p_membership_id;
end;
$$;
revoke execute on function public.org_change_role(uuid, text) from public;
grant  execute on function public.org_change_role(uuid, text) to authenticated, service_role;

create or replace function public.org_deactivate_user(p_membership_id uuid)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_org uuid;
begin
  select org_id into v_org from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_deactivate_user: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_deactivate_user: requires org.manage_all';
  end if;
  update public.memberships set status = 'suspended' where id = p_membership_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.user_deactivated', 'memberships', p_membership_id, jsonb_build_object('status', 'suspended'));
  return p_membership_id;
end;
$$;
revoke execute on function public.org_deactivate_user(uuid) from public;
grant  execute on function public.org_deactivate_user(uuid) to authenticated, service_role;

create or replace function public.data_export_request_create(p_org_id uuid, p_scope jsonb default '{}'::jsonb, p_notes text default null)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_id uuid;
begin
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'data_export_request_create: requires org.manage_all';
  end if;
  if v_actor is null then raise exception 'data_export_request_create: no person row for caller'; end if;
  insert into public.data_export_requests (org_id, requested_by, scope_json, notes) values (p_org_id, v_actor, coalesce(p_scope,'{}'::jsonb), p_notes) returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'data_export.requested', 'data_export_requests', v_id, jsonb_build_object('scope', p_scope));
  return v_id;
end;
$$;
revoke execute on function public.data_export_request_create(uuid, jsonb, text) from public;
grant  execute on function public.data_export_request_create(uuid, jsonb, text) to authenticated, service_role;

create or replace function public.admin_overview(p_org_id uuid)
returns jsonb language plpgsql set search_path = '' stable security definer as $$
declare v_caller uuid := (select auth.uid()); v_settings jsonb; v_members jsonb; v_consent_counts jsonb; v_module_toggles jsonb; v_audit jsonb; v_exports jsonb;
begin
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'admin_overview: requires org.manage_all';
  end if;
  select jsonb_build_object('id', id, 'name', name, 'type', type, 'country', country, 'locale_default', locale_default, 'data_region', data_region, 'status', status, 'settings_json', settings_json)
    into v_settings from public.organizations where id = p_org_id;
  select coalesce(jsonb_agg(jsonb_build_object('membership_id', m.id, 'person_id', p.id, 'name', p.full_name, 'email', p.primary_email, 'status', m.status,
    'roles', (select jsonb_agg(r.key) from public.membership_roles mr join public.rbac_roles r on r.id = mr.rbac_role_id where mr.membership_id = m.id))
    order by p.full_name), '[]'::jsonb)
    into v_members from public.memberships m join public.people p on p.id = m.person_id where m.org_id = p_org_id;
  select coalesce(jsonb_object_agg(purpose, cnt), '{}'::jsonb) into v_consent_counts
    from (select purpose::text, count(*) cnt from public.consent_grants where granted_to_org_id = p_org_id and status='active' and revoked_at is null group by purpose) c;
  select coalesce(jsonb_agg(jsonb_build_object('key', module_key, 'enabled', enabled, 'config', config_json)), '[]'::jsonb)
    into v_module_toggles from public.org_modules where org_id = p_org_id;
  select coalesce(jsonb_agg(jsonb_build_object('action', action, 'entity_type', entity_type, 'at', at, 'actor_person_id', actor_person_id) order by at desc), '[]'::jsonb)
    into v_audit from (select action, entity_type, at, actor_person_id from public.audit_log where org_id = p_org_id order by at desc limit 50) a;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'requested_at', requested_at, 'status', status) order by requested_at desc), '[]'::jsonb)
    into v_exports from public.data_export_requests where org_id = p_org_id;
  return jsonb_build_object('organization', v_settings, 'members', v_members, 'consent_counts', v_consent_counts,
    'module_toggles', v_module_toggles, 'audit_recent', v_audit, 'data_exports', v_exports);
end;
$$;
revoke execute on function public.admin_overview(uuid) from public;
grant  execute on function public.admin_overview(uuid) to authenticated, service_role;
