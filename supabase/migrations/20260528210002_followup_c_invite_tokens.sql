-- Step C — magic-link invite + accept flow. org_invite_user mints an
-- invite_tokens row alongside the membership. /admin/accept-invite/:token
-- reads org_invite_state (anon-friendly, token-only), the recipient signs
-- in via Supabase Auth, calls org_invite_accept(token) which verifies the
-- signed-in email matches the invited email + flips memberships.status
-- to 'active'. Admins can copy invite links via invite_token_for and
-- revoke via org_invite_revoke.

create table public.invite_tokens (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  person_id       uuid not null references public.people(id),
  membership_id   uuid not null references public.memberships(id) on delete cascade,
  token           text not null unique,
  invited_email   text not null,
  invited_by      uuid references public.people(id),
  invited_at      timestamptz not null default now(),
  expires_at      timestamptz not null default (now() + interval '14 days'),
  accepted_at     timestamptz,
  accepted_by     uuid references public.people(id),
  revoked_at      timestamptz
);
create index invite_tokens_org_idx on public.invite_tokens (org_id);
create index invite_tokens_token_lookup_idx on public.invite_tokens (token) where accepted_at is null and revoked_at is null;
create trigger trg_audit_invite_tokens after insert or update or delete on public.invite_tokens for each row execute function public._audit_row();
alter table public.invite_tokens enable row level security;
alter table public.invite_tokens force row level security;
create policy invite_tokens_select on public.invite_tokens for select to authenticated using (public.has_permission(org_id, 'org.manage_all'));
create policy invite_tokens_admin_write on public.invite_tokens for all to authenticated
  using (public.has_permission(org_id, 'org.manage_all'))
  with check (public.has_permission(org_id, 'org.manage_all'));

create or replace function public.org_invite_user(
  p_org_id uuid, p_email text, p_rbac_role_key text, p_full_name text default null
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1);
        v_person uuid; v_membership uuid; v_role uuid; v_existing_status public.membership_status; v_token text;
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
  select id, status into v_membership, v_existing_status from public.memberships where org_id = p_org_id and person_id = v_person limit 1;
  if v_membership is null then
    insert into public.memberships (org_id, person_id, status) values (p_org_id, v_person, 'invited') returning id into v_membership;
  elsif v_existing_status = 'removed' then
    update public.memberships set status = 'invited' where id = v_membership;
  end if;
  insert into public.membership_roles (membership_id, rbac_role_id) values (v_membership, v_role) on conflict do nothing;
  if not exists (select 1 from public.invite_tokens where membership_id = v_membership
                  and accepted_at is null and revoked_at is null and expires_at > now()) then
    v_token := encode(extensions.gen_random_bytes(32), 'base64');
    v_token := replace(replace(replace(v_token, '+', '-'), '/', '_'), '=', '');
    insert into public.invite_tokens (org_id, person_id, membership_id, token, invited_email, invited_by)
      values (p_org_id, v_person, v_membership, v_token, lower(p_email), v_actor);
  end if;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'org.user_invited', 'memberships', v_membership,
      jsonb_build_object('email', p_email, 'role', p_rbac_role_key, 'person_id', v_person,
                         'prior_status', v_existing_status, 'created_new_membership', (v_existing_status is null)));
  return v_membership;
end;
$$;
revoke execute on function public.org_invite_user(uuid, text, text, text) from public;
grant  execute on function public.org_invite_user(uuid, text, text, text) to authenticated, service_role;

create or replace function public.invite_token_for(p_membership_id uuid)
returns jsonb language plpgsql set search_path = '' stable security definer as $$
declare v_caller uuid := (select auth.uid()); v_org uuid; v_row record;
begin
  select org_id into v_org from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'invite_token_for: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'invite_token_for: requires org.manage_all';
  end if;
  select id, token, invited_email, expires_at, accepted_at, revoked_at into v_row
    from public.invite_tokens where membership_id = p_membership_id order by invited_at desc limit 1;
  if v_row is null then return null; end if;
  return jsonb_build_object('id', v_row.id, 'token', v_row.token, 'invited_email', v_row.invited_email,
    'expires_at', v_row.expires_at, 'accepted_at', v_row.accepted_at, 'revoked_at', v_row.revoked_at);
end;
$$;
revoke execute on function public.invite_token_for(uuid) from public;
grant  execute on function public.invite_token_for(uuid) to authenticated, service_role;

create or replace function public.org_invite_state(p_token text)
returns jsonb language plpgsql set search_path = '' stable security definer as $$
declare v_row record;
begin
  if p_token is null or length(p_token) < 16 then raise exception 'org_invite_state: invalid token'; end if;
  select t.*, o.name as org_name, o.settings_json as org_settings into v_row
    from public.invite_tokens t
    join public.organizations o on o.id = t.org_id
    where t.token = p_token and t.accepted_at is null and t.revoked_at is null and t.expires_at > now();
  if v_row is null then raise exception 'org_invite_state: token not found or expired/used'; end if;
  return jsonb_build_object('invited_email', v_row.invited_email, 'org_id', v_row.org_id,
    'org_name', v_row.org_name, 'org_settings', v_row.org_settings,
    'membership_id', v_row.membership_id, 'expires_at', v_row.expires_at);
end;
$$;
revoke execute on function public.org_invite_state(text) from public;
grant  execute on function public.org_invite_state(text) to authenticated, anon, service_role;

create or replace function public.org_invite_accept(p_token text)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_caller_email text; v_token record;
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
  update public.people set auth_user_id = v_caller where id = v_token.person_id and (auth_user_id is null or auth_user_id = v_caller);
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

create or replace function public.org_invite_revoke(p_token_id uuid)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_org uuid;
begin
  select org_id into v_org from public.invite_tokens where id = p_token_id;
  if v_org is null then raise exception 'org_invite_revoke: token not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_invite_revoke: requires org.manage_all';
  end if;
  update public.invite_tokens set revoked_at = now() where id = p_token_id and accepted_at is null;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.invite_revoked', 'invite_tokens', p_token_id, '{}'::jsonb);
  return p_token_id;
end;
$$;
revoke execute on function public.org_invite_revoke(uuid) from public;
grant  execute on function public.org_invite_revoke(uuid) to authenticated, service_role;
