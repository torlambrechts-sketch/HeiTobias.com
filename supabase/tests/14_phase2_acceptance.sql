-- 14_phase2_acceptance — Phase 2 §7 acceptance.
--
-- The cross-cutting invariants that the per-step batteries (09-13) didn't
-- assert:
--   * Channel posture — post-placement, the AGENCY cannot read the
--     employee's employer-side profile / scores / kickstart. This is the
--     privacy property AND the channel-trust property the spec names.
--   * No-second-bridge guard — placement_execute is the ONE function
--     that writes profiles into a different org from the source. A
--     meta-test against pg_get_functiondef enforces this structurally.

begin;
select plan(10);

-- ============ Setup: full lifecycle through activation + kickstart ============
do $$
declare
  agency_a   constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid     constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea     constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid; plan_id uuid; ag_membership uuid;
begin
  insert into public.people (full_name, primary_email)
    values ('Posture Test', 'pst_'||gen_random_uuid()||'@p2.test') returning id into cand;
  insert into public.memberships (org_id, person_id, status)
    values (agency_a, cand, 'invited') returning id into ag_membership;

  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, cand, 'sample_personality_v0','personality',14);
  tok := inv->>'token';
  perform set_config('request.jwt.claims','{}', true);
  cap_consent := public.assessment_capture_consent(tok);
  for it in select i.id from public.assessment_items i
    join public.assessment_instruments ai on ai.id=i.instrument_id
    where ai.key='sample_personality_v0'
  loop perform public.assessment_submit_response(tok, it.id, '{"value":4}'::jsonb); end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);
  perform public.compute_fit_for_candidate(agency_req, cand);
  perform public.hiring_decision_record(agency_req, cand,'hire','channel-posture fixture hire');

  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);

  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);

  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  perform public.placement_activate(placement_id);
  plan_id := public.kickstart_generate(cand, employer_a);

  perform set_config('t.cand', cand::text, true);
  perform set_config('t.placement', placement_id::text, true);
  perform set_config('t.plan', plan_id::text, true);
  perform set_config('t.ag_membership', ag_membership::text, true);
end$$;

-- ============ Channel posture: agency loses standing visibility ============
--
-- After placement, Magnus (Nordic Recruit recruiter) should still see
-- the placement record (his org's history) but NOT any employer-side
-- profile, scores, or post-hire artifacts. The spec calls this both a
-- privacy property and a channel-trust property — employers will not
-- tolerate agencies retaining live access to their hires.

-- Preflight (as postgres, RLS-bypassed): the placement actually happened.
-- This makes the negative posture assertions below meaningful — they fail
-- because RLS rejects the read, not because the rows don't exist.
select ok(
  (select count(*) from public.kickstart_plans where id = current_setting('t.plan')::uuid) = 1,
  '[P0] (preflight) the employer-side kickstart row exists at the storage layer'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true);  -- Magnus

select is(
  (select status::text from public.memberships
    where id = (select v::uuid from (select current_setting('t.ag_membership') as v) s)),
  'removed',
  '[P1] Agency-side membership flipped to removed atomic with placement'
);

select is(
  (select count(*) from public.profiles
    where person_id = current_setting('t.cand')::uuid
      and org_id = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  '[P2] Magnus (agency) CANNOT read the employee''s employer-side profile (no consent for him → FjordTech)'
);

select is(
  (select count(*) from public.assessment_scores
    where person_id = current_setting('t.cand')::uuid
      and org_id = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  '[P3] Magnus (agency) CANNOT read the employee''s employer-side assessment_scores'
);

select is(
  (select count(*) from public.kickstart_plans
    where id = current_setting('t.plan')::uuid),
  0::bigint,
  '[P4] Magnus (agency) CANNOT read the employee''s kickstart plan (employer-org artifact)'
);

select is(
  (select count(*) from public.fit_results
    where person_id = current_setting('t.cand')::uuid
      and org_id = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  '[P5] Magnus (agency) CANNOT read the employee''s employer-side fit_results'
);

-- Sara (FjordTech employee, no manage_all + no scope on this person) sees neither.
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000005"}', true);  -- Sara
select is(
  (select count(*) from public.kickstart_plans
    where id = current_setting('t.plan')::uuid),
  0::bigint,
  '[P6] Sara (employer manager, not in-scope on this person) cannot read kickstart plan either'
);

-- ============ No-second-bridge guard ============
--
-- Only placement_execute is allowed to write public.profiles with a
-- person+org pair that crosses a tenant boundary. The meta-test:
-- inspect every SECURITY DEFINER function in public and assert that
-- only placement_execute contains an INSERT INTO public.profiles.
--
-- (Triggers and seed scripts insert profiles in single-org contexts
-- via assessment capture; they don't pass an org_id argument. The
-- pattern we forbid is a cross-org function — i.e. a SECDEF function
-- that writes to public.profiles. placement_execute is the only
-- function in that set today; if a future PR introduces a second one,
-- this assertion fires.)

reset role;

select is(
  (
    select string_agg(p.proname, ',' order by p.proname)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
      and pg_get_functiondef(p.oid) ilike '%insert into public.profiles%'
  ),
  'placement_execute',
  '[NB1] No-second-bridge: placement_execute is the only SECDEF function that inserts into public.profiles'
);

select is(
  (
    select string_agg(p.proname, ',' order by p.proname)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
      and pg_get_functiondef(p.oid) ilike '%insert into public.placements%'
  ),
  'placement_execute',
  '[NB2] No-second-bridge: placement_execute is the only SECDEF function that inserts into public.placements'
);

select ok(
  not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
      and p.proname <> 'placement_execute'
      and pg_get_functiondef(p.oid) ilike '%insert into public.positions%'
      and pg_get_functiondef(p.oid) ilike '%to_org%'
  ),
  '[NB3] No-second-bridge: no SECDEF function (other than placement_execute) creates positions in a to_org'
);

select * from finish();
rollback;
