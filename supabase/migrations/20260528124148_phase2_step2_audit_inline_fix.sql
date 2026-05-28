-- portability_grant + consent_revoke are anon-callable via the consent token.
-- The candidate doesn't have org.read in the employer org, so audit_log_event
-- (which enforces that permission) rejects them. Instead, write directly to
-- audit_log from the SECURITY DEFINER function — bypasses the RLS gate that
-- only existed to keep arbitrary authenticated callers from forging actions
-- on other orgs. Inserting from a controlled, named function preserves the
-- audit trail intent.

create or replace function public.portability_grant(
  p_token text, p_employer_org_id uuid, p_scope_json jsonb default '{}'::jsonb
)
returns uuid
language plpgsql set search_path = '' security definer
as $$
declare
  v_person_id uuid; v_org public.organizations%rowtype; v_existing uuid; v_id uuid;
begin
  if p_token is null or length(p_token) = 0 then raise exception 'portability_grant: token required'; end if;
  select (r).person_id into v_person_id from public._consent_token_resolve(p_token) r;
  if v_person_id is null then raise exception 'portability_grant: invalid or expired token'; end if;
  select * into v_org from public.organizations where id = p_employer_org_id;
  if not found then raise exception 'portability_grant: employer org not found'; end if;
  select id into v_existing from public.consent_grants
    where person_id = v_person_id and granted_to_org_id = p_employer_org_id
      and purpose = 'profile_portability' and status = 'active'
      and revoked_at is null and (expires_at is null or expires_at > now())
    limit 1;
  if v_existing is not null then return v_existing; end if;
  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis, scope_json)
    values (v_person_id, p_employer_org_id, 'profile_portability', 'consent', coalesce(p_scope_json,'{}'::jsonb))
    returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_employer_org_id, v_person_id, 'consent.granted', 'consent_grants', v_id,
      jsonb_build_object('purpose','profile_portability','person_id',v_person_id,'source','candidate_dashboard'));
  return v_id;
end;
$$;

create or replace function public.consent_revoke(p_token text, p_consent_id uuid)
returns uuid
language plpgsql set search_path = '' security definer
as $$
declare v_person_id uuid; v_grant public.consent_grants%rowtype;
begin
  if p_token is null or length(p_token) = 0 then raise exception 'consent_revoke: token required'; end if;
  select (r).person_id into v_person_id from public._consent_token_resolve(p_token) r;
  if v_person_id is null then raise exception 'consent_revoke: invalid or expired token'; end if;
  select * into v_grant from public.consent_grants where id = p_consent_id;
  if not found then raise exception 'consent_revoke: consent not found'; end if;
  if v_grant.person_id <> v_person_id then raise exception 'consent_revoke: caller is not the data subject for this consent'; end if;
  if v_grant.status = 'revoked' then return p_consent_id; end if;
  update public.consent_grants set status='revoked', revoked_at=now(), updated_at=now() where id=p_consent_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (v_grant.granted_to_org_id, v_person_id, 'consent.revoked', 'consent_grants', p_consent_id,
      jsonb_build_object('status','active'), jsonb_build_object('status','revoked','source','candidate_dashboard'));
  return p_consent_id;
end;
$$;
