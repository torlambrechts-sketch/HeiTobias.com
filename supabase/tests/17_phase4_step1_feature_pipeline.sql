-- 17_phase4_step1_feature_pipeline — Phase 4 Step 1 acceptance.
-- Verifies the load-bearing rules per the Phase 4 prompt + SCIENCE-SPEC:
--   * Only validly-consented subjects enter feature_rows
--   * Revoking research_anonymized blocks new feature rows (and the next
--     model_dataset_freeze excludes them)
--   * Lineage is preserved on every row (source_refs + consent_id + valid_at)
--   * Every row is _dev_stub=true and synthetic-only until experts engage
--   * feature_views.feature_kind allow-list refuses raw_trait (SCIENCE-SPEC §1)
--   * Fabrication guard: no row in any seed/fixture carries validity_status='validated'

begin;
select plan(13);

-- Setup: candidate placed + activated; have their consent_token; we'll
-- have them grant research_anonymized to FjordTech.
do $$
declare
  agency_a constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid; r_consent uuid; v_fv uuid; v_role uuid;
begin
  insert into public.people (full_name, primary_email) values ('P4 Subject', 'p4_'||gen_random_uuid()||'@p4.test') returning id into cand;
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
  perform public.hiring_decision_record(agency_req, cand,'hire','p4 fixture');
  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);
  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  perform public.placement_activate(placement_id);

  -- Candidate grants research_anonymized to FjordTech.
  perform set_config('request.jwt.claims','{}', true);
  r_consent := public.research_consent_grant(ct_token, employer_a);

  -- Register a feature view (as Linnea — needs org.manage_all, which she has).
  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  insert into public.feature_views (org_id, key, feature_kind, source_tables, feature_spec)
    values (employer_a, 'trait_range_fit_v0', 'trait_range_fit',
      array['assessment_scores','roles_catalog','profiles'],
      jsonb_build_object('description','DEV STUB trait-range fit feature','_dev_stub',true))
    returning id into v_fv;

  -- Use the placed role (the one Sigrid was matched against).
  select role_id into v_role from public.requisitions where id = agency_req;

  perform set_config('t.cand', cand::text, true);
  perform set_config('t.ct_token', ct_token, true);
  perform set_config('t.r_consent', r_consent::text, true);
  perform set_config('t.fv', v_fv::text, true);
  perform set_config('t.role', v_role::text, true);
end$$;

-- ============ [A] research_consent_grant + computed feature ============
-- Org-admin computes a feature for the consented subject.
-- (Need someone with org.manage_all in FjordTech who is also modeling-permissioned —
-- give Linnea modeling.read/write via the org_admin grant. Actually she's people_ops_admin,
-- not org_admin; the seed grants modeling to org_admin only. Let's grant it to
-- people_ops_admin for the test.)
reset role;
do $$
declare po_role uuid;
begin
  select id into po_role from public.rbac_roles where org_id is null and key = 'people_ops_admin';
  insert into public.rbac_role_permissions (role_id, permission_id)
    select po_role, p.id from public.rbac_permissions p where p.key in ('modeling.read','modeling.write')
    on conflict do nothing;
end$$;

do $$
declare row_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  row_id := public.feature_compute_trait_range_fit(
    current_setting('t.cand')::uuid,
    'a1000000-0000-0000-0000-000000000002'::uuid,
    current_setting('t.role')::uuid,
    current_setting('t.fv')::uuid);
  perform set_config('t.row', row_id::text, true);
end$$;
select is(
  (select consent_id from public.feature_rows where id = current_setting('t.row')::uuid),
  current_setting('t.r_consent')::uuid,
  '[A1] feature_row stamped with the research_anonymized consent_id'
);
select ok(
  (select _dev_stub from public.feature_rows where id = current_setting('t.row')::uuid),
  '[A2] feature_row _dev_stub = true (synthetic-only until experts engage)'
);
select ok(
  (select source_refs ? 'method' and source_refs ? 'role_id' and source_refs ? 'consent_id'
    from public.feature_rows where id = current_setting('t.row')::uuid),
  '[A3] feature_row carries source_refs lineage (method + role_id + consent_id)'
);

-- ============ [B] Subjects without research_anonymized are blocked ============
do $$
declare other_cand uuid;
begin
  insert into public.people (full_name, primary_email) values ('NoResearch','nr_'||gen_random_uuid()||'@p4.test') returning id into other_cand;
  perform set_config('t.other', other_cand::text, true);
end$$;
select throws_ok(
  format($$select public.feature_compute_trait_range_fit(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid, %L::uuid, %L::uuid)$$,
    current_setting('t.other'), current_setting('t.role'), current_setting('t.fv')),
  'P0001', NULL::text,
  '[B1] feature compute rejected for subject without research_anonymized consent'
);

-- ============ [C] model_dataset_freeze captures only consented subjects ============
do $$
declare ds uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  ds := public.model_dataset_freeze('a1000000-0000-0000-0000-000000000002'::uuid,
    current_setting('t.fv')::uuid, 'p4_test_ds_'||gen_random_uuid()::text);
  perform set_config('t.ds', ds::text, true);
end$$;
select is(
  (select subject_count from public.model_datasets where id = current_setting('t.ds')::uuid),
  1,
  '[C1] dataset captures exactly the one consented subject'
);
select is(
  (select source from public.model_datasets where id = current_setting('t.ds')::uuid),
  'synthetic',
  '[C2] dataset.source = synthetic (the only value allowed until validated)'
);
select ok(
  (select _dev_stub from public.model_datasets where id = current_setting('t.ds')::uuid),
  '[C3] dataset is marked _dev_stub'
);

-- model_dataset_subjects has the row pointing at the feature_row.
select ok(
  (select array_length(feature_row_ids, 1) >= 1
    from public.model_dataset_subjects
    where dataset_id = current_setting('t.ds')::uuid
      and person_id = current_setting('t.cand')::uuid),
  '[C4] dataset_subject carries the feature_row_ids that fed it'
);

-- ============ [D] Revocation drops them on the NEXT freeze ============
reset role;
do $$
begin
  update public.consent_grants set status='revoked', revoked_at=now()
    where id = current_setting('t.r_consent')::uuid;
end$$;
do $$
declare ds2 uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  ds2 := public.model_dataset_freeze('a1000000-0000-0000-0000-000000000002'::uuid,
    current_setting('t.fv')::uuid, 'p4_test_ds_post_revoke_'||gen_random_uuid()::text);
  perform set_config('t.ds2', ds2::text, true);
end$$;
select is(
  (select subject_count from public.model_datasets where id = current_setting('t.ds2')::uuid),
  0,
  '[D1] post-revoke freeze excludes the now-revoked subject'
);
-- And the new feature compute is also blocked.
select throws_ok(
  format($$select public.feature_compute_trait_range_fit(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid, %L::uuid, %L::uuid)$$,
    current_setting('t.cand'), current_setting('t.role'), current_setting('t.fv')),
  'P0001', NULL::text,
  '[D2] post-revoke feature compute is blocked for the same subject'
);

-- ============ [E] feature_kind allow-list refuses raw_trait ============
-- (Critical SCIENCE-SPEC §1 + §2: trait-range fit features, not raw traits)
reset role;
select throws_ok(
  $$insert into public.feature_views (org_id, key, feature_kind, source_tables)
    values ('a1000000-0000-0000-0000-000000000002', 'raw_trait_v0', 'raw_trait', array['x'])$$,
  '23514', NULL::text,
  '[E1] raw_trait feature_kind refused (SCIENCE-SPEC §1: trait-RANGE fit, not raw traits)'
);

-- ============ [F] Fabrication guard: no validated rows ============
select is(
  (select count(*) from public.feature_views where validity_status = 'validated')
  + (select count(*) from public.feature_rows where _dev_stub = false)
  + (select count(*) from public.model_datasets where validity_status = 'validated' or _dev_stub = false),
  0::bigint,
  '[F1] no validated / non-stub rows in the Phase 4 pipeline (synthetic-only)'
);

-- ============ [G] audit_log captures the freeze event ============
select ok(
  (select count(*) from public.audit_log
    where action = 'model_dataset.frozen' and entity_id = current_setting('t.ds')::uuid) >= 1,
  '[G1] model_dataset.frozen audit event written'
);

select * from finish();
rollback;
