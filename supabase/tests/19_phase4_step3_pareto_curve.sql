-- 19_phase4_step3_pareto_curve — Phase 4 Step 3 acceptance.
-- Verifies the load-bearing rules per the Phase 4 prompt + SCIENCE-SPEC §10:
--   * Pareto curve computes (>=21 points) on synthetic data, all marked dev_stub
--   * DEFAULT point prioritizes neither extreme (0.05 < w < 0.95, structurally)
--   * Curve has exactly one is_default_point row
--   * Point choice requires authenticated person, rationale >20 chars
--     (refused without it) — Mobley v. Workday-style attribution
--   * pareto_weight.chosen audit event written
--   * Fabrication guard: no validated rows in any of the three Pareto tables

begin;
select plan(8);

-- Setup: reuse Step 1/2 fixture pattern. Place subject and grant research consent so we have a feature_view.
do $$
declare
  agency_a constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid; r_consent uuid;
  v_fv uuid; v_role uuid;
begin
  insert into public.people (full_name, primary_email) values ('P4S3 Subject', 'p4s3_'||gen_random_uuid()||'@p4.test') returning id into cand;
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
  perform public.hiring_decision_record(agency_req, cand,'hire','p4s3 fixture');
  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);
  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  perform public.placement_activate(placement_id);
  perform set_config('request.jwt.claims','{}', true);
  r_consent := public.research_consent_grant(ct_token, employer_a);
  reset role;
  insert into public.rbac_role_permissions (role_id, permission_id)
    select r.id, p.id from public.rbac_roles r cross join public.rbac_permissions p
    where r.org_id is null and r.key = 'people_ops_admin'
      and p.key in ('modeling.read','modeling.write')
    on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  insert into public.feature_views (org_id, key, feature_kind, source_tables, feature_spec)
    values (employer_a, 'trait_range_fit_p4s3', 'trait_range_fit',
      array['assessment_scores','roles_catalog','profiles'],
      jsonb_build_object('description','DEV STUB','_dev_stub',true))
    returning id into v_fv;
  select role_id into v_role from public.requisitions where id = agency_req;
  perform set_config('t.employer', employer_a::text, true);
  perform set_config('t.fv', v_fv::text, true);
end$$;

-- ============ [A] curve compute ============
-- Default not extreme is enforced by CHECK; the function emits the
-- default at 0.5, well inside the (0.05, 0.95) window.
do $$
declare c_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  c_id := public.pareto_curve_compute(
    current_setting('t.employer')::uuid,
    current_setting('t.fv')::uuid,
    null, 'p4s3_curve_'||gen_random_uuid()::text, 0.0);
  perform set_config('t.curve', c_id::text, true);
end$$;
select ok(
  (select count(*) from public.pareto_curve_points where curve_id = current_setting('t.curve')::uuid) >= 21,
  '[A1] pareto_curve_compute emits >=21 points'
);
select is(
  (select count(*) from public.pareto_curve_points
    where curve_id = current_setting('t.curve')::uuid and is_default_point),
  1::bigint,
  '[A2] exactly one is_default_point on the curve'
);
select ok(
  (select default_weight_validity > 0.05 and default_weight_validity < 0.95
    from public.pareto_curves where id = current_setting('t.curve')::uuid),
  '[A3] default_weight_validity prioritizes neither extreme (structural CHECK)'
);
-- CHECK refuses an extreme default at INSERT time.
select throws_ok(
  format($q$insert into public.pareto_curves (org_id, feature_view_id, key, default_weight_validity)
           values (%L::uuid, %L::uuid, 'extreme_default_test', 0.01)$q$,
    current_setting('t.employer'), current_setting('t.fv')),
  '23514', NULL::text,
  '[A4] extreme default (<=0.05) refused by chk_pareto_default_not_extreme'
);

-- ============ [B] point choice = attributable + audited ============
-- Rationale <=20 chars is refused.
select throws_ok(
  format($q$select public.pareto_weight_choose(%L::uuid, 0.55, 'too short')$q$, current_setting('t.curve')),
  'P0001', NULL::text,
  '[B1] short rationale refused (attribution requirement)'
);
do $$
declare ch_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  ch_id := public.pareto_weight_choose(
    current_setting('t.curve')::uuid, 0.55,
    'Bias-aware tuning — Linnea (people_ops_admin) chose 0.55 after reviewing the synthetic dev-stub curve');
  perform set_config('t.choice', ch_id::text, true);
end$$;
select isnt(
  (select chosen_by_person_id::text from public.pareto_weight_choices where id = current_setting('t.choice')::uuid),
  null::text,
  '[B2] point choice carries chosen_by_person_id (attribution)'
);
select ok(
  (select count(*) from public.audit_log
    where action = 'pareto_weight.chosen' and entity_id = current_setting('t.choice')::uuid) >= 1,
  '[B3] pareto_weight.chosen audit event written'
);

-- ============ [F] fabrication guard ============
select is(
  (select count(*) from public.pareto_curves        where validity_status = 'validated' or _dev_stub = false)
  + (select count(*) from public.pareto_curve_points where _dev_stub = false)
  + (select count(*) from public.pareto_weight_choices where _dev_stub = false),
  0::bigint,
  '[F1] no validated / non-stub rows in Pareto tables (synthetic-only)'
);

select * from finish();
rollback;
