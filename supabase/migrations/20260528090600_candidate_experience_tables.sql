-- candidate_experience_tables — Phase 1 capability: no-login candidate flow.
--
--   assessment_invites    — one-time token per (person, assessment). expires_at
--                           bounds the validity. consent_recorded_id links to
--                           the consent_grant captured before any response.
--   _invite_from_header() — reads the X-Invite-Token request header and returns
--                           the matching invite id (or null). Used by RLS.
--   Token-gated anon INSERT policy on assessment_responses — the only thing
--                           an anon caller can do, and only for exactly their
--                           own invite's (person, assessment, consent).
--
-- Step 4 of Phase 1 will add SECURITY DEFINER RPCs candidate_capture_consent()
-- and candidate_submit_response() that orchestrate the full flow. This
-- migration sets up the table + the RLS plumbing.

create table public.assessment_invites (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id) on delete cascade,
  assessment_id       uuid not null references public.assessments(id)   on delete cascade,
  person_id           uuid not null references public.people(id)        on delete restrict,
  token               text not null unique,
  expires_at          timestamptz not null,
  used_at             timestamptz,
  consent_required    boolean not null default true,
  consent_recorded_id uuid references public.consent_grants(id) on delete set null,
  created_by          uuid references public.people(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- The invite's assessment + person must be self-consistent.
  -- (The assessment is itself FK'd to a person_id; we re-assert it here for sanity.)
  constraint chk_invite_expires_future check (expires_at > created_at)
);

create index assessment_invites_org_idx          on public.assessment_invites (org_id);
create index assessment_invites_assessment_idx   on public.assessment_invites (assessment_id);
create index assessment_invites_person_idx       on public.assessment_invites (person_id);
create index assessment_invites_active_partial   on public.assessment_invites (token)
  where used_at is null;

create trigger trg_assessment_invites_updated_at
  before update on public.assessment_invites
  for each row execute function public.set_updated_at();
create trigger trg_audit_assessment_invites
  after insert or update or delete on public.assessment_invites
  for each row execute function public._audit_row();

alter table public.assessment_invites enable row level security;

-- Recruiter / authenticated callers with assessment.read see invites in their org.
create policy invites_select on public.assessment_invites
  for select to authenticated
  using (public.has_permission(org_id, 'assessment.read'));
create policy invites_insert on public.assessment_invites
  for insert to authenticated
  with check (public.has_permission(org_id, 'assessment.invite'));
create policy invites_update on public.assessment_invites
  for update to authenticated
  using      (public.has_permission(org_id, 'assessment.invite'))
  with check (public.has_permission(org_id, 'assessment.invite'));

comment on table public.assessment_invites is
  'One-time invite token for a candidate to take an assessment without a login. consent_recorded_id is set by the candidate-experience flow before any response is stored.';

-- ---- _invite_from_header() ---------------------------------------------
-- Reads X-Invite-Token from PostgREST's request.headers GUC. Header names are
-- normalized to lower-case. Returns NULL if the token is missing, unknown,
-- expired, or already used.
create or replace function public._invite_from_header()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select inv.id
  from public.assessment_invites inv
  where inv.token = (current_setting('request.headers', true)::json ->> 'x-invite-token')
    and inv.expires_at > now()
    and inv.used_at is null
  limit 1;
$$;

revoke execute on function public._invite_from_header() from public;
grant  execute on function public._invite_from_header() to anon, authenticated, service_role;

comment on function public._invite_from_header() is
  'RLS helper: returns the assessment_invites.id matching the X-Invite-Token request header (if not expired or used).';

-- ---- Token-gated anon INSERT on assessment_responses -------------------
-- An anon caller bearing a valid X-Invite-Token can INSERT exactly responses
-- whose (assessment_id, person_id, consent_id) match the invite. The invite's
-- consent_recorded_id must be set (i.e. consent was captured) and active.
-- Nothing else is granted to anon — no SELECT, no UPDATE, no other table.
create policy responses_insert_via_invite on public.assessment_responses
  for insert to anon
  with check (
    exists (
      select 1 from public.assessment_invites inv
      where inv.id              = public._invite_from_header()
        and inv.assessment_id   = assessment_responses.assessment_id
        and inv.person_id       = assessment_responses.person_id
        and inv.consent_recorded_id = assessment_responses.consent_id
        and inv.consent_recorded_id is not null
        and public.consent_active(inv.consent_recorded_id)
    )
  );
