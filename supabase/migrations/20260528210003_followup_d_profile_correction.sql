-- Step D — controlled escape hatch for the §A5 profiles append-only
-- trigger. Real operational need: a typo correction in traits_json that
-- doesn't justify a whole new profile version (which would carry a new
-- valid_from and break the re-fit time series). profile_correction_record
-- requires org.manage_all + a >=20-char reason; updates a single
-- whitelisted field atomically; bypasses the append-only trigger via a
-- session-local flag and writes a paired audit_log row with diff.

create or replace function public._profiles_append_only_guard() returns trigger
language plpgsql set search_path = '' as $$
declare immutable_fields text[] := array['org_id','person_id','source','traits_json','cognitive_json','values_json','derived_json','consent_id','valid_from'];
declare f text;
begin
  if coalesce(current_setting('app.profile_correction_in_progress', true), 'false') = 'true' then
    return new;
  end if;
  foreach f in array immutable_fields loop
    if (to_jsonb(old) -> f) is distinct from (to_jsonb(new) -> f) then
      raise exception 'profiles is append-only: cannot UPDATE column "%" on row %. Use profile_correction_record for an audited correction, or "close old + insert new" for a re-fit. SCIENCE-SPEC §6.', f, old.id;
    end if;
  end loop;
  return new;
end;
$$;

create or replace function public.profile_correction_record(
  p_profile_id uuid, p_field text, p_new_value jsonb, p_reason text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1);
        v_org uuid; v_before jsonb; v_after jsonb;
begin
  if v_caller is null then raise exception 'profile_correction_record: not authenticated'; end if;
  if p_reason is null or length(p_reason) < 20 then raise exception 'profile_correction_record: reason >=20 chars (audit-grade attribution)'; end if;
  if p_field not in ('traits_json','cognitive_json','values_json','derived_json') then
    raise exception 'profile_correction_record: field % is not correctable; allowed: traits_json|cognitive_json|values_json|derived_json', p_field;
  end if;
  select org_id, to_jsonb(p) into v_org, v_before from public.profiles p where p.id = p_profile_id;
  if v_org is null then raise exception 'profile_correction_record: profile not found'; end if;
  if not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'profile_correction_record: requires org.manage_all';
  end if;
  perform set_config('app.profile_correction_in_progress', 'true', true);
  execute format('update public.profiles set %I = $1, updated_at = now() where id = $2', p_field) using p_new_value, p_profile_id;
  perform set_config('app.profile_correction_in_progress', 'false', true);
  select to_jsonb(p) into v_after from public.profiles p where p.id = p_profile_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (v_org, v_actor, 'profile.corrected', 'profiles', p_profile_id,
      jsonb_build_object('field', p_field, 'before', v_before -> p_field, 'reason_excerpt', left(p_reason, 200)),
      jsonb_build_object('field', p_field, 'after',  v_after  -> p_field));
  return p_profile_id;
end;
$$;
revoke execute on function public.profile_correction_record(uuid, text, jsonb, text) from public;
grant  execute on function public.profile_correction_record(uuid, text, jsonb, text) to authenticated, service_role;
