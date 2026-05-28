-- 08_phase1_acceptance — PHASE1-SPEC §7 acceptance battery (pgTAP).
--
-- Runs the full Phase 1 candidate lifecycle end-to-end inside a transaction
-- and asserts every §7 acceptance bullet. ROLLED BACK at end; no test data
-- leaks. Run from psql or the Supabase MCP execute_sql tool.
--
-- Coverage map (Phase 1 §7):
--   [1] All 5 modules registered + enabled per agency
--   [2] Role profile instantiable from template + versioned
--   [3] Team-based definition: divergence surfaced + reconciled signed-off
--   [4] Assessment pipeline end-to-end on stub data
--   [5] DB check refuses validated + stub values
--   [6] Fit produces multi-dim fit_results, decision/override audited
--   [7] membership ≠ profile visibility (PHASE0 §4.4)
--   [8] Post-placement lifecycle (PHASE0 §5.5 / §3.1)
--   [9] No peer-personality-rating table exists (hard "never")
--  [10] Zero rows with validity_status='validated' in any seed/score table

begin;

-- ============ Scenario setup (creates fresh data) ============
-- Identities from Phase 0 seed:
--   agency_a   = Nordic Recruit
--   employer_a = FjordTech
--   agency_req = the seeded requisition
--   astrid     = org_admin in Nordic Recruit (has every permission)
--   magnus     = recruiter in Nordic Recruit
do $$
declare
  agency_a    constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a  constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req  constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid      constant uuid := 'b1000000-0000-0000-0000-000000000001';
  magnus      constant uuid := 'b1000000-0000-0000-0000-000000000002';
  -- Fresh test rows
  v_candidate uuid;
  v_membership uuid;
  v_3rd_rater  uuid;
  v_3rd_mem    uuid;
  v_invite_jsonb jsonb;
  v_assessment uuid;
  v_token text;
  v_consent_hire uuid;
  v_consent_port uuid;
  v_item record;
  v_fit_id uuid;
  v_report_id uuid;
  v_decision_id uuid;
  v_placement_id uuid;
  v_recon_id uuid;
  v_template uuid;
  v_role_v1 uuid;
begin
  -- Test candidate + invited agency membership (the §4.4 pattern).
  insert into public.people (full_name, primary_email)
    values ('Acceptance Petra', 'petra_'||gen_random_uuid()||'@accept.test')
    returning id into v_candidate;
  insert into public.memberships (org_id, person_id, status)
    values (agency_a, v_candidate, 'invited') returning id into v_membership;

  -- Persist on a temp table so the assertions below can read them.
  create temp table t_ids (k text primary key, v uuid) on commit drop;
  insert into t_ids values
    ('candidate', v_candidate),
    ('membership', v_membership),
    ('agency', agency_a),
    ('employer', employer_a),
    ('agency_req', agency_req),
    ('astrid', astrid);

  -- ===== [2] Role template instantiation =====
  -- Use a template whose title doesn't collide with the Phase 0 seed role
  -- already in agency_a ("Senior Backend Engineer" is seeded).
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  select id into v_template from public.templates
    where kind = 'role' and key = 'sample_engineering_lead';
  v_role_v1 := public.role_instantiate_from_template(v_template, agency_a);
  insert into t_ids values ('template', v_template), ('instantiated_role', v_role_v1);

  -- ===== [3] Team-based definition: 3 raters, divergence, reconcile =====
  -- Add a 3rd rater (recruiter) so the default min_evaluators=2 is comfortably exceeded.
  declare third_uuid uuid := gen_random_uuid();
  begin
    insert into auth.users (id, email) values (third_uuid, 'third_'||third_uuid||'@accept.test');
    insert into public.people (full_name, primary_email, auth_user_id)
      values ('Third Rater', 'third_'||third_uuid||'@accept.test', third_uuid)
      returning id into v_3rd_rater;
    insert into public.memberships (org_id, person_id, status)
      values (agency_a, v_3rd_rater, 'active') returning id into v_3rd_mem;
    insert into public.membership_roles (membership_id, rbac_role_id)
      select v_3rd_mem, id from public.rbac_roles where org_id is null and key='recruiter';
  end;

  insert into public.role_definition_evaluations (org_id, requisition_id, evaluator_id, ratings_json, submitted_at) values
    (agency_a, agency_req, astrid,      '[{"criterion":"sample_systems_thinking","importance":0.9},{"criterion":"sample_code_craft","importance":0.7}]'::jsonb, now()),
    (agency_a, agency_req, magnus,      '[{"criterion":"sample_systems_thinking","importance":0.5},{"criterion":"sample_code_craft","importance":0.4}]'::jsonb, now()),
    (agency_a, agency_req, v_3rd_rater, '[{"criterion":"sample_systems_thinking","importance":0.7},{"criterion":"sample_code_craft","importance":0.6}]'::jsonb, now());

  v_recon_id := public.reconcile_role_definition(agency_req,
    '[{"criterion":"sample_systems_thinking","weight":0.6},{"criterion":"sample_code_craft","weight":0.4}]'::jsonb);
  insert into t_ids values ('recon', v_recon_id);

  -- ===== [4] Assessment pipeline end-to-end =====
  v_invite_jsonb := public.assessment_invite_create(agency_a, v_candidate, 'sample_personality_v0', 'personality', 14);
  v_assessment   := (v_invite_jsonb->>'assessment_id')::uuid;
  v_token        := v_invite_jsonb->>'token';
  insert into t_ids values ('assessment', v_assessment);

  perform set_config('request.jwt.claims', '{}', true);  -- anon
  v_consent_hire := public.assessment_capture_consent(v_token);
  for v_item in select i.id from public.assessment_items i
    join public.assessment_instruments ai on ai.id = i.instrument_id
    where ai.key = 'sample_personality_v0'
  loop perform public.assessment_submit_response(v_token, v_item.id, '{"value":4}'::jsonb); end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  perform public.assessment_run_scoring(v_assessment);
  insert into t_ids values ('consent_hire', v_consent_hire);

  -- ===== [6] Fit + report =====
  v_fit_id    := public.compute_fit_for_candidate(agency_req, v_candidate);
  v_report_id := public.placement_report_generate(agency_req, v_candidate);
  insert into t_ids values ('fit', v_fit_id), ('report', v_report_id);

  -- Decision (override flag set)
  perform public.hiring_decision_record(agency_req, v_candidate, 'advance',
    'Acceptance scenario: advancing after stub review.');
  v_decision_id := public.hiring_decision_record(agency_req, v_candidate, 'hire',
    'Acceptance scenario: confirming hire after interview.', true, 'DEV STUB scenario');
  insert into t_ids values ('decision', v_decision_id);

  -- ===== [8] Placement (post-placement lifecycle assertions below) =====
  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis)
    values (v_candidate, employer_a, 'profile_portability', 'consent')
    returning id into v_consent_port;
  insert into t_ids values ('consent_port', v_consent_port);

  v_placement_id := public.placement_execute(agency_req, v_candidate, employer_a, v_consent_port);
  insert into t_ids values ('placement', v_placement_id);
end$$;

-- ============ pgTAP assertions ============
select plan(21);

-- Grant temp-table reads to authenticated for the role-switched assertions later.
grant select on t_ids to authenticated;

-- [1] All 5 Phase 1 modules registered + enabled for the agency.
select is(
  (select count(*) from public.modules where key in
    ('role_architecture','team_definition','assessment_engine','fit_scoring','candidate_experience')),
  5::bigint,
  '[1] all 5 Phase 1 modules registered'
);
select is(
  (select count(*) from public.org_modules om
   where om.org_id = (select v from t_ids where k='agency')
     and om.module_key in ('role_architecture','team_definition','assessment_engine','fit_scoring','candidate_experience')
     and om.enabled = true),
  5::bigint,
  '[1] all 5 modules enabled for the agency'
);

-- [2] Role instantiation produced a real, non-template role version.
select ok(
  (select is_template = false and status in ('draft','active')
    from public.roles_catalog
    where id = (select v from t_ids where k='instantiated_role')),
  '[2] instantiated role is non-template + active/draft'
);
select ok(
  (select definition_json ? 'competencies'
    from public.roles_catalog
    where id = (select v from t_ids where k='instantiated_role')),
  '[2] instantiated role has tightened definition shape (competencies present)'
);

-- [3] Reconciliation produced a signed-off role version with full attribution.
select ok(
  (select pr.status = 'active'
     and pr.signed_off_by is not null
     and jsonb_array_length(pr.authored_by_json) >= 4   -- 1 reconciliation + 3 evaluators
    from public.roles_catalog pr
    where pr.id = (select produced_role_id from public.role_definition_reconciliations
                   where id = (select v from t_ids where k='recon'))),
  '[3] reconciled role is active, signed off, attribution >= 4 (1 recon + 3 evaluators)'
);
-- Divergence snapshot stored
select ok(
  (select divergence_json ? 'by_criterion'
    from public.role_definition_reconciliations
    where id = (select v from t_ids where k='recon')),
  '[3] divergence_json snapshot stored with by_criterion'
);

-- [4] Assessment pipeline: 5 responses, 5 scores, all dev_stub.
select is(
  (select count(*) from public.assessment_responses
    where assessment_id = (select v from t_ids where k='assessment')),
  5::bigint,
  '[4] 5 assessment_responses persisted'
);
select is(
  (select count(*) from public.assessment_scores
    where assessment_id = (select v from t_ids where k='assessment')
      and validity_status = 'dev_stub'
      and _dev_stub = true),
  5::bigint,
  '[4] 5 dev_stub assessment_scores produced'
);

-- [5] DB check refuses validated row carrying stub values.
-- Try to insert a fake "validated" assessment_score for the same assessment with no raw/scaled score.
select throws_ok(
  $sql$
    insert into public.assessment_scores (
      org_id, assessment_id, person_id, consent_id, scale_key,
      validity_status, _dev_stub
    )
    select org_id, assessment_id, person_id, consent_id, 'fake_validated_no_value',
           'validated', true
      from public.assessment_scores
      where assessment_id = (select v from t_ids where k='assessment') limit 1
  $sql$,
  null::text,
  '[5] DB check refuses validity_status=validated + _dev_stub=true'
);

-- [6] Fit_result is multi-dim, dev_stub-marked, no auto-decide.
select ok(
  (select fit_json ? 'per_competency' and fit_json ? 'trait_ranges' and fit_json ? 'overall_summary'
    from public.fit_results where id = (select v from t_ids where k='fit')),
  '[6] fit_result carries per_competency + trait_ranges + overall_summary (multi-dim)'
);
select is(
  (select validity_status::text from public.fit_results where id = (select v from t_ids where k='fit')),
  'dev_stub',
  '[6] fit_result validity_status = dev_stub'
);
-- Override + audit
select ok(
  (select overrode_recommendation
    from public.hiring_decisions
    where id = (select v from t_ids where k='decision')),
  '[6] override flag preserved on hiring_decisions row'
);
select is(
  (select count(*) from public.audit_log
    where action = 'hiring.decision'
      and entity_id = (select v from t_ids where k='decision')),
  1::bigint,
  '[6] audit_log captures hiring.decision event'
);

-- [7] membership ≠ profile visibility (PHASE0 §4.4)
-- Revoke the assessment consent. Then:
--   - As Magnus (recruiter): people row is visible (membership exists)
--   - As Magnus: assessment_scores via consent are NOT visible
-- (Note: post-placement, membership status was set to 'removed' by Step 8 above.
--  For the §4.4 acceptance we test pre-placement semantics on a fresh pair.)
do $$
declare
  agency_a constant uuid := 'a1000000-0000-0000-0000-000000000001';
  astrid   constant uuid := 'b1000000-0000-0000-0000-000000000001';
  magnus   constant uuid := 'b1000000-0000-0000-0000-000000000002';
  cand uuid;
  inv jsonb;
  tok text;
  consent_id uuid;
  it record;
begin
  insert into public.people (full_name, primary_email)
    values ('§4.4 Test', 'fourfour_'||gen_random_uuid()||'@accept.test') returning id into cand;
  insert into public.memberships (org_id, person_id, status) values (agency_a, cand, 'invited');

  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, cand, 'sample_personality_v0','personality',14);
  tok := inv->>'token';
  perform set_config('request.jwt.claims','{}', true);
  consent_id := public.assessment_capture_consent(tok);
  for it in select i.id from public.assessment_items i
    join public.assessment_instruments ai on ai.id = i.instrument_id
    where ai.key = 'sample_personality_v0'
  loop perform public.assessment_submit_response(tok, it.id, '{"value":3}'::jsonb); end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);

  -- Revoke the consent.
  update public.consent_grants set status='revoked', revoked_at=now() where id=consent_id;

  -- Stash the candidate id so assertions can read it.
  create temp table t_44 (k text primary key, v uuid) on commit drop;
  insert into t_44 values ('cand', cand), ('consent', consent_id);
end$$;

-- Grant temp-table reads to authenticated for the role-switched assertions.
grant select on t_44 to authenticated;

-- As Magnus (recruiter), the candidate person row is visible (membership pattern).
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true);
select ok(
  (select count(*) from public.people where id = (select v from t_44 where k='cand')) >= 1,
  '[7] recruiter sees candidate person row (membership-based visibility holds)'
);
-- As Magnus, the assessment_scores for that candidate are INVISIBLE because consent is revoked.
select is(
  (select count(*) from public.assessment_scores
    where person_id = (select v from t_44 where k='cand')),
  0::bigint,
  '[7] consent-revoked → recruiter sees ZERO assessment_scores for the candidate'
);
reset role;

-- [8] Post-placement lifecycle (on the FIRST candidate, who was placed in setup).
select is(
  (select status::text from public.memberships where id = (select v from t_ids where k='membership')),
  'removed',
  '[8] post-placement: agency membership status = removed'
);
select is(
  (select stage::text from public.requisition_candidates
   where requisition_id = (select v from t_ids where k='agency_req')
     and person_id = (select v from t_ids where k='candidate')),
  'placed',
  '[8] post-placement: requisition_candidates.stage = placed'
);
select is(
  (select status::text from public.requisitions where id = (select v from t_ids where k='agency_req')),
  'placed',
  '[8] post-placement: requisitions.status = placed'
);
select ok(
  (select count(*) from public.positions
    where person_id = (select v from t_ids where k='candidate')
      and org_id = (select v from t_ids where k='employer')
      and status = 'filled') >= 1,
  '[8] post-placement: position created in employer'
);

-- [9] No peer-personality-rating table exists (hard "never").
select is(
  (select count(*) from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and (c.relname like '%peer_personality%' or c.relname like '%peer_rating%'
           or c.relname like '%personality_rating%' or c.relname like '%rate_peer%'
           or c.relname like '%rate_personality%')),
  0::bigint,
  '[9] no peer-personality-rating table exists (CLAUDE.md hard never)'
);

-- [10] Zero rows with validity_status='validated' anywhere in seed.
select is(
  (select count(*) from public.assessment_instruments where validity_status = 'validated')
  + (select count(*) from public.assessment_scores       where validity_status = 'validated')
  + (select count(*) from public.fit_results             where validity_status = 'validated'),
  0::bigint,
  '[10] zero rows with validity_status=validated across instruments, scores, fit_results'
);

select * from finish();
rollback;
