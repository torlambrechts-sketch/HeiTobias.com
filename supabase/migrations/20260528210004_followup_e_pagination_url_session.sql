-- Step E — pagination on admin_overview members, URL validation on
-- org_settings_update, and org_for_current_user so the admin UI can
-- derive the active org from the signed-in user's memberships.

-- The old 1-arg admin_overview(uuid) is dropped so the new 4-arg
-- (uuid, int, int, int) form is unambiguous (Postgres can't resolve
-- two all-defaultable overloads).
drop function if exists public.admin_overview(uuid);

create or replace function public.admin_overview(
  p_org_id uuid, p_members_limit int default 100, p_members_offset int default 0, p_audit_limit int default 50
)
returns jsonb language plpgsql set search_path = '' stable security definer as $$
declare v_caller uuid := (select auth.uid()); v_settings jsonb; v_members jsonb; v_member_total bigint;
        v_consent_counts jsonb; v_module_toggles jsonb; v_audit jsonb; v_exports jsonb;
        v_limit int := least(coalesce(p_members_limit,100), 500);
        v_offset int := greatest(coalesce(p_members_offset,0), 0);
        v_audit_limit int := least(coalesce(p_audit_limit,50), 200);
begin
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'admin_overview: requires org.manage_all';
  end if;
  select jsonb_build_object('id', id, 'name', name, 'type', type, 'country', country, 'locale_default', locale_default, 'data_region', data_region, 'status', status, 'settings_json', settings_json)
    into v_settings from public.organizations where id = p_org_id;
  select count(*) into v_member_total from public.memberships where org_id = p_org_id;
  select coalesce(jsonb_agg(jsonb_build_object('membership_id', m.id, 'person_id', p.id, 'name', p.full_name, 'email', p.primary_email, 'status', m.status,
    'roles', (select jsonb_agg(r.key) from public.membership_roles mr join public.rbac_roles r on r.id = mr.rbac_role_id where mr.membership_id = m.id))
    order by p.full_name), '[]'::jsonb)
    into v_members from (
      select m.id, m.status, m.person_id from public.memberships m where m.org_id = p_org_id order by m.id limit v_limit offset v_offset
    ) m join public.people p on p.id = m.person_id;
  select coalesce(jsonb_object_agg(purpose, cnt), '{}'::jsonb) into v_consent_counts
    from (select purpose::text, count(*) cnt from public.consent_grants where granted_to_org_id = p_org_id and status='active' and revoked_at is null group by purpose) c;
  select coalesce(jsonb_agg(jsonb_build_object('key', module_key, 'enabled', enabled, 'config', config_json)), '[]'::jsonb)
    into v_module_toggles from public.org_modules where org_id = p_org_id;
  select coalesce(jsonb_agg(jsonb_build_object('action', action, 'entity_type', entity_type, 'at', at, 'actor_person_id', actor_person_id) order by at desc), '[]'::jsonb)
    into v_audit from (select action, entity_type, at, actor_person_id from public.audit_log where org_id = p_org_id order by at desc limit v_audit_limit) a;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'requested_at', requested_at, 'status', status) order by requested_at desc), '[]'::jsonb)
    into v_exports from public.data_export_requests where org_id = p_org_id;
  return jsonb_build_object(
    'organization', v_settings,
    'members', v_members, 'members_total', v_member_total, 'members_limit', v_limit, 'members_offset', v_offset,
    'consent_counts', v_consent_counts, 'module_toggles', v_module_toggles,
    'audit_recent', v_audit, 'data_exports', v_exports);
end;
$$;
revoke execute on function public.admin_overview(uuid, int, int, int) from public;
grant  execute on function public.admin_overview(uuid, int, int, int) to authenticated, service_role;

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
  if p_logo_url is not null and p_logo_url <> '' and p_logo_url !~* '^https://' then
    raise exception 'org_settings_update: logo_url must start with https:// (got %)', p_logo_url;
  end if;
  if p_dpa_url is not null and p_dpa_url <> '' and p_dpa_url !~* '^https://' then
    raise exception 'org_settings_update: dpa_url must start with https:// (got %)', p_dpa_url;
  end if;
  if p_accent_color is not null and p_accent_color <> '' and p_accent_color !~* '^#[0-9a-f]{6}$' then
    raise exception 'org_settings_update: accent_color must be #RRGGBB hex (got %)', p_accent_color;
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

create or replace function public.org_for_current_user()
returns jsonb language plpgsql set search_path = '' stable security definer as $$
declare v_caller uuid := (select auth.uid()); v_person uuid; v_rows jsonb;
begin
  if v_caller is null then return jsonb_build_object('rows', '[]'::jsonb); end if;
  select id into v_person from public.people where auth_user_id = v_caller limit 1;
  if v_person is null then return jsonb_build_object('rows', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(distinct jsonb_build_object(
    'org_id', o.id, 'name', o.name, 'type', o.type,
    'is_admin', public.has_permission(o.id, 'org.manage_all'))), '[]'::jsonb)
    into v_rows from public.organizations o
    join public.memberships m on m.org_id = o.id and m.person_id = v_person
    where m.status = 'active';
  return jsonb_build_object('person_id', v_person, 'rows', v_rows);
end;
$$;
revoke execute on function public.org_for_current_user() from public;
grant  execute on function public.org_for_current_user() to authenticated, service_role;
