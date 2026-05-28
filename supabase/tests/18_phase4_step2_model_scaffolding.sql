-- 18_phase4_step2_model_scaffolding — Phase 4 Step 2 acceptance.
-- Verifies the load-bearing rules per the Phase 4 prompt + SCIENCE-SPEC:
--   * model_register creates a model + a first-class card in one txn
--   * predictions structurally require a SHAP-style explanation
--     (chk_predictions_shap_present)
--   * predictions are consent-gated on research_anonymized + lineage-tracked
--     (model_id + feature_row_ids + consent_id)
--   * prediction_compute_baseline_interpretable emits per-feature
--     attribution (the "logic involved" Art. 22 requirement)
--   * model_card_signoff is gated by modeling.signoff (NOT granted to
--     any seeded role) — the I/O psychologist seam
--   * prediction_attach_to_decision wires the prediction to the human
--     attributable hiring/lifecycle decision (informs, never decides)
--   * Fabrication guard: no validated rows in any Phase 4 Step 2 table

begin;
select plan(13);

-- Setup: candidate placed + activated; research_anonymized granted;
-- feature_view registered; one feature_row computed. Mirrors test 17.
do $$
declare
  agency_a constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid; r_consent uuid;
  v_fv uuid; v_role uuid; v_row uuid;
begin
  insert into public.people (full_name, primary_email) values ('P4S2 Subject', 'p4s2_'||gen_random_uuid()||'@p4.test') returning id into cand;
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
  perform public.hiring_decision_record(agency_req, cand,'hire','p4s2 fixture');
  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);
  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  perform public.placement_activate(placement_id);

  perform set_config('request.jwt.claims','{}', true);
  r_consent := public.research_consent_grant(ct_token, employer_a);

  -- Grant modeling.read/write to people_ops_admin (which Linnea has).
  reset role;
  insert into public.rbac_role_permissions (role_id, permission_id)
    select r.id, p.id from public.rbac_roles r cross join public.rbac_permissions p
    where r.org_id is null and r.key = 'people_ops_admin'
      and p.key in ('modeling.read','modeling.write')
    on conflict do nothing;

  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  insert into public.feature_views (org_id, key, feature_kind, source_tables, feature_spec)
    values (employer_a, 'trait_range_fit_p4s2', 'trait_range_fit',
      array['assessment_scores','roles_catalog','profiles'],
      jsonb_build_object('description','DEV STUB','_dev_stub',true))
    returning id into v_fv;

  select role_id into v_role from public.requisitions where id = agency_req;

  v_row := public.feature_compute_trait_range_fit(cand, employer_a, v_role, v_fv);

  perform set_config('t.cand', cand::text, true);
  perform set_config('t.employer', employer_a::text, true);
  perform set_config('t.role', v_role::text, true);
  perform set_config('t.fv', v_fv::text, true);
  perform set_config('t.row', v_row::text, true);
  perform set_config('t.r_consent', r_consent::text, true);
end$$;

-- ============ [A] model_register creates registry + card in one txn ============
do $$
declare m_id uuid; c_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  m_id := public.model_register(
    current_setting('t.employer')::uuid,
    'baseline_perf_p4s2',
    'interpretable_baseline_v0',
    current_setting('t.fv')::uuid,
    null, 'DEV STUB baseline model', null);
  select id into c_id from public.model_cards where model_id = m_id;
  perform set_config('t.model', m_id::text, true);
  perform set_config('t.card', c_id::text, true);
end$$;
select isnt(
  current_setting('t.card', true), '',
  '[A1] model_register created a model_cards row in the same txn'
);
select ok(
  (select _dev_stub from public.model_cards where id = current_setting('t.card')::uuid),
  '[A2] new model_card is _dev_stub=true (synthetic-only)'
);
select ok(
  (select count(*) from public.audit_log
    where action = 'model.registered' and entity_id = current_setting('t.model')::uuid) >= 1,
  '[A3] model.registered audit event written'
);

-- ============ [B] model_card_update + signoff seam ============
do $$
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  perform public.model_card_update(
    current_setting('t.model')::uuid,
    'DEV STUB intended use: synthetic-only interpretable baseline for testing',
    jsonb_build_object('not_for','live hiring decisions','until','I/O psychologist signoff'),
    jsonb_build_object('feature_view_id', current_setting('t.fv')::uuid, '_dev_stub', true),
    jsonb_build_array(jsonb_build_object('key','sample_competency','weight',1)),
    jsonb_build_object('sample_competency', 1),
    '{}'::jsonb,
    'Synthetic only until I/O psychologist engages — see HANDOFF'
  );
end$$;
select is(
  (select intended_use is not null and length(intended_use) > 10 from public.model_cards where id = current_setting('t.card')::uuid),
  true,
  '[B1] model_card_update populated intended_use'
);
-- modeling.signoff is NOT granted to people_ops_admin — Linnea must be refused.
select throws_ok(
  format($$select public.model_card_signoff(%L::uuid)$$, current_setting('t.model')),
  'P0001', NULL::text,
  '[B2] model_card_signoff refused — modeling.signoff is an expert seam (not seeded)'
);

-- ============ [C] training_run_record writes audit ============
do $$
declare tr uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  -- We need a dataset to point at; freeze one quickly.
  perform set_config('t.ds',
    public.model_dataset_freeze(current_setting('t.employer')::uuid,
                                current_setting('t.fv')::uuid,
                                'p4s2_ds_'||gen_random_uuid()::text)::text, true);
  tr := public.training_run_record(
    current_setting('t.model')::uuid,
    current_setting('t.ds')::uuid,
    'linear_regression_dev_stub_v0',
    jsonb_build_object('r2', null, '_dev_stub', true),
    'DEV STUB run');
  perform set_config('t.tr', tr::text, true);
end$$;
select ok(
  (select count(*) from public.audit_log
    where action = 'model.training_run' and entity_id = current_setting('t.tr')::uuid) >= 1,
  '[C1] training_run_record wrote model.training_run audit event'
);

-- ============ [D] prediction_compute_baseline_interpretable ============
do $$
declare p_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  p_id := public.prediction_compute_baseline_interpretable(
    current_setting('t.model')::uuid,
    current_setting('t.cand')::uuid,
    current_setting('t.role')::uuid);
  perform set_config('t.pred', p_id::text, true);
end$$;
select ok(
  (select _dev_stub from public.predictions where id = current_setting('t.pred')::uuid),
  '[D1] prediction is _dev_stub=true (interpretable baseline, never validated)'
);
select ok(
  (select jsonb_array_length(explanation_shap_json) >= 1 from public.predictions where id = current_setting('t.pred')::uuid),
  '[D2] prediction carries SHAP-style attribution (Art. 22 logic-involved)'
);
select ok(
  (select array_length(feature_row_ids, 1) >= 1 from public.predictions where id = current_setting('t.pred')::uuid),
  '[D3] prediction carries lineage (feature_row_ids)'
);
select is(
  (select (prediction_json->>'is_decision')::boolean from public.predictions where id = current_setting('t.pred')::uuid),
  false,
  '[D4] prediction.is_decision = false (informs human, never decides)'
);

-- Direct insert with empty explanation_shap_json is REFUSED by CHECK.
select throws_ok(
  format($$insert into public.predictions (org_id, model_id, person_id, consent_id, explanation_shap_json)
           values (%L::uuid, %L::uuid, %L::uuid, %L::uuid, '[]'::jsonb)$$,
    current_setting('t.employer'), current_setting('t.model'),
    current_setting('t.cand'), current_setting('t.r_consent')),
  '23514', NULL::text,
  '[D5] empty explanation_shap_json refused (chk_predictions_shap_present)'
);

-- ============ [E] prediction_attach_to_decision ============
do $$
declare ld_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  -- Record a lifecycle_decision in the employer org (same org as prediction)
  -- — Phase 4 predictions are about post-hire flight risk / performance.
  ld_id := public.lifecycle_decision_record(
    current_setting('t.cand')::uuid,
    current_setting('t.employer')::uuid,
    'retain'::public.lifecycle_decision_kind,
    'P4S2 test fixture — human decided to retain after seeing the (dev_stub) prediction',
    false, null, null, null);
  perform public.prediction_attach_to_decision(
    current_setting('t.pred')::uuid, ld_id, 'lifecycle_decision');
end$$;
select isnt(
  (select informs_decision_id::text from public.predictions where id = current_setting('t.pred')::uuid),
  null::text,
  '[E1] prediction_attach_to_decision wired the prediction to a lifecycle_decision'
);

-- ============ [F] Fabrication guard ============
select is(
  (select count(*) from public.model_registry where validity_status = 'validated' or _dev_stub = false)
  + (select count(*) from public.model_cards   where validity_status = 'validated' or _dev_stub = false)
  + (select count(*) from public.predictions   where validity_status = 'validated' or _dev_stub = false),
  0::bigint,
  '[F1] no validated / non-stub rows in Phase 4 Step 2 tables (synthetic-only)'
);

select * from finish();
rollback;
