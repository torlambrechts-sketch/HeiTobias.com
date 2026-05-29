-- Gap-closure step 4: consent_revoke_by_purpose (self-service revoke).
create or replace function public.consent_revoke_by_purpose(
  p_purpose text,
  p_granted_to_org_id uuid
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_consent uuid;
begin
  if v_caller is null or v_actor is null then
    raise exception 'consent_revoke_by_purpose: not authenticated';
  end if;
  select id into v_consent from public.consent_grants
    where person_id = v_actor
      and purpose = p_purpose::public.consent_purpose
      and granted_to_org_id = p_granted_to_org_id
      and revoked_at is null
    order by created_at desc
    limit 1;
  if v_consent is null then
    raise exception 'consent_revoke_by_purpose: no active grant for purpose=% / org=%', p_purpose, p_granted_to_org_id;
  end if;
  update public.consent_grants set revoked_at = now() where id = v_consent;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_granted_to_org_id, v_actor, 'consent.revoked_by_subject', 'consent_grants', v_consent,
            jsonb_build_object('purpose', p_purpose, 'method', 'self_view'));
  return v_consent;
end;
$$;
revoke execute on function public.consent_revoke_by_purpose(text, uuid) from public;
grant  execute on function public.consent_revoke_by_purpose(text, uuid) to authenticated, service_role;
