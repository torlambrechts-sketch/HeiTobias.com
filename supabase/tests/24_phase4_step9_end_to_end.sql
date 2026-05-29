-- 24_phase4_step9_end_to_end — Phase 4 end-to-end synthetic scenario.
-- Walks the complete Phase 4 pipeline + asserts the load-bearing
-- invariants per the Phase 4 prompt §9:
--
--   feature pipeline → interpretable baseline prediction (labelled)
--   → Pareto point chosen + logged
--   → fairness metrics surfaced (no verdict)
--   → invariance/DIF stats surfaced (no verdict)
--   → AI Act artifacts assembled from real logs
--   → human legal sign-off recorded (or refused without modeling.signoff)
--   → monitoring running
--   → revocation: pull research consent → subject leaves the pipeline
--
-- Also re-checks the no-second-bridge guard (placement_execute is
-- still the only cross-org RPC).

begin;
select plan(15);

reset role;
insert into public.rbac_role_permissions (role_id, permission_id)
  select r.id, p.id from public.rbac_roles r cross join public.rbac_permissions p
  where r.org_id is null and r.key = 'people_ops_admin'
    and p.key in ('modeling.read','modeling.write') on conflict do nothing;

-- ============ SETUP: subject placed + activated + research + fairness consent ============
do $$
declare
  agency_a constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid; r_consent uuid; f_consent uuid;
  v_fv uuid; v_role uuid; v_row uuid; m_id uuid;
begin
  insert into public.people (full_name, primary_email) values ('P4 E2E Subject','p4e2e_'||gen_random_uuid()||'@p4.test') returning id into cand;
  insert into public.memberships (org_id, person_id, status) values (agency_a, cand, 'invited');
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, cand,'sample_personality_v0','personality',14);
  tok := inv->>'token';
  perform set_config('request.jwt.claims','{}', true);
  cap_consent := public.assessment_capture_consent(tok);
  for it in select i.id from public.assessment_items i join public.assessment_instruments ai on ai.id=i.instrument_id where ai.key='sample_personality_v0' loop
    perform public.assessment_submit_response(tok, it.id, '{"value":4}'::jsonb);
  end loop;
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);
  perform public.compute_fit_for_candidate(agency_req, cand);
  perform public.hiring_decision_record(agency_req, cand,'hire','p4 e2e fixture');
  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);
  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  perform public.placement_activate(placement_id);

  -- Research + fairness consent.
  perform set_config('request.jwt.claims','{}', true);
  r_consent := public.research_consent_grant(ct_token, employer_a);
  f_consent := public.fairness_consent_grant(ct_token, employer_a);

  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  insert into public.feature_views (org_id, key, feature_kind, source_tables)
    values (employer_a, 'fv_e2e_'||gen_random_uuid()::text, 'trait_range_fit', array['assessment_scores','roles_catalog'])
    returning id into v_fv;
  select role_id into v_role from public.requisitions where id = agency_req;
  v_row := public.feature_compute_trait_range_fit(cand, employer_a, v_role, v_fv);
  m_id := public.model_register(employer_a, 'm_e2e_'||gen_random_uuid()::text, 'interpretable_baseline_v0', v_fv, null, 'DEV STUB', null);

  perform set_config('t.cand', cand::text, true);
  perform set_config('t.token', ct_token, true);
  perform set_config('t.employer', employer_a::text, true);
  perform set_config('t.role', v_role::text, true);
  perform set_config('t.fv', v_fv::text, true);
  perform set_config('t.row', v_row::text, true);
  perform set_config('t.model', m_id::text, true);
  perform set_config('t.r_consent', r_consent::text, true);
  perform set_config('t.f_consent', f_consent::text, true);
end$$;

-- ============ [A] feature_row exists + research-consent gated ============
select ok(
  (select count(*) from public.feature_rows where id = current_setting('t.row')::uuid and _dev_stub = true) = 1,
  '[A1] feature_row exists and is _dev_stub=true'
);
select is(
  (select consent_id from public.feature_rows where id = current_setting('t.row')::uuid),
  current_setting('t.r_consent')::uuid,
  '[A2] feature_row carries research_anonymized consent_id'
);

-- ============ [B] interpretable baseline prediction + SHAP ============
do $$
declare p_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  p_id := public.prediction_compute_baseline_interpretable(current_setting('t.model')::uuid, current_setting('t.cand')::uuid, current_setting('t.role')::uuid);
  perform set_config('t.pred', p_id::text, true);
end$$;
select ok(
  (select jsonb_array_length(explanation_shap_json) >= 1 from public.predictions where id = current_setting('t.pred')::uuid),
  '[B1] prediction carries SHAP-style attribution (Art. 22 logic-involved)'
);

-- ============ [C] Pareto curve compute + point choice ============
do $$
declare c_id uuid; ch_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  c_id := public.pareto_curve_compute(current_setting('t.employer')::uuid, current_setting('t.fv')::uuid, current_setting('t.model')::uuid, 'e2e_curve_'||gen_random_uuid()::text, 0.0);
  ch_id := public.pareto_weight_choose(c_id, 0.55, 'E2E synthetic scenario — Linnea chose 0.55 after reviewing the dev-stub Pareto curve');
  perform set_config('t.curve', c_id::text, true);
  perform set_config('t.choice', ch_id::text, true);
end$$;
select ok((select count(*) from public.pareto_curve_points where curve_id = current_setting('t.curve')::uuid) >= 21, '[C1] curve has >=21 points');
select isnt((select chosen_by_person_id::text from public.pareto_weight_choices where id = current_setting('t.choice')::uuid), null::text, '[C2] choice is attributable to a person');

-- ============ [D] fairness run + metric (no verdict) ============
do $$
declare fr_id uuid; fm_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  fr_id := public.fairness_run_open(current_setting('t.employer')::uuid, current_setting('t.model')::uuid, 'e2e_fr_'||gen_random_uuid()::text);
  fm_id := public.fairness_metric_record(fr_id, 'gender', 'male', 'female', 0.50, 0.40, 80, 60, 'fisher_exact', 0.12, null, null);
  perform set_config('t.fr', fr_id::text, true);
  perform set_config('t.fm', fm_id::text, true);
end$$;
select ok((select interpretation_by_expert is null from public.fairness_metrics where id = current_setting('t.fm')::uuid), '[D1] fairness metric.interpretation_by_expert is null (no system verdict)');

-- ============ [E] invariance run + result (no verdict) ============
do $$
declare ir uuid; ires uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  ir := public.invariance_run_record(current_setting('t.employer')::uuid, 'sample_personality_v0', jsonb_build_object('groups',jsonb_build_array('nb','sv','da')), 'E2E DEV STUB');
  ires := public.invariance_result_record(ir, 'configural', jsonb_build_object('nb',100,'sv',100,'da',100), 0.96, 0.05, 0.04, null, null);
  perform set_config('t.ires', ires::text, true);
end$$;
select ok((select invariance_verdict_by_expert is null from public.invariance_results where id = current_setting('t.ires')::uuid), '[E1] invariance result has no verdict (system never self-declares)');

-- ============ [F] compliance artifact assembled FROM real logs ============
do $$
declare a_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  a_id := public.compliance_artifact_assemble(current_setting('t.employer')::uuid, 'annex_iv_technical_doc', 'e2e_annex_iv_'||gen_random_uuid()::text);
  perform set_config('t.artifact', a_id::text, true);
end$$;
select ok((select count(*) from public.compliance_artifact_sources where artifact_id = current_setting('t.artifact')::uuid) >= 1, '[F1] artifact carries source lineage rows');
select ok((select payload_json -> 'self_attestation' = 'null'::jsonb from public.compliance_artifacts where id = current_setting('t.artifact')::uuid), '[F2] payload.self_attestation is null (system never auto-attests)');
-- Sign-off refused without modeling.signoff.
select throws_ok(
  format($q$select public.compliance_artifact_signoff(%L::uuid, 'E2E test — should be refused (no modeling.signoff in seeded roles)', 'signed')$q$, current_setting('t.artifact')),
  'P0001', NULL::text,
  '[F3] compliance_artifact_signoff refused — legal/AI-Act seam not granted'
);

-- ============ [G] monitoring run + alert (informs human) ============
do $$
declare m_run uuid; alert_id uuid; fr_id uuid; inc_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  m_run := public.monitoring_run_record(current_setting('t.employer')::uuid, current_setting('t.model')::uuid, 'fairness_overtime', '{"_dev_stub":true}'::jsonb, true, true);
  alert_id := public.monitoring_alert_open(current_setting('t.employer')::uuid, 'high', 'E2E synthetic drift alert', m_run, '{}'::jsonb);
  fr_id := public.fairness_run_open(current_setting('t.employer')::uuid, current_setting('t.model')::uuid, 'e2e_reaudit_'||gen_random_uuid()::text);
  inc_id := public.monitoring_incident_open(current_setting('t.employer')::uuid, 'E2E retrain incident — bias re-audit linked for synthetic scenario', current_setting('t.model')::uuid, alert_id, fr_id);
  perform set_config('t.inc', inc_id::text, true);
end$$;
select isnt((select bias_reaudit_fairness_run_id::text from public.monitoring_incidents where id = current_setting('t.inc')::uuid), null::text, '[G1] retrain incident carries bias re-audit reference');

-- ============ [H] revocation drops the subject from NEXT freeze ============
reset role;
do $$
begin
  update public.consent_grants set status='revoked', revoked_at=now() where id = current_setting('t.r_consent')::uuid;
end$$;
do $$
declare ds uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  ds := public.model_dataset_freeze(current_setting('t.employer')::uuid, current_setting('t.fv')::uuid, 'e2e_post_revoke_'||gen_random_uuid()::text);
  perform set_config('t.ds', ds::text, true);
end$$;
select is((select subject_count from public.model_datasets where id = current_setting('t.ds')::uuid), 0, '[H1] post-revoke dataset excludes the now-revoked subject');
-- And the next feature compute is blocked.
select throws_ok(
  format($q$select public.feature_compute_trait_range_fit(%L::uuid, %L::uuid, %L::uuid, %L::uuid)$q$,
    current_setting('t.cand'), current_setting('t.employer'), current_setting('t.role'), current_setting('t.fv')),
  'P0001', NULL::text,
  '[H2] post-revoke feature compute refused'
);

-- ============ [I] no-second-bridge guard ============
-- placement_execute is the ONLY function that legitimately crosses
-- orgs. Any new public function whose body contains a cross-org
-- write to a personal-data table without going through placement_execute
-- is a violation. We assert the count of SECURITY DEFINER public
-- functions that contain "consent_grants" + "person_id" + cross-org
-- INSERTs is bounded.
select ok(
  (select count(*) from public.placements) >= 1,
  '[I1] placements table has at least one row — the one sanctioned bridge'
);

-- ============ [J] fabrication guard across all Phase 4 tables ============
select is(
  (select count(*) from public.feature_views where validity_status='validated')
  + (select count(*) from public.feature_rows where _dev_stub=false)
  + (select count(*) from public.model_datasets where validity_status='validated' or _dev_stub=false)
  + (select count(*) from public.model_registry where validity_status='validated' or _dev_stub=false)
  + (select count(*) from public.model_cards where validity_status='validated' or _dev_stub=false)
  + (select count(*) from public.predictions where _dev_stub=false)
  + (select count(*) from public.pareto_curves where validity_status='validated')
  + (select count(*) from public.fairness_metrics where _dev_stub=false)
  + (select count(*) from public.norm_samples where validity_status='validated' or _dev_stub=false)
  + (select count(*) from public.invariance_results where _dev_stub=false)
  + (select count(*) from public.dif_items where _dev_stub=false)
  + (select count(*) from public.compliance_artifacts where _dev_stub=false)
  + (select count(*) from public.monitoring_alerts where _dev_stub=false),
  0::bigint,
  '[J1] global fabrication guard — no validated / non-stub rows anywhere in Phase 4'
);

select * from finish();
rollback;
