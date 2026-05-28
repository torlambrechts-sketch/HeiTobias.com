-- phase2_step1_purpose_aware_consent — extend the consent-active helper
-- family to be purpose-aware, and tighten RLS predicates on every
-- personal-data table so the consent purpose ladder is enforced at the
-- database layer (PHASE2 §3 §6 §7).

create or replace function public.consent_active(
  consent_grant_id uuid,
  p_purpose        public.consent_purpose
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.consent_grants cg
    where cg.id           = consent_active.consent_grant_id
      and cg.purpose      = consent_active.p_purpose
      and cg.status       = 'active'
      and cg.revoked_at   is null
      and (cg.expires_at  is null or cg.expires_at > now())
  );
$$;
revoke execute on function public.consent_active(uuid, public.consent_purpose) from public;
grant  execute on function public.consent_active(uuid, public.consent_purpose) to authenticated, service_role, anon;
comment on function public.consent_active(uuid, public.consent_purpose) is
  'Purpose-aware variant. True iff the consent row is active AND its purpose matches.';

create or replace function public.consent_active_for(
  p_person_id uuid,
  p_org_id    uuid,
  p_purpose   public.consent_purpose
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.consent_grants cg
    where cg.person_id          = consent_active_for.p_person_id
      and cg.granted_to_org_id  = consent_active_for.p_org_id
      and cg.purpose            = consent_active_for.p_purpose
      and cg.status             = 'active'
      and cg.revoked_at         is null
      and (cg.expires_at is null or cg.expires_at > now())
  );
$$;
revoke execute on function public.consent_active_for(uuid, uuid, public.consent_purpose) from public;
grant  execute on function public.consent_active_for(uuid, uuid, public.consent_purpose) to authenticated, service_role, anon;
comment on function public.consent_active_for(uuid, uuid, public.consent_purpose) is
  'True iff ANY active consent grant of the given purpose exists from person to org. Used by RLS predicates that gate access on a purpose-appropriate grant existing — distinct from the row''s originating consent_id.';

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select
  using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'profile.read')
      and public.in_scope(org_id, person_id)
      and (
        public.consent_active_for(person_id, org_id, 'hiring_decision')
        or public.consent_active_for(person_id, org_id, 'ongoing_management')
      )
    )
  );

drop policy if exists responses_select on public.assessment_responses;
create policy responses_select on public.assessment_responses
  for select using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'assessment.read')
      and public.in_scope(org_id, person_id)
      and public.consent_active(consent_id, 'hiring_decision')
    )
  );

drop policy if exists responses_update on public.assessment_responses;
create policy responses_update on public.assessment_responses
  for update
  using (public.has_permission(org_id,'assessment.write') and public.consent_active(consent_id,'hiring_decision'))
  with check (public.has_permission(org_id,'assessment.write') and public.consent_active(consent_id,'hiring_decision'));

drop policy if exists responses_insert_self on public.assessment_responses;
create policy responses_insert_self on public.assessment_responses
  for insert with check (
    public.is_self(person_id) and public.consent_active(consent_id, 'hiring_decision')
  );

drop policy if exists responses_insert_via_invite on public.assessment_responses;
create policy responses_insert_via_invite on public.assessment_responses
  for insert with check (
    exists (
      select 1 from public.assessment_invites inv
      where inv.id = public._invite_from_header()
        and inv.assessment_id        = assessment_responses.assessment_id
        and inv.person_id            = assessment_responses.person_id
        and inv.consent_recorded_id  = assessment_responses.consent_id
        and inv.consent_recorded_id  is not null
        and public.consent_active(inv.consent_recorded_id, 'hiring_decision')
    )
  );

drop policy if exists scores_select on public.assessment_scores;
create policy scores_select on public.assessment_scores
  for select using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'assessment.read')
      and public.in_scope(org_id, person_id)
      and public.consent_active(consent_id, 'hiring_decision')
    )
  );

drop policy if exists scores_insert on public.assessment_scores;
create policy scores_insert on public.assessment_scores
  for insert with check (
    public.has_permission(org_id,'assessment.write') and public.consent_active(consent_id,'hiring_decision')
  );

drop policy if exists fit_results_select on public.fit_results;
create policy fit_results_select on public.fit_results
  for select using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'fit.read')
      and public.in_scope(org_id, person_id)
      and public.consent_active(consent_id, 'hiring_decision')
    )
  );

drop policy if exists fit_results_insert on public.fit_results;
create policy fit_results_insert on public.fit_results
  for insert with check (
    public.has_permission(org_id,'fit.compute') and public.consent_active(consent_id,'hiring_decision')
  );

drop policy if exists fit_results_update on public.fit_results;
create policy fit_results_update on public.fit_results
  for update
  using (public.has_permission(org_id,'fit.compute') and public.consent_active(consent_id,'hiring_decision'))
  with check (public.has_permission(org_id,'fit.compute') and public.consent_active(consent_id,'hiring_decision'));
