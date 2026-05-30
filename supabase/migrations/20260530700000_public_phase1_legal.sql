-- Public Surfaces Phase 1 — legal perimeter + platform settings + DSR.
--
-- Adds:
--   1. platform_settings — singleton row holding the platform operator's
--      legal entity, DPO contact, support email, and the legal-review
--      status. Legal pages read a PUBLIC subset of this; platform_admin
--      writes it.
--   2. dsr_unauth_requests — the ledger for unauthenticated data-subject
--      requests (former candidates with no active account). Identity is
--      proven by an emailed magic token before any data is revealed.
--   3. RPCs:
--        platform_settings_public()        anon-readable legal contact subset
--        platform_settings_get()           platform_admin full read
--        platform_settings_update(...)      platform_admin write
--        dsr_unauth_open(email)             anon; mints a verification token
--                                           + records the request; NEVER
--                                           reveals whether data is held
--        dsr_unauth_verify(token)          anon; marks the request verified
--        dsr_unauth_summary(token)         anon (post-verify); returns what
--                                           data is held for the email
--
-- Discipline: the unauth flow must never leak existence. dsr_unauth_open
-- returns the same shape whether or not the email matches a person. Only
-- after the requester proves they own the email (clicking the magic link)
-- does dsr_unauth_summary reveal anything — and even then only for that
-- exact email.

-- ─── 1. platform_settings ───────────────────────────────────────────
create table if not exists public.platform_settings (
  id                          boolean primary key default true,   -- singleton guard
  platform_legal_entity_name  text,
  platform_legal_entity_address text,
  dpo_contact_name            text,
  dpo_contact_email           text,
  support_email               text,
  legal_review_status         text not null default 'pending'
                                check (legal_review_status in ('pending', 'current')),
  legal_reviewer_name         text,
  legal_reviewed_at           timestamptz,
  last_updated_by             uuid references public.people(id) on delete set null,
  updated_at                  timestamptz not null default now(),
  constraint platform_settings_singleton check (id = true)
);

-- Seed the singleton with honest placeholder values. legal_review_status
-- stays 'pending' — the legal pages render the TEMPLATE header until a
-- platform_admin flips this to 'current' with a reviewer name.
insert into public.platform_settings (id, platform_legal_entity_name, support_email, legal_review_status)
values (true, 'HeiTobias (legal entity TBD — pending incorporation)', 'support@heitobias.example', 'pending')
on conflict (id) do nothing;

alter table public.platform_settings enable row level security;
alter table public.platform_settings force  row level security;

-- No direct table SELECT policy for anon — the public subset is exposed
-- only through the SECDEF RPC below (so we control exactly which columns
-- leave). platform_admin can SELECT the whole row.
drop policy if exists platform_settings_admin_read on public.platform_settings;
create policy platform_settings_admin_read on public.platform_settings
  for select to authenticated using (public.is_platform_admin());

-- ─── 2. unauth DSR ledger ───────────────────────────────────────────
create table if not exists public.dsr_unauth_requests (
  id                uuid primary key default extensions.gen_random_uuid(),
  email             text not null,
  kind              public.data_subject_request_kind not null default 'export',
  verify_token      text not null unique,
  verified_at       timestamptz,
  status            text not null default 'pending'
                      check (status in ('pending', 'verified', 'fulfilled', 'expired')),
  requested_at      timestamptz not null default now(),
  expires_at        timestamptz not null default (now() + interval '30 days'),
  fulfilled_at      timestamptz
);
create index if not exists dsr_unauth_email_idx on public.dsr_unauth_requests (lower(email));
create index if not exists dsr_unauth_token_idx on public.dsr_unauth_requests (verify_token);

alter table public.dsr_unauth_requests enable row level security;
alter table public.dsr_unauth_requests force  row level security;
-- No anon/authenticated table policies — all access goes through the
-- SECDEF RPCs which scope strictly by token. platform_admin can read for
-- fulfilment.
drop policy if exists dsr_unauth_admin_read on public.dsr_unauth_requests;
create policy dsr_unauth_admin_read on public.dsr_unauth_requests
  for select to authenticated using (public.is_platform_admin());

-- ─── 3a. platform_settings_public ───────────────────────────────────
-- Anon-readable. Returns ONLY the columns that legal pages render. Never
-- returns last_updated_by or internal columns.
create or replace function public.platform_settings_public()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'platform_legal_entity_name', s.platform_legal_entity_name,
    'platform_legal_entity_address', s.platform_legal_entity_address,
    'dpo_contact_name', s.dpo_contact_name,
    'dpo_contact_email', s.dpo_contact_email,
    'support_email', s.support_email,
    'legal_review_status', s.legal_review_status,
    'legal_reviewer_name', s.legal_reviewer_name,
    'legal_reviewed_at', s.legal_reviewed_at
  )
  from public.platform_settings s
  where s.id = true;
$$;
revoke execute on function public.platform_settings_public() from public;
grant  execute on function public.platform_settings_public() to anon, authenticated;

-- ─── 3b. platform_settings_get (admin full) ─────────────────────────
create or replace function public.platform_settings_get()
returns public.platform_settings
language sql
stable
security definer
set search_path = ''
as $$
  select s.* from public.platform_settings s
  where s.id = true and public.is_platform_admin();
$$;
revoke execute on function public.platform_settings_get() from public;
grant  execute on function public.platform_settings_get() to authenticated;

-- ─── 3c. platform_settings_update ───────────────────────────────────
create or replace function public.platform_settings_update(
  p_legal_entity_name    text default null,
  p_legal_entity_address text default null,
  p_dpo_contact_name     text default null,
  p_dpo_contact_email    text default null,
  p_support_email        text default null,
  p_legal_review_status  text default null,
  p_legal_reviewer_name  text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden: platform_admin required';
  end if;
  if p_legal_review_status is not null and p_legal_review_status not in ('pending', 'current') then
    raise exception 'legal_review_status must be pending|current';
  end if;
  -- Flipping to 'current' (i.e. removing the TEMPLATE header) is a
  -- consequential action: require a reviewer name to be present.
  if p_legal_review_status = 'current'
     and coalesce(p_legal_reviewer_name, (select legal_reviewer_name from public.platform_settings where id)) is null then
    raise exception 'legal_review_status=current requires a reviewer name (who signed off)';
  end if;

  v_actor := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);

  update public.platform_settings set
    platform_legal_entity_name    = coalesce(p_legal_entity_name, platform_legal_entity_name),
    platform_legal_entity_address = coalesce(p_legal_entity_address, platform_legal_entity_address),
    dpo_contact_name              = coalesce(p_dpo_contact_name, dpo_contact_name),
    dpo_contact_email             = coalesce(p_dpo_contact_email, dpo_contact_email),
    support_email                 = coalesce(p_support_email, support_email),
    legal_review_status           = coalesce(p_legal_review_status, legal_review_status),
    legal_reviewer_name           = coalesce(p_legal_reviewer_name, legal_reviewer_name),
    legal_reviewed_at             = case when p_legal_review_status = 'current' then now() else legal_reviewed_at end,
    last_updated_by               = v_actor,
    updated_at                    = now()
  where id = true;

  insert into public.platform_admin_investigation_log (actor_person_id, action, target_org_id, payload_json)
  values (v_actor, 'platform_settings.update', null,
          jsonb_build_object('legal_review_status', p_legal_review_status));
end;
$$;
revoke execute on function public.platform_settings_update(text, text, text, text, text, text, text) from public;
grant  execute on function public.platform_settings_update(text, text, text, text, text, text, text) to authenticated;

-- ─── 4a. dsr_unauth_open ────────────────────────────────────────────
-- Anon. Records the request + mints a verification token. Returns the
-- token (the edge layer emails it as a magic link). Deliberately returns
-- the SAME shape regardless of whether the email matches a person — no
-- existence leak.
create or replace function public.dsr_unauth_open(
  p_email text,
  p_kind  text default 'export'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  if p_email is null or p_email !~ '^[^@]+@[^@]+\.[^@]+$' then
    raise exception 'invalid_email';
  end if;
  if p_kind not in ('export', 'erase') then
    raise exception 'invalid_kind';
  end if;

  -- Match the token-minting pattern used elsewhere (take-tokens etc):
  -- two dash-stripped UUIDs concatenated → 64 hex chars.
  v_token := replace(extensions.gen_random_uuid()::text, '-', '')
          || replace(extensions.gen_random_uuid()::text, '-', '');

  insert into public.dsr_unauth_requests (email, kind, verify_token)
  values (lower(p_email), p_kind::public.data_subject_request_kind, v_token);

  -- Always-the-same response. The caller cannot infer whether data exists.
  return jsonb_build_object(
    'ok', true,
    'verify_token', v_token,
    'message', 'If this email is associated with data, a verification link has been sent.'
  );
end;
$$;
revoke execute on function public.dsr_unauth_open(text, text) from public;
grant  execute on function public.dsr_unauth_open(text, text) to anon, authenticated;

-- ─── 4b. dsr_unauth_verify ──────────────────────────────────────────
create or replace function public.dsr_unauth_verify(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.dsr_unauth_requests%rowtype;
begin
  select * into v_row from public.dsr_unauth_requests where verify_token = p_token;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'invalid_token');
  end if;
  if v_row.expires_at < now() then
    update public.dsr_unauth_requests set status = 'expired' where id = v_row.id;
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;
  update public.dsr_unauth_requests
     set verified_at = coalesce(verified_at, now()), status = 'verified'
   where id = v_row.id;
  return jsonb_build_object('ok', true, 'email', v_row.email, 'kind', v_row.kind);
end;
$$;
revoke execute on function public.dsr_unauth_verify(text) from public;
grant  execute on function public.dsr_unauth_verify(text) to anon, authenticated;

-- ─── 4c. dsr_unauth_summary ─────────────────────────────────────────
-- Post-verification. Returns a summary of what data is held for the
-- verified email. Only works once the token is verified. Scoped strictly
-- to the email on the request row.
create or replace function public.dsr_unauth_summary(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row    public.dsr_unauth_requests%rowtype;
  v_person uuid;
  v_out    jsonb;
begin
  select * into v_row from public.dsr_unauth_requests where verify_token = p_token;
  if not found or v_row.verified_at is null then
    return jsonb_build_object('ok', false, 'reason', 'not_verified');
  end if;
  if v_row.expires_at < now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  select id into v_person from public.people where lower(primary_email) = v_row.email limit 1;

  if v_person is null then
    return jsonb_build_object('ok', true, 'email', v_row.email, 'data_held', false,
                              'message', 'No personal data is held for this email address.');
  end if;

  v_out := jsonb_build_object(
    'ok', true,
    'email', v_row.email,
    'data_held', true,
    'person_id', v_person,
    'counts', jsonb_build_object(
      'memberships', (select count(*) from public.memberships where person_id = v_person),
      'consent_grants', (select count(*) from public.consent_grants where person_id = v_person),
      'profiles', (select count(*) from public.profiles where person_id = v_person),
      'assessment_sessions', (select count(*) from public.assessment_sessions where person_id = v_person),
      'requisition_candidates', (select count(*) from public.requisition_candidates where person_id = v_person)
    ),
    'message', 'To receive the full export or request erasure, the platform operator processes this within 30 days (GDPR Art. 12(3)).'
  );

  return v_out;
end;
$$;
revoke execute on function public.dsr_unauth_summary(text) from public;
grant  execute on function public.dsr_unauth_summary(text) to anon, authenticated;
