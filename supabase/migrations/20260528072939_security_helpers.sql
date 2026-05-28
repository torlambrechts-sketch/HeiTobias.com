-- security_helpers — the four functions every RLS policy will call.
--
-- All are SECURITY DEFINER + STABLE + search_path = '' so a malicious schema earlier
-- on the path cannot shadow our references. They are also fully schema-qualified.
-- Execute is granted to authenticated/anon/service_role and revoked from PUBLIC.

-- is_self(person_id) -------------------------------------------------------
create or replace function public.is_self(person_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.people p
    where p.id = is_self.person_id
      and p.auth_user_id = (select auth.uid())
  );
$$;
comment on function public.is_self(uuid) is
  'RLS helper: true iff the caller (auth.uid()) is linked to the given person row.';

-- has_permission(org_id, permission_key) -----------------------------------
create or replace function public.has_permission(org_id uuid, permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.people p              on p.id   = m.person_id
    join public.membership_roles mr   on mr.membership_id = m.id
    join public.rbac_role_permissions rrp on rrp.role_id  = mr.rbac_role_id
    join public.rbac_permissions rp   on rp.id  = rrp.permission_id
    where m.org_id       = has_permission.org_id
      and p.auth_user_id = (select auth.uid())
      and m.status       = 'active'
      and rp.key         = has_permission.permission_key
  );
$$;
comment on function public.has_permission(uuid, text) is
  'RLS helper: true iff caller has an ACTIVE membership in org_id holding a role with permission_key.';

-- in_scope(org_id, target_person_id) ---------------------------------------
-- Three OR'd legs:
--   (a) is_self(target)
--   (b) has_permission(org_id, 'org.manage_all')        — org-wide admin scope
--   (c) caller has a position in org_id that is an ANCESTOR on target's
--       manager_position_id chain                       — manager scope
create or replace function public.in_scope(org_id uuid, target_person_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive
  caller_positions as (
    select p.id
    from public.positions p
    join public.people pp on pp.id = p.person_id
    where pp.auth_user_id = (select auth.uid())
      and p.org_id        = in_scope.org_id
  ),
  target_chain as (
    -- Anchor: every position the target holds in this org.
    select p.id, p.manager_position_id
    from public.positions p
    where p.org_id    = in_scope.org_id
      and p.person_id = in_scope.target_person_id
    union all
    -- Climb the chain.
    select p.id, p.manager_position_id
    from target_chain tc
    join public.positions p on p.id = tc.manager_position_id
    where p.org_id = in_scope.org_id
  )
  select
    public.is_self(in_scope.target_person_id)
    or public.has_permission(in_scope.org_id, 'org.manage_all')
    or exists (
      select 1
      from target_chain tc
      where tc.manager_position_id in (select id from caller_positions)
    );
$$;
comment on function public.in_scope(uuid, uuid) is
  'RLS helper: true iff caller is is_self(target), OR has org.manage_all in org, OR is on target''s manager_position_id ancestor chain.';

-- consent_active(consent_grant_id) — PLACEHOLDER --------------------------
create or replace function public.consent_active(consent_grant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- PLACEHOLDER: returns false until Step 4 creates consent_grants and redefines this body.
  select false;
$$;
comment on function public.consent_active(uuid) is
  'RLS helper: PLACEHOLDER returning false. Step 4 redefines this once consent_grants exists.';

-- Grants -------------------------------------------------------------------
revoke execute on function public.is_self(uuid)              from public;
revoke execute on function public.has_permission(uuid, text) from public;
revoke execute on function public.in_scope(uuid, uuid)       from public;
revoke execute on function public.consent_active(uuid)       from public;

grant  execute on function public.is_self(uuid)              to authenticated, anon, service_role;
grant  execute on function public.has_permission(uuid, text) to authenticated, anon, service_role;
grant  execute on function public.in_scope(uuid, uuid)       to authenticated, anon, service_role;
grant  execute on function public.consent_active(uuid)       to authenticated, anon, service_role;
