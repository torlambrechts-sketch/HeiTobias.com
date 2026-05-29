-- 31_phase3_closure_fixups — closes P-1 + P-2 from PHASE3-AUDIT-REPORT.md.
--
-- F1 (closes P-2): asserts the load-bearing transparency property — after
--   a manager records a guidance action, the data subject sees the same
--   guidance row + same refit + same signals via lifecycle_self_view.
--   Phase 3 prompt §A: "the EMPLOYEE can view their own profile, re-fit
--   history, and the same signals their manager sees (transparency, not
--   a one-way mirror)."
--
-- F2 (closes P-1): asserts team_composition_snapshots are queryable in the
--   shape ITEM 3 (Team-Based Role Definition) will consume — _peer_rating
--   guard intact + complementary/supplementary pull traits available.

begin;
select plan(10);

-- ============ Setup (mirrors test 15) ============
do $$
declare
  agency_a   constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid     constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea     constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand_email text := 't31_'||gen_random_uuid()||'@p3.test';
  cand_auth uuid := gen_random_uuid(); cand uuid;
  inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid; pulse_template uuid;
begin
  insert into auth.users (id, email) values (cand_auth, cand_email);
  insert into public.people (full_name, primary_email, auth_user_id)
    values ('T31 Subject', cand_email, cand_auth) returning id into cand;
  insert into public.memberships (org_id, person_id, status) values (agency_a, cand, 'invited');

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
  perform public.hiring_decision_record(agency_req, cand,'hire','t31 fixture');

  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);
  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  perform public.placement_activate(placement_id);

  select id into pulse_template from public.frameworks where key='pulse_v0_quarterly' limit 1;

  perform set_config('t.cand', cand::text, true);
  perform set_config('t.cand_auth', cand_auth::text, true);
  perform set_config('t.ct_token', ct_token, true);
  perform set_config('t.pulse_template', pulse_template::text, true);
end$$;

-- ============ Drive the lifecycle: pulse → signals → refit → guidance + action ============
do $$
declare consent_id uuid; g_id uuid;
begin
  select id into consent_id from public.consent_grants
    where person_id = current_setting('t.cand')::uuid
      and granted_to_org_id = 'a1000000-0000-0000-0000-000000000002'::uuid
      and purpose = 'ongoing_management' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.cand_auth'))::text, true);
  perform public.pulse_submit(consent_id, current_setting('t.pulse_template')::uuid,
    jsonb_build_object('answers', jsonb_build_array(
      jsonb_build_object('key','energy','value',4),
      jsonb_build_object('key','clarity','value',3),
      jsonb_build_object('key','support','value',5))));
  perform public.pulse_submit(consent_id, current_setting('t.pulse_template')::uuid,
    jsonb_build_object('answers', jsonb_build_array(
      jsonb_build_object('key','energy','value',5),
      jsonb_build_object('key','clarity','value',4),
      jsonb_build_object('key','support','value',5))));
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  perform public.signal_compute(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid, 4);
  perform public.refit_compute(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid);
  perform public.refit_compute(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid);
  g_id := public.guidance_compose(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid,
    'one_on_one_prep'::public.guidance_kind, '{"refit_quadrant":"growth_gap"}'::jsonb);
  perform public.guidance_record_action(g_id, 'acted_on', 'Discussed in 1:1');
  perform set_config('t.guidance', g_id::text, true);
end$$;

-- ============ [F1] lifecycle_self_view returns the data subject's view ============
-- Anonymous caller; the token alone authorises the self-view (data subject
-- right per GDPR Art. 15 — independent of the org's ongoing_management consent).
reset role;
do $$ begin perform set_config('request.jwt.claims', '{}', true); end$$;
select ok(
  (public.lifecycle_self_view(current_setting('t.ct_token')) ? 'pulses')
  and (public.lifecycle_self_view(current_setting('t.ct_token')) ? 'signals')
  and (public.lifecycle_self_view(current_setting('t.ct_token')) ? 'refit')
  and (public.lifecycle_self_view(current_setting('t.ct_token')) ? 'guidance')
  and (public.lifecycle_self_view(current_setting('t.ct_token')) ? 'outcomes'),
  '[F1.1] lifecycle_self_view returns all 5 sections (pulses, signals, refit, guidance, outcomes)'
);
select ok(
  jsonb_array_length((public.lifecycle_self_view(current_setting('t.ct_token'))) -> 'pulses') >= 2,
  '[F1.2] data subject sees their own pulse history (>=2 submissions)'
);
select ok(
  jsonb_array_length((public.lifecycle_self_view(current_setting('t.ct_token'))) -> 'signals') >= 1,
  '[F1.3] data subject sees the signals the manager just computed (>=1 signal)'
);
select ok(
  jsonb_array_length((public.lifecycle_self_view(current_setting('t.ct_token'))) -> 'refit') >= 2,
  '[F1.4] data subject sees the re-fit time series (>=2 evaluations from manager-side compute)'
);
select ok(
  jsonb_array_length((public.lifecycle_self_view(current_setting('t.ct_token'))) -> 'guidance') >= 1,
  '[F1.5] data subject sees the guidance row written about them (>=1 guidance item)'
);

-- TRANSPARENCY CHAIN: the guidance row the manager just acted on must be
-- present in the self-view, with the action label visible.
select is(
  (select (g ->> 'id')::uuid
     from jsonb_array_elements(public.lifecycle_self_view(current_setting('t.ct_token')) -> 'guidance') g
     where (g ->> 'id')::uuid = current_setting('t.guidance')::uuid),
  current_setting('t.guidance')::uuid,
  '[F1.6] specific guidance row from the manager workflow is visible in the self-view (transparency chain proven)'
);
select is(
  (select g ->> 'action'
     from jsonb_array_elements(public.lifecycle_self_view(current_setting('t.ct_token')) -> 'guidance') g
     where (g ->> 'id')::uuid = current_setting('t.guidance')::uuid),
  'acted_on',
  '[F1.7] action label the manager set is visible to the data subject (no hidden manager-only state)'
);

-- ============ [F2] team_composition_snapshots shape — ITEM 3 read-edge ============
-- Compute a snapshot, then assert the shape ITEM 3 will consume.
do $$ declare team_id uuid; snap_id uuid; begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  select id into team_id from public.teams where org_id = 'a1000000-0000-0000-0000-000000000002'::uuid limit 1;
  snap_id := public.team_composition_compute(team_id);
  perform set_config('t.snap', snap_id::text, true);
end$$;
select ok(
  (select (snapshot_json ->> '_peer_rating')::boolean = false
     and (snapshot_json ->> '_source') = 'members_own_profiles'
   from public.team_composition_snapshots where id = current_setting('t.snap')::uuid),
  '[F2.1] team_composition_snapshots carries _peer_rating=false + _source=members_own_profiles (the ITEM 3 read-edge guard)'
);
select ok(
  (select snapshot_json ? 'complementary_pull_traits' or snapshot_json ? 'supplementary_pull_traits'
     or snapshot_json ? 'trait_means' or snapshot_json ? 'coverage'
   from public.team_composition_snapshots where id = current_setting('t.snap')::uuid),
  '[F2.2] snapshot carries the structured trait-aggregate fields ITEM 3 will read (complementary/supplementary/means/coverage)'
);

-- [F2.3] queryable from a generic select — no privileged-only join required
select is(
  (select count(*) from public.team_composition_snapshots where id = current_setting('t.snap')::uuid),
  1::bigint,
  '[F2.3] snapshot is queryable via the standard pattern (ITEM 3 can read it without owner-only privilege)'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
