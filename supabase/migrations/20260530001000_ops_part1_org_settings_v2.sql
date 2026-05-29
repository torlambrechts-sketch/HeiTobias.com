-- ITEM 2: org_settings_update_v2 — adds locale_default + writes
-- admin_decisions alongside audit_log. Retention preferences seed as
-- dev_stub (read-only surface) — never writable via this RPC because
-- retention policy is an operator item per the closure prompt.

create or replace function public.org_settings_update_v2(
  p_org_id uuid,
  p_display_name text default null,
  p_legal_name   text default null,
  p_accent_color text default null,
  p_logo_url     text default null,
  p_dpa_url      text default null,
  p_locale_default text default null,
  p_rationale    text default null
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_settings jsonb;
  v_before jsonb;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'org_settings_update_v2: rationale >=20 chars required';
  end if;
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'org_settings_update_v2: requires org.manage_all';
  end if;
  select settings_json, jsonb_build_object('name', name, 'locale_default', locale_default, 'settings_json', settings_json)
    into v_settings, v_before from public.organizations where id = p_org_id;
  if v_settings is null then v_settings := '{}'::jsonb; end if;
  if p_legal_name   is not null then v_settings := jsonb_set(v_settings, '{legal_name}',   to_jsonb(p_legal_name)); end if;
  if p_accent_color is not null then v_settings := jsonb_set(v_settings, '{accent_color}', to_jsonb(p_accent_color)); end if;
  if p_logo_url     is not null then v_settings := jsonb_set(v_settings, '{logo_url}',     to_jsonb(p_logo_url)); end if;
  if p_dpa_url      is not null then v_settings := jsonb_set(v_settings, '{dpa_url}',      to_jsonb(p_dpa_url)); end if;
  if not v_settings ? 'retention_preferences' then
    v_settings := jsonb_set(v_settings, '{retention_preferences}', jsonb_build_object(
      'hiring_records',  jsonb_build_object('validity_status','dev_stub','note','Requires policy decision per CLAUDE-CODE-CLOSURE-PROMPT operator items'),
      'pulse_data',      jsonb_build_object('validity_status','dev_stub','note','Requires policy decision'),
      'audit_log',       jsonb_build_object('validity_status','dev_stub','note','Requires policy decision'),
      'consent_records', jsonb_build_object('validity_status','dev_stub','note','Requires policy decision')
    ));
  end if;

  update public.organizations set
    name = coalesce(p_display_name, name),
    locale_default = coalesce(p_locale_default, locale_default),
    settings_json = v_settings,
    updated_at = now()
  where id = p_org_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (p_org_id, v_actor, 'org.settings_updated', 'organizations', p_org_id, v_before,
      jsonb_build_object('rationale_excerpt', left(p_rationale, 200),
                         'changed_fields', jsonb_strip_nulls(jsonb_build_object(
                           'display_name', p_display_name, 'legal_name', p_legal_name,
                           'accent_color', p_accent_color, 'logo_url', p_logo_url,
                           'dpa_url', p_dpa_url, 'locale_default', p_locale_default))));
  insert into public.admin_decisions (org_id, kind, decided_by, rationale, target_entity_type, target_entity_id, overrode_recommendation)
    values (p_org_id, 'org_settings_change', v_actor, p_rationale, 'organizations', p_org_id, true);
  return p_org_id;
end;
$$;
revoke execute on function public.org_settings_update_v2(uuid, text, text, text, text, text, text, text) from public;
grant  execute on function public.org_settings_update_v2(uuid, text, text, text, text, text, text, text) to authenticated, service_role;
