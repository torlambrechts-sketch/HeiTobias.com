-- Gap-closure step 5: take-token brand resolver.
-- Returns the inviting org's display brand (name + accent + logo + locale)
-- for the candidate /take/<token> flow. Anon-callable; only non-personal
-- org info is returned.

create or replace function public.assessment_take_brand(p_token text)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare v_org uuid; v_name text; v_locale text; v_settings jsonb;
begin
  select i.org_id into v_org from public.assessment_invites i where i.token = p_token;
  if v_org is null then return jsonb_build_object('org_name', null); end if;
  select name, locale_default, settings_json into v_name, v_locale, v_settings
    from public.organizations where id = v_org;
  return jsonb_build_object(
    'org_id', v_org,
    'org_name', v_name,
    'locale_default', v_locale,
    'accent_color', v_settings->>'accent_color',
    'logo_url', v_settings->>'logo_url'
  );
end;
$$;
revoke execute on function public.assessment_take_brand(text) from public;
grant  execute on function public.assessment_take_brand(text) to authenticated, anon, service_role;
