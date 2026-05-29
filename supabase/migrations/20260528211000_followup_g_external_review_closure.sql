-- Step G — external-review closure.
-- org_invite_accept tightened: refuse if the person row already has an
-- auth_user_id pointing at a different account. The email-match check
-- already prevents most cases, but a stale person row (created from a
-- candidate flow under a different auth account) could slip through
-- the previous "auth_user_id is null or matches" predicate. A senior
-- reviewer flagged this; the new predicate is "must be null or must
-- match caller exactly".

create or replace function public.org_invite_accept(p_token text)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_caller_email text; v_token record; v_existing_auth uuid;
begin
  if v_caller is null then raise exception 'org_invite_accept: not authenticated'; end if;
  select email into v_caller_email from auth.users where id = v_caller;
  if v_caller_email is null then raise exception 'org_invite_accept: no email on auth user'; end if;
  select * into v_token from public.invite_tokens
    where token = p_token and accepted_at is null and revoked_at is null and expires_at > now() for update;
  if v_token is null then raise exception 'org_invite_accept: token not found, already used, or expired'; end if;
  if lower(v_caller_email) <> lower(v_token.invited_email) then
    raise exception 'org_invite_accept: signed-in email does not match the invited email';
  end if;

  select auth_user_id into v_existing_auth from public.people where id = v_token.person_id;
  if v_existing_auth is not null and v_existing_auth <> v_caller then
    raise exception 'org_invite_accept: this email is already linked to a different account; contact an admin';
  end if;

  update public.people set auth_user_id = v_caller where id = v_token.person_id and auth_user_id is null;
  update public.memberships set status = 'active' where id = v_token.membership_id;
  update public.invite_tokens set accepted_at = now(), accepted_by = v_token.person_id where id = v_token.id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_token.org_id, v_token.person_id, 'org.invite_accepted', 'memberships', v_token.membership_id,
      jsonb_build_object('token_id', v_token.id, 'invited_email', v_token.invited_email));
  return jsonb_build_object('membership_id', v_token.membership_id, 'org_id', v_token.org_id, 'person_id', v_token.person_id, 'status', 'active');
end;
$$;
revoke execute on function public.org_invite_accept(text) from public;
grant  execute on function public.org_invite_accept(text) to authenticated, service_role;
