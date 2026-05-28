-- 21_phase4_step5_invariance_norms — Phase 4 Step 5 acceptance.
-- Verifies SCIENCE-SPEC §11 + Phase 4 prompt §5:
--   * norm_samples default _dev_stub=true; chk_norm_samples_validated_requires_real
--     refuses validated marker without sample_n>=100 AND _dev_stub=false
--   * invariance_run_record + invariance_result_record store statistics
--     WITHOUT a verdict (verdict NULL on insert)
--   * invariance_verdict_record requires modeling.signoff (refused in dev)
--   * dif_item_record sets flagged_for_review based on effect_size threshold
--     (INSPECTION TRIGGER, not verdict)
--   * fabrication guard: no validated / non-stub rows anywhere

begin;
select plan(9);

reset role;
insert into public.rbac_role_permissions (role_id, permission_id)
  select r.id, p.id from public.rbac_roles r cross join public.rbac_permissions p
  where r.org_id is null and r.key = 'people_ops_admin'
    and p.key in ('modeling.read','modeling.write') on conflict do nothing;

do $$
declare s_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  s_id := public.norm_sample_register(
    'sample_personality_v0', 'NO', 'nb',
    'a1000000-0000-0000-0000-000000000002'::uuid,
    null, null, null, 'DEV STUB Norwegian norm collection — pending real data', null);
  perform set_config('t.sample', s_id::text, true);
end$$;
select ok(
  (select _dev_stub from public.norm_samples where id = current_setting('t.sample')::uuid),
  '[A1] norm_sample defaults _dev_stub=true'
);
select is(
  (select validity_status::text from public.norm_samples where id = current_setting('t.sample')::uuid),
  'dev_stub',
  '[A2] norm_sample defaults validity_status=dev_stub'
);
-- The CHECK refuses validated unless sample_n>=100 AND _dev_stub=false.
reset role;
select throws_ok(
  format($q$update public.norm_samples set validity_status='validated'::public.validity_status where id = %L::uuid$q$, current_setting('t.sample')),
  '23514', NULL::text,
  '[A3] norm_sample cannot be marked validated without sample_n>=100 + _dev_stub=false'
);

-- ============ invariance run + result + verdict seam ============
do $$
declare r_id uuid; res_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  r_id := public.invariance_run_record(
    'a1000000-0000-0000-0000-000000000002'::uuid,
    'sample_personality_v0',
    jsonb_build_object('groups',jsonb_build_array('nb','sv','da')),
    'DEV STUB synthetic invariance run');
  res_id := public.invariance_result_record(r_id, 'configural',
    jsonb_build_object('nb',100,'sv',100,'da',100),
    0.97, 0.04, 0.03, null, null);
  perform set_config('t.run', r_id::text, true);
  perform set_config('t.res', res_id::text, true);
end$$;
select isnt(current_setting('t.res', true), '', '[B1] invariance_result row created');
select ok(
  (select invariance_verdict_by_expert is null from public.invariance_results where id = current_setting('t.res')::uuid),
  '[B2] invariance_verdict_by_expert NULL on insert (system never writes verdict)'
);
select throws_ok(
  format($q$select public.invariance_verdict_record(%L::uuid, 'configural invariance achieved by dev')$q$, current_setting('t.res')),
  'P0001', NULL::text,
  '[B3] invariance_verdict_record refused (modeling.signoff expert seam)'
);

-- ============ DIF item flag = inspection trigger ============
do $$
declare run_id uuid; item_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  run_id := public.dif_run_record(
    'a1000000-0000-0000-0000-000000000002'::uuid,
    'sample_personality_v0', 'reference_group_synthetic', 'focal_group_synthetic', 'mh',
    'DEV STUB synthetic DIF run');
  -- Effect size 0.15 > default threshold 0.10 → flagged
  item_id := public.dif_item_record(run_id, 'item_1', 0.15, 0.02, 0.10);
  perform set_config('t.dif_high', item_id::text, true);
  -- Effect size 0.05 < threshold → not flagged
  item_id := public.dif_item_record(run_id, 'item_2', 0.05, 0.50, 0.10);
  perform set_config('t.dif_low', item_id::text, true);
end$$;
select ok(
  (select flagged_for_review from public.dif_items where id = current_setting('t.dif_high')::uuid),
  '[C1] DIF item with |effect_size| >= threshold flagged_for_review (TRIGGER, not verdict)'
);
select is(
  (select flagged_for_review from public.dif_items where id = current_setting('t.dif_low')::uuid),
  false,
  '[C2] DIF item below threshold not flagged'
);

-- ============ fabrication guard ============
select is(
  (select count(*) from public.norm_samples where validity_status='validated' or _dev_stub=false)
  + (select count(*) from public.norm_percentiles where _dev_stub=false)
  + (select count(*) from public.invariance_runs where _dev_stub=false)
  + (select count(*) from public.invariance_results where _dev_stub=false)
  + (select count(*) from public.dif_runs where _dev_stub=false)
  + (select count(*) from public.dif_items where _dev_stub=false),
  0::bigint,
  '[D1] no validated / non-stub rows in Phase 4 Step 5 tables'
);

select * from finish();
rollback;
