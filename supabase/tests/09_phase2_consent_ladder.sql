-- 09_phase2_consent_ladder — PHASE2 Step 1: purpose-aware consent helpers
-- and the three-rung consent ladder (hiring_decision → profile_portability →
-- ongoing_management). Each rung is a separate grant; none implies another;
-- each is independently revocable.

begin;

select plan(13);

-- ============ helper-level checks ============

-- Use the seeded portability consent (f1000000-...-002, purpose=profile_portability).
select ok(
  public.consent_active('f1000000-0000-0000-0000-000000000002'::uuid, 'profile_portability'),
  '[A1] consent_active(id, profile_portability) = true for seeded portability consent'
);
select ok(
  not public.consent_active('f1000000-0000-0000-0000-000000000002'::uuid, 'hiring_decision'),
  '[A2] consent_active(id, hiring_decision) = false for a profile_portability consent (cross-purpose denied)'
);
select ok(
  not public.consent_active('f1000000-0000-0000-0000-000000000002'::uuid, 'ongoing_management'),
  '[A3] consent_active(id, ongoing_management) = false for a profile_portability consent (cross-purpose denied)'
);

-- consent_active_for: matches by (person, org, purpose), not by consent_id.
select ok(
  public.consent_active_for(
    'b1000000-0000-0000-0000-000000000007'::uuid,   -- Petra
    'a1000000-0000-0000-0000-000000000002'::uuid,   -- FjordTech
    'profile_portability'),
  '[A4] consent_active_for(person, org, profile_portability) = true (seed matches)'
);
select ok(
  not public.consent_active_for(
    'b1000000-0000-0000-0000-000000000007'::uuid,
    'a1000000-0000-0000-0000-000000000002'::uuid,
    'ongoing_management'),
  '[A5] consent_active_for(person, org, ongoing_management) = false (no such grant seeded)'
);

-- ============ profile visibility under the ladder ============
--
-- Set up: place Petra at FjordTech under profile_portability so the profile row
-- exists. Per Phase 2, profile_portability alone does NOT authorize ongoing
-- viewing; an active hiring_decision OR ongoing_management grant is required.

do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true);  -- Magnus
  perform public.hiring_decision_record(
    'a3000000-0000-0000-0000-000000000001'::uuid,
    'b1000000-0000-0000-0000-000000000007'::uuid,
    'hire', 'Test fixture: hire.');
  perform public.placement_execute(
    'a3000000-0000-0000-0000-000000000001'::uuid,
    'b1000000-0000-0000-0000-000000000007'::uuid,
    'a1000000-0000-0000-0000-000000000002'::uuid,
    'f1000000-0000-0000-0000-000000000002'::uuid);
end$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);  -- Linnea, FjordTech people_ops_admin

-- [B1] Before any hiring_decision or ongoing_management consent exists for
-- (Petra → FjordTech), Linnea cannot see the migrated profile — profile_portability
-- alone is not a use-authorization.
select is(
  (select count(*) from public.profiles
    where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
      and org_id    = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  '[B1] profile_portability alone does NOT authorize ongoing visibility (Phase 2 §)'
);

-- Capture an ongoing_management consent.
reset role;
do $$
declare v uuid;
begin
  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis)
    values ('b1000000-0000-0000-0000-000000000007'::uuid,
            'a1000000-0000-0000-0000-000000000002'::uuid,
            'ongoing_management', 'consent') returning id into v;
  perform set_config('t.ongoing', v::text, true);
end$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);

select is(
  (select count(*) from public.profiles
    where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
      and org_id    = 'a1000000-0000-0000-0000-000000000002'::uuid),
  1::bigint,
  '[B2] ongoing_management consent unlocks profile visibility for the employer'
);

-- Also grant hiring_decision for FjordTech (e.g. legacy/hybrid window).
reset role;
do $$
declare v uuid;
begin
  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis)
    values ('b1000000-0000-0000-0000-000000000007'::uuid,
            'a1000000-0000-0000-0000-000000000002'::uuid,
            'hiring_decision', 'consent') returning id into v;
  perform set_config('t.hiring_fjord', v::text, true);
end$$;

-- Revoke ongoing_management — profile should still be visible via hiring_decision.
reset role;
update public.consent_grants
  set status='revoked', revoked_at=now()
  where id = current_setting('t.ongoing')::uuid;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
select is(
  (select count(*) from public.profiles
    where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
      and org_id    = 'a1000000-0000-0000-0000-000000000002'::uuid),
  1::bigint,
  '[B3] revoking ongoing_management alone does NOT remove access if hiring_decision is also active'
);

-- Revoke hiring_decision too — now everything is gone.
reset role;
update public.consent_grants
  set status='revoked', revoked_at=now()
  where id = current_setting('t.hiring_fjord')::uuid;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
select is(
  (select count(*) from public.profiles
    where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
      and org_id    = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  '[B4] with BOTH use-consents revoked, profile is invisible (profile_portability is not a use-auth)'
);

-- ============ assessment-data is tied to hiring_decision specifically ============
--
-- assessment_scores / responses / fit_results check consent_active(consent_id, 'hiring_decision').
-- An ongoing_management grant does NOT authorize reading those rows (cross-purpose denied).
-- Set up a fresh candidate, run the full assessment pipeline to produce scores under
-- a hiring_decision consent, then verify the ladder.

reset role;
do $$
declare
  agency_a   constant uuid := 'a1000000-0000-0000-0000-000000000001';
  astrid     constant uuid := 'b1000000-0000-0000-0000-000000000001';
  c_id uuid; inv jsonb; tok text; cap_consent uuid; it record;
begin
  insert into public.people (full_name, primary_email)
    values ('LadderTest', 'ladder_'||gen_random_uuid()||'@p2.test') returning id into c_id;
  insert into public.memberships (org_id, person_id, status) values (agency_a, c_id, 'invited');
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, c_id, 'sample_personality_v0', 'personality', 14);
  tok := inv->>'token';
  perform set_config('request.jwt.claims', '{}', true);
  cap_consent := public.assessment_capture_consent(tok);
  for it in select i.id from public.assessment_items i
    join public.assessment_instruments ai on ai.id = i.instrument_id
    where ai.key = 'sample_personality_v0'
  loop perform public.assessment_submit_response(tok, it.id, '{"value":4}'::jsonb); end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);
  perform set_config('t.cand', c_id::text, true);
  perform set_config('t.cap_consent', cap_consent::text, true);
end$$;

-- Astrid (org_admin in Nordic Recruit) should see the freshly scored candidate's scores
-- via the hiring_decision consent created during capture.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000001"}', true);  -- Astrid
select ok(
  (select count(*) from public.assessment_scores
    where person_id = current_setting('t.cand')::uuid) >= 1,
  '[C1] astrid sees fresh candidate scores via active hiring_decision consent'
);

-- Revoke the hiring_decision consent (the one created during capture).
reset role;
update public.consent_grants
  set status='revoked', revoked_at=now()
  where id = current_setting('t.cap_consent')::uuid;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000001"}', true);
select is(
  (select count(*) from public.assessment_scores
    where person_id = current_setting('t.cand')::uuid),
  0::bigint,
  '[C2] revoking hiring_decision removes score access (per-rung revocation)'
);

-- Adding an ongoing_management consent (different purpose) does NOT restore access.
reset role;
insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis)
  values (current_setting('t.cand')::uuid,
          'a1000000-0000-0000-0000-000000000001'::uuid,
          'ongoing_management', 'consent');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000001"}', true);
select is(
  (select count(*) from public.assessment_scores
    where person_id = current_setting('t.cand')::uuid),
  0::bigint,
  '[C3] ongoing_management does NOT unlock hiring_decision-purposed scores (cross-purpose denied)'
);

-- ============ Petra always sees her own data (is_self) ============
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000007"}', true);
select ok(
  (select count(*) from public.profiles where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid) >= 1,
  '[D1] petra (data subject) always sees her profile via is_self regardless of consent'
);

select * from finish();
rollback;
