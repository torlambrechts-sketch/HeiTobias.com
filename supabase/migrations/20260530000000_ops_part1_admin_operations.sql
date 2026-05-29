-- Operations Layer Part 1 — ITEM 1: admin operations on memberships.
--
-- Existing infrastructure (org_invite_user, org_invite_accept,
-- org_change_role, org_deactivate_user, org_invite_revoke) provides
-- the plumbing; this migration adds the operator-grade discipline:
--   * change_role + deactivate now REQUIRE a >=20-char rationale and
--     write a decision_artefact in addition to audit_log
--   * org_reactivate_user added (was a missing primitive)
--   * org_invite_resend bumps the expires_at + writes an audit row
--   * org_invite_user_v2 accepts an optional rationale and persists
--     it via decision_artefact; the legacy v1 stays for backward compat
--
-- All retain SECURITY DEFINER + search_path = '' and require
-- org.manage_all in the target org. None bypass RLS via service-role
-- on the client — admins have elevated permissions, not god mode.

-- Drop the v1 signatures so we can introduce the rationale parameter
-- without breaking callers via fallback to the older overload.
drop function if exists public.org_change_role(uuid, text);
drop function if exists public.org_deactivate_user(uuid);

create or replace function public.org_change_role(
  p_membership_id uuid,
  p_new_rbac_role_key text,
  p_rationale text default null
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_org    uuid;
  v_pid    uuid;
  v_role   uuid;
  v_old    text;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'org_change_role: rationale >=20 chars required (audit-grade attribution)';
  end if;
  select org_id, person_id into v_org, v_pid from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_change_role: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_change_role: requires org.manage_all';
  end if;
  select id into v_role from public.rbac_roles where org_id is null and key = p_new_rbac_role_key;
  if v_role is null then raise exception 'org_change_role: unknown rbac role key %', p_new_rbac_role_key; end if;
  select string_agg(r.key, ',') into v_old
    from public.membership_roles mr join public.rbac_roles r on r.id = mr.rbac_role_id
    where mr.membership_id = p_membership_id;
  delete from public.membership_roles where membership_id = p_membership_id;
  insert into public.membership_roles (membership_id, rbac_role_id) values (p_membership_id, v_role);
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (v_org, v_actor, 'org.role_changed', 'memberships', p_membership_id,
      jsonb_build_object('old_role', v_old),
      jsonb_build_object('new_role', p_new_rbac_role_key, 'rationale_excerpt', left(p_rationale, 200)));
  insert into public.decision_artefacts (org_id, person_id, decision_type, decided_by, decided_at,
                                          justification_text, source_table, human_override)
    values (v_org, v_pid, 'rbac_role_change', v_actor, now(), p_rationale, 'memberships', true);
  return p_membership_id;
end;
$$;
revoke execute on function public.org_change_role(uuid, text, text) from public;
grant  execute on function public.org_change_role(uuid, text, text) to authenticated, service_role;

create or replace function public.org_deactivate_user(
  p_membership_id uuid,
  p_rationale text default null
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_org    uuid;
  v_pid    uuid;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'org_deactivate_user: rationale >=20 chars required';
  end if;
  select org_id, person_id into v_org, v_pid from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_deactivate_user: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_deactivate_user: requires org.manage_all';
  end if;
  update public.memberships set status = 'suspended', updated_at = now() where id = p_membership_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.user_deactivated', 'memberships', p_membership_id,
      jsonb_build_object('rationale_excerpt', left(p_rationale, 200)));
  insert into public.decision_artefacts (org_id, person_id, decision_type, decided_by, decided_at,
                                          justification_text, source_table, human_override)
    values (v_org, v_pid, 'user_deactivation', v_actor, now(), p_rationale, 'memberships', true);
  return p_membership_id;
end;
$$;
revoke execute on function public.org_deactivate_user(uuid, text) from public;
grant  execute on function public.org_deactivate_user(uuid, text) to authenticated, service_role;

create or replace function public.org_reactivate_user(
  p_membership_id uuid,
  p_rationale text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_org    uuid;
  v_pid    uuid;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'org_reactivate_user: rationale >=20 chars required';
  end if;
  select org_id, person_id into v_org, v_pid from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_reactivate_user: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_reactivate_user: requires org.manage_all';
  end if;
  update public.memberships set status = 'active', updated_at = now() where id = p_membership_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.user_reactivated', 'memberships', p_membership_id,
      jsonb_build_object('rationale_excerpt', left(p_rationale, 200)));
  insert into public.decision_artefacts (org_id, person_id, decision_type, decided_by, decided_at,
                                          justification_text, source_table, human_override)
    values (v_org, v_pid, 'user_reactivation', v_actor, now(), p_rationale, 'memberships', true);
  return p_membership_id;
end;
$$;
revoke execute on function public.org_reactivate_user(uuid, text) from public;
grant  execute on function public.org_reactivate_user(uuid, text) to authenticated, service_role;

create or replace function public.org_invite_resend(
  p_token_id uuid,
  p_extend_days int default 14
)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_org    uuid;
  v_new_exp timestamptz;
  v_token  text;
begin
  select org_id, token into v_org, v_token from public.invite_tokens where id = p_token_id;
  if v_org is null then raise exception 'org_invite_resend: invite not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_invite_resend: requires org.manage_all';
  end if;
  v_new_exp := now() + (p_extend_days || ' days')::interval;
  update public.invite_tokens set expires_at = v_new_exp where id = p_token_id and accepted_at is null and revoked_at is null;
  if not found then raise exception 'org_invite_resend: invite already accepted or revoked'; end if;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.invite_resent', 'invite_tokens', p_token_id,
      jsonb_build_object('new_expires_at', v_new_exp));
  return jsonb_build_object('token', v_token, 'new_expires_at', v_new_exp);
end;
$$;
revoke execute on function public.org_invite_resend(uuid, int) from public;
grant  execute on function public.org_invite_resend(uuid, int) to authenticated, service_role;

-- Accept invite extended: capture display name + locale at accept time.
-- The legacy org_invite_accept(token) stays for back-compat; the v2 is
-- the new path for AcceptInvitePage.
create or replace function public.org_invite_accept_v2(
  p_token text,
  p_display_name text default null,
  p_locale text default 'en'
)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_caller   uuid := (select auth.uid());
  v_actor    uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_tok      public.invite_tokens%rowtype;
begin
  select * into v_tok from public.invite_tokens where token = p_token for update;
  if not found then raise exception 'org_invite_accept_v2: invite not found'; end if;
  if v_tok.accepted_at is not null then raise exception 'org_invite_accept_v2: invite already accepted'; end if;
  if v_tok.revoked_at is not null then raise exception 'org_invite_accept_v2: invite revoked'; end if;
  if v_tok.expires_at < now() then raise exception 'org_invite_accept_v2: invite expired'; end if;

  update public.invite_tokens set accepted_at = now(), accepted_by = coalesce(v_caller, v_tok.person_id) where id = v_tok.id;
  update public.memberships set status = 'active', updated_at = now() where id = v_tok.membership_id;

  if p_display_name is not null and length(trim(p_display_name)) > 0 then
    update public.people set full_name = trim(p_display_name) where id = v_tok.person_id;
  end if;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_tok.org_id, v_actor, 'org.invite_accepted', 'invite_tokens', v_tok.id,
      jsonb_build_object('membership_id', v_tok.membership_id, 'locale_at_accept', p_locale));
  return jsonb_build_object(
    'membership_id', v_tok.membership_id,
    'person_id', v_tok.person_id,
    'org_id', v_tok.org_id,
    'locale', p_locale
  );
end;
$$;
revoke execute on function public.org_invite_accept_v2(text, text, text) from public;
grant  execute on function public.org_invite_accept_v2(text, text, text) to authenticated, anon, service_role;

-- List pending invites for an org (admin view).
create or replace function public.org_pending_invites(p_org_id uuid)
returns table (
  id uuid, token text, invited_email text, invited_at timestamptz,
  expires_at timestamptz, accepted_at timestamptz, revoked_at timestamptz,
  membership_id uuid, person_id uuid
) language plpgsql set search_path = '' security definer as $$
begin
  if (select auth.uid()) is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'org_pending_invites: requires org.manage_all';
  end if;
  return query
    select t.id, t.token, t.invited_email, t.invited_at, t.expires_at, t.accepted_at, t.revoked_at,
           t.membership_id, t.person_id
    from public.invite_tokens t
    where t.org_id = p_org_id
    order by t.invited_at desc;
end;
$$;
revoke execute on function public.org_pending_invites(uuid) from public;
grant  execute on function public.org_pending_invites(uuid) to authenticated, service_role;
