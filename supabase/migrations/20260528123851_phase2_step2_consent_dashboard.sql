-- phase2_step2_consent_dashboard — candidate-owned portability flow.
--
-- A long-lived, candidate-facing token gives access to a consent dashboard
-- where the data subject can GRANT / INSPECT / REVOKE consent grants for
-- their own portable profile. This is distinct from the short-lived,
-- single-purpose assessment_invite token in /take/:token.
--
-- Issued automatically the first time a candidate captures consent in the
-- assessment flow. The token authorizes anon callers to manage CONSENT,
-- not the underlying profile/assessment data. No new cross-org data bridge.

create table public.consent_tokens (
  id          uuid primary key default extensions.gen_random_uuid(),
  person_id   uuid not null references public.people(id) on delete cascade,
  token       text not null unique,
  expires_at  timestamptz not null,
  revoked_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index consent_tokens_person_idx on public.consent_tokens (person_id);
create trigger trg_touch_consent_tokens before update on public.consent_tokens
  for each row execute function public.set_updated_at();
create trigger trg_audit_consent_tokens after insert or update or delete on public.consent_tokens
  for each row execute function public._audit_row();
alter table public.consent_tokens enable row level security;
alter table public.consent_tokens force  row level security;
-- Token bearer reads go through SECURITY DEFINER RPCs; the table is otherwise
-- locked. The data subject can directly select their own row (defensive,
-- not the primary read path).
create policy consent_tokens_self_select on public.consent_tokens
  for select using (public.is_self(person_id));

-- ---- helper: resolve a token to a (person_id, token_id) tuple ----
create or replace function public._consent_token_resolve(p_token text)
returns table (person_id uuid, token_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select ct.person_id, ct.id
    from public.consent_tokens ct
    where ct.token = p_token
      and ct.revoked_at is null
      and ct.expires_at > now()
    limit 1;
$$;
revoke execute on function public._consent_token_resolve(text) from public;
grant  execute on function public._consent_token_resolve(text) to anon, authenticated, service_role;

-- ---- assessment_capture_consent now ALSO mints a consent_token ----
-- The candidate's first consent grant is the natural moment to give them
-- access to their consent dashboard. Token is returned via a separate RPC.
create or replace function public.assessment_capture_consent(p_token text)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_invite     public.assessment_invites%rowtype;
  v_consent_id uuid;
  v_existing_token public.consent_tokens%rowtype;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'assessment_capture_consent: token required';
  end if;
  select * into v_invite from public.assessment_invites where token = p_token;
  if not found then raise exception 'assessment_capture_consent: invalid token'; end if;
  if v_invite.used_at is not null then raise exception 'assessment_capture_consent: invite already used'; end if;
  if v_invite.expires_at <= now() then raise exception 'assessment_capture_consent: invite expired'; end if;

  if v_invite.consent_recorded_id is not null then
    return v_invite.consent_recorded_id;
  end if;

  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis, scope_json)
    values (v_invite.person_id, v_invite.org_id, 'hiring_decision', 'consent',
      jsonb_build_object('assessment_id', v_invite.assessment_id, 'invite_id', v_invite.id))
    returning id into v_consent_id;
  update public.assessment_invites set consent_recorded_id = v_consent_id, updated_at = now() where id = v_invite.id;
  update public.assessments set status = 'in_progress', updated_at = now()
    where id = v_invite.assessment_id and status = 'invited';

  -- Mint a consent_token for this person if none active.
  select * into v_existing_token from public.consent_tokens
    where person_id = v_invite.person_id and revoked_at is null and expires_at > now()
    limit 1;
  if not found then
    insert into public.consent_tokens (person_id, token, expires_at)
    values (v_invite.person_id, extensions.gen_random_uuid()::text, now() + interval '365 days');
  end if;
  return v_consent_id;
end;
$$;
comment on function public.assessment_capture_consent(text) is
  'Anon-callable. Validates invite token, creates consent_grants(purpose=hiring_decision), wires onto invite, advances assessment to in_progress. Phase 2: also mints a long-lived consent_token so the candidate can manage their own consents post-assessment.';

-- ---- consent_token_for_invite(invite_token) ----
-- Anon helper: given the SHORT invite token, return the (existing) long-lived
-- consent_token for the same person — so the /take done screen can link to
-- the dashboard without re-authenticating. Returns null if no token exists.
create or replace function public.consent_token_for_invite(p_invite_token text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select ct.token
    from public.assessment_invites inv
    join public.consent_tokens ct on ct.person_id = inv.person_id
    where inv.token = p_invite_token
      and inv.consent_recorded_id is not null  -- only after consent captured
      and ct.revoked_at is null
      and ct.expires_at > now()
    order by ct.created_at desc
    limit 1;
$$;
revoke execute on function public.consent_token_for_invite(text) from public;
grant  execute on function public.consent_token_for_invite(text) to anon, authenticated, service_role;

-- ---- consent_dashboard_state(token) ----
-- The data subject's identity + every consent they hold + the orgs they hold
-- them with. Anon, token-gated.
create or replace function public.consent_dashboard_state(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_person_id uuid;
  v_person    public.people%rowtype;
  v_grants    jsonb;
  v_employers jsonb;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'consent_dashboard_state: token required';
  end if;
  select (r).person_id into v_person_id from public._consent_token_resolve(p_token) r;
  if v_person_id is null then
    raise exception 'consent_dashboard_state: invalid or expired token';
  end if;
  select * into v_person from public.people where id = v_person_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',          cg.id,
    'org_id',      cg.granted_to_org_id,
    'org_name',    o.name,
    'org_type',    o.type,
    'purpose',     cg.purpose,
    'status',      cg.status,
    'legal_basis', cg.legal_basis,
    'scope_json',  cg.scope_json,
    'granted_at',  cg.granted_at,
    'revoked_at',  cg.revoked_at,
    'expires_at',  cg.expires_at
  ) order by cg.granted_at desc), '[]'::jsonb) into v_grants
  from public.consent_grants cg
  join public.organizations o on o.id = cg.granted_to_org_id
  where cg.person_id = v_person_id;

  -- Employer orgs available to receive a portability grant — used by the UI
  -- to populate the "grant to this employer" dropdown without leaking other
  -- private org metadata. Employers only; the agency the candidate is
  -- already in via assessment is auto-included.
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name) order by o.name), '[]'::jsonb)
    into v_employers
  from public.organizations o
  where o.type = 'employer';

  return jsonb_build_object(
    'person', jsonb_build_object(
      'id',           v_person.id,
      'full_name',    v_person.full_name,
      'primary_email', v_person.primary_email
    ),
    'grants',    v_grants,
    'employers', v_employers
  );
end;
$$;
revoke execute on function public.consent_dashboard_state(text) from public;
grant  execute on function public.consent_dashboard_state(text) to anon, authenticated, service_role;
comment on function public.consent_dashboard_state(text) is
  'Anon, token-gated. Returns the data subject''s identity + the full ledger of their consents + a list of employer orgs eligible to receive a portability grant.';

-- ---- portability_grant(token, employer_org_id) ----
-- Candidate grants profile_portability to a named employer. Idempotent.
create or replace function public.portability_grant(
  p_token text,
  p_employer_org_id uuid,
  p_scope_json jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_person_id uuid;
  v_org public.organizations%rowtype;
  v_existing uuid;
  v_id uuid;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'portability_grant: token required';
  end if;
  select (r).person_id into v_person_id from public._consent_token_resolve(p_token) r;
  if v_person_id is null then
    raise exception 'portability_grant: invalid or expired token';
  end if;
  select * into v_org from public.organizations where id = p_employer_org_id;
  if not found then
    raise exception 'portability_grant: employer org not found';
  end if;

  select id into v_existing from public.consent_grants
    where person_id = v_person_id
      and granted_to_org_id = p_employer_org_id
      and purpose = 'profile_portability'
      and status = 'active'
      and revoked_at is null
      and (expires_at is null or expires_at > now())
    limit 1;
  if v_existing is not null then
    return v_existing;
  end if;

  insert into public.consent_grants (
    person_id, granted_to_org_id, purpose, legal_basis, scope_json
  ) values (
    v_person_id, p_employer_org_id, 'profile_portability', 'consent',
    coalesce(p_scope_json, '{}'::jsonb)
  )
  returning id into v_id;

  perform public.audit_log_event(
    p_employer_org_id, 'consent.granted', 'consent_grants', v_id, null,
    jsonb_build_object('purpose', 'profile_portability', 'person_id', v_person_id, 'source', 'candidate_dashboard'),
    null
  );

  return v_id;
end;
$$;
revoke execute on function public.portability_grant(text, uuid, jsonb) from public;
grant  execute on function public.portability_grant(text, uuid, jsonb) to anon, authenticated, service_role;
comment on function public.portability_grant(text, uuid, jsonb) is
  'Anon, token-gated. Data subject grants profile_portability to a named employer org. Idempotent. Audited as consent.granted.';

-- ---- consent_revoke(token, consent_id) ----
-- Data subject revokes any one of their own grants.
create or replace function public.consent_revoke(
  p_token text,
  p_consent_id uuid
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_person_id uuid;
  v_grant public.consent_grants%rowtype;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'consent_revoke: token required';
  end if;
  select (r).person_id into v_person_id from public._consent_token_resolve(p_token) r;
  if v_person_id is null then
    raise exception 'consent_revoke: invalid or expired token';
  end if;
  select * into v_grant from public.consent_grants where id = p_consent_id;
  if not found then raise exception 'consent_revoke: consent not found'; end if;
  if v_grant.person_id <> v_person_id then
    raise exception 'consent_revoke: caller is not the data subject for this consent';
  end if;
  if v_grant.status = 'revoked' then
    return p_consent_id;
  end if;
  update public.consent_grants
    set status = 'revoked', revoked_at = now(), updated_at = now()
    where id = p_consent_id;
  perform public.audit_log_event(
    v_grant.granted_to_org_id, 'consent.revoked', 'consent_grants', p_consent_id,
    jsonb_build_object('status','active'), jsonb_build_object('status','revoked'),
    null
  );
  return p_consent_id;
end;
$$;
revoke execute on function public.consent_revoke(text, uuid) from public;
grant  execute on function public.consent_revoke(text, uuid) to anon, authenticated, service_role;
comment on function public.consent_revoke(text, uuid) is
  'Anon, token-gated. Data subject revokes one of their own consent grants. Audited as consent.revoked. Idempotent.';
