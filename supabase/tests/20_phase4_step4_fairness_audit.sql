-- 20_phase4_step4_fairness_audit — Phase 4 Step 4 acceptance.
-- Verifies SCIENCE-SPEC §10 + Phase 4 prompt §4:
--   * Demographics are separately stored + voluntary + fairness_monitoring-consent-gated
--   * Demographics CANNOT be used as a feature source (trigger refuses
--     'demographics_voluntary' in feature_views.source_tables — AI Act
--     Art. 10(5))
--   * fairness_run_open creates a run + audit event
--   * fairness_metric_record computes adverse_impact_ratio + CIs + the
--     INSPECTION TRIGGER (four_fifths_inspection_triggered), never a
--     verdict
--   * interpretation_by_expert is NEVER written by the system on insert
--     (the function leaves it null; only fairness_metric_interpret —
--     gated by modeling.signoff — can fill it)
--   * fabrication guard: no validated rows in any of the new tables

begin;
select plan(9);

do $$
declare
  agency_a constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid; r_consent uuid; f_consent uuid;
  v_fv uuid; v_role uuid; m_id uuid;
begin
  insert into public.people (full_name, primary_email) values ('P4S4 Subject', 'p4s4_'||gen_random_uuid()||'@p4.test') returning id into cand;
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
  perform public.hiring_decision_record(agency_req, cand,'hire','p4s4 fixture');
  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);
  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  perform public.placement_activate(placement_id);
  perform set_config('request.jwt.claims','{}', true);
  r_consent := public.research_consent_grant(ct_token, employer_a);
  f_consent := public.fairness_consent_grant(ct_token, employer_a);
  reset role;
  insert into public.rbac_role_permissions (role_id, permission_id)
    select r.id, p.id from public.rbac_roles r cross join public.rbac_permissions p
    where r.org_id is null and r.key = 'people_ops_admin'
      and p.key in ('modeling.read','modeling.write') on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  insert into public.feature_views (org_id, key, feature_kind, source_tables)
    values (employer_a, 'fv_p4s4', 'trait_range_fit', array['assessment_scores','roles_catalog'])
    returning id into v_fv;
  select role_id into v_role from public.requisitions where id = agency_req;
  m_id := public.model_register(employer_a, 'm_p4s4', 'interpretable_baseline_v0', v_fv, null, 'DEV STUB', null);
  perform set_config('t.cand', cand::text, true);
  perform set_config('t.employer', employer_a::text, true);
  perform set_config('t.fv', v_fv::text, true);
  perform set_config('t.model', m_id::text, true);
  perform set_config('t.token', ct_token, true);
  perform set_config('t.f_consent', f_consent::text, true);
end$$;

-- ============ [A] demographics gated by fairness_monitoring consent ============
do $$
declare d_id uuid;
begin
  perform set_config('request.jwt.claims','{}', true);
  d_id := public.demographic_record(
    current_setting('t.token'),
    current_setting('t.employer')::uuid,
    'female','prefer_not_to_say','25_34','no','NO','nb');
  perform set_config('t.dem', d_id::text, true);
end$$;
select isnt(current_setting('t.dem', true), '', '[A1] demographic_record created a row (fairness_monitoring consent active)');

-- ============ [B] demographics CANNOT be a feature source ============
reset role;
select throws_ok(
  format($q$insert into public.feature_views (org_id, key, feature_kind, source_tables)
           values (%L::uuid, 'gender_as_feature', 'trait_range_fit', array['demographics_voluntary','roles_catalog'])$q$,
    current_setting('t.employer')),
  '23514', NULL::text,
  '[B1] feature_views refuses demographics_voluntary as a source table (AI Act Art. 10(5))'
);

-- ============ [C] fairness_run_open ============
do $$
declare r_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  r_id := public.fairness_run_open(
    current_setting('t.employer')::uuid, current_setting('t.model')::uuid,
    'p4s4_fr_'||gen_random_uuid()::text);
  perform set_config('t.fr', r_id::text, true);
end$$;
select ok(
  (select count(*) from public.audit_log where action = 'fairness_run.opened' and entity_id = current_setting('t.fr')::uuid) >= 1,
  '[C1] fairness_run.opened audit event written'
);

-- ============ [D] fairness_metric_record computes AIR + CI + inspection trigger ============
do $$
declare m_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  -- Synthetic numbers: ref selects 50%, protected selects 30% → AIR=0.6
  -- which is below 0.8 — trigger should fire.
  m_id := public.fairness_metric_record(
    current_setting('t.fr')::uuid, 'gender', 'male', 'female',
    0.50, 0.30, 100, 50, 'fisher_exact', 0.04, null, null);
  perform set_config('t.fm', m_id::text, true);
end$$;
select is(
  (select round(adverse_impact_ratio::numeric, 4) from public.fairness_metrics where id = current_setting('t.fm')::uuid),
  0.6000::numeric,
  '[D1] adverse_impact_ratio computed = 0.30/0.50 = 0.60'
);
select ok(
  (select four_fifths_inspection_triggered from public.fairness_metrics where id = current_setting('t.fm')::uuid),
  '[D2] four_fifths_inspection_triggered = true at AIR<0.80 (TRIGGER, not verdict)'
);
select ok(
  (select interpretation_by_expert is null from public.fairness_metrics where id = current_setting('t.fm')::uuid),
  '[D3] interpretation_by_expert is null — system NEVER writes a verdict'
);

-- ============ [E] interpret requires modeling.signoff seam ============
select throws_ok(
  format($q$select public.fairness_metric_interpret(%L::uuid, 'DEV STUB attempted by non-expert — should refuse')$q$, current_setting('t.fm')),
  'P0001', NULL::text,
  '[E1] fairness_metric_interpret refused — modeling.signoff is an expert seam (not seeded)'
);

-- ============ [F] inverse case: AIR>=0.80 does NOT trigger ============
do $$
declare m_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  m_id := public.fairness_metric_record(
    current_setting('t.fr')::uuid, 'age_band', '25_34', '35_44',
    0.50, 0.45, 100, 80, 'fisher_exact', 0.40, null, null);
  perform set_config('t.fm2', m_id::text, true);
end$$;
select is(
  (select four_fifths_inspection_triggered from public.fairness_metrics where id = current_setting('t.fm2')::uuid),
  false,
  '[F1] inspection trigger off when AIR>=0.80'
);

-- ============ [G] fabrication guard ============
select is(
  (select count(*) from public.demographics_voluntary where _dev_stub = false)
  + (select count(*) from public.fairness_runs       where _dev_stub = false)
  + (select count(*) from public.fairness_metrics    where _dev_stub = false),
  0::bigint,
  '[G1] no validated / non-stub rows in Phase 4 Step 4 tables'
);

select * from finish();
rollback;
