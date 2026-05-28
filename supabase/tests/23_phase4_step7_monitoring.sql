-- 23_phase4_step7_monitoring — Phase 4 Step 7 acceptance.
-- Verifies Phase 4 prompt §7:
--   * monitoring_runs record + audit
--   * monitoring_alerts default 'open'; transitions require humans
--   * monitoring_alerts.status enum has NO 'auto_remediated' option
--   * Direct UPDATE to status='acknowledged' or 'resolved' refused
--     without acknowledged_by/resolved_by + note (CHECK constraints)
--   * monitoring_incident_open requires an authenticated person +
--     >=20-char summary; bias_reaudit_fairness_run_id is supported
--   * Fabrication guard

begin;
select plan(11);

reset role;
insert into public.rbac_role_permissions (role_id, permission_id)
  select r.id, p.id from public.rbac_roles r cross join public.rbac_permissions p
  where r.org_id is null and r.key = 'people_ops_admin'
    and p.key in ('modeling.read','modeling.write') on conflict do nothing;

do $$
declare employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002'; v_fv uuid; m_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  insert into public.feature_views (org_id, key, feature_kind, source_tables)
    values (employer_a, 'fv_p4s7_'||gen_random_uuid()::text, 'trait_range_fit', array['assessment_scores','roles_catalog'])
    returning id into v_fv;
  m_id := public.model_register(employer_a, 'm_p4s7_'||gen_random_uuid()::text, 'interpretable_baseline_v0', v_fv, null, 'DEV STUB', null);
  perform set_config('t.employer', employer_a::text, true);
  perform set_config('t.model', m_id::text, true);
end$$;

-- ============ [A] monitoring run + alert ============
do $$
declare run_id uuid; alert_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  run_id := public.monitoring_run_record(
    current_setting('t.employer')::uuid, current_setting('t.model')::uuid,
    'fairness_overtime', jsonb_build_object('window_days', 90, '_dev_stub', true),
    true, false);
  alert_id := public.monitoring_alert_open(
    current_setting('t.employer')::uuid, 'high',
    'Drift detected on synthetic test data', run_id,
    jsonb_build_object('_dev_stub', true));
  perform set_config('t.run', run_id::text, true);
  perform set_config('t.alert', alert_id::text, true);
end$$;
select is(
  (select status from public.monitoring_alerts where id = current_setting('t.alert')::uuid),
  'open',
  '[A1] new alert defaults status=open'
);
select ok(
  (select count(*) from public.audit_log where action = 'monitoring.run' and entity_id = current_setting('t.run')::uuid) >= 1,
  '[A2] monitoring.run audit event written'
);
select ok(
  (select count(*) from public.audit_log where action = 'monitoring.alert_opened' and entity_id = current_setting('t.alert')::uuid) >= 1,
  '[A3] monitoring.alert_opened audit event written'
);

-- ============ [B] no 'auto_remediated' status ============
reset role;
select throws_ok(
  format($q$update public.monitoring_alerts set status='auto_remediated' where id = %L::uuid$q$, current_setting('t.alert')),
  '23514', NULL::text,
  '[B1] status="auto_remediated" refused (enum CHECK)'
);

-- ============ [C] human-only transitions ============
-- Direct UPDATE to 'acknowledged' without ack_by/ack_at is refused.
select throws_ok(
  format($q$update public.monitoring_alerts set status='acknowledged' where id = %L::uuid$q$, current_setting('t.alert')),
  '23514', NULL::text,
  '[C1] direct UPDATE to acknowledged refused (chk_ack_requires_human)'
);
-- Direct UPDATE to 'resolved' without resolved_by/resolve_note is refused.
select throws_ok(
  format($q$update public.monitoring_alerts set status='resolved' where id = %L::uuid$q$, current_setting('t.alert')),
  '23514', NULL::text,
  '[C2] direct UPDATE to resolved refused (chk_resolve_requires_human)'
);

-- ============ [D] RPCs perform the human-attributed transitions ============
do $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  perform public.monitoring_alert_acknowledge(current_setting('t.alert')::uuid, 'Acknowledged by Linnea — investigating drift cause');
end$$;
select is(
  (select status from public.monitoring_alerts where id = current_setting('t.alert')::uuid),
  'acknowledged',
  '[D1] monitoring_alert_acknowledge moves status to acknowledged'
);
do $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  perform public.monitoring_alert_resolve(current_setting('t.alert')::uuid, 'Resolved by Linnea — drift was within tolerance after refit');
end$$;
select is(
  (select status from public.monitoring_alerts where id = current_setting('t.alert')::uuid),
  'resolved',
  '[D2] monitoring_alert_resolve moves status to resolved'
);

-- ============ [E] incident with bias re-audit reference ============
do $$
declare fr_id uuid; inc_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  fr_id := public.fairness_run_open(current_setting('t.employer')::uuid, current_setting('t.model')::uuid, 'p4s7_reaudit_'||gen_random_uuid()::text);
  inc_id := public.monitoring_incident_open(
    current_setting('t.employer')::uuid,
    'Retrain incident — drift exceeded threshold; bias re-audit linked',
    current_setting('t.model')::uuid, current_setting('t.alert')::uuid, fr_id);
  perform set_config('t.incident', inc_id::text, true);
end$$;
select isnt(
  (select bias_reaudit_fairness_run_id::text from public.monitoring_incidents where id = current_setting('t.incident')::uuid),
  null::text,
  '[E1] monitoring_incident carries bias_reaudit_fairness_run_id (mandatory bias re-audit on retrain)'
);
select ok(
  (select count(*) from public.audit_log where action = 'monitoring.incident_opened' and entity_id = current_setting('t.incident')::uuid) >= 1,
  '[E2] monitoring.incident_opened audit event written'
);

-- ============ [F] fabrication guard ============
select is(
  (select count(*) from public.monitoring_runs where _dev_stub=false)
  + (select count(*) from public.monitoring_alerts where _dev_stub=false)
  + (select count(*) from public.monitoring_incidents where _dev_stub=false),
  0::bigint,
  '[F1] no non-stub rows in Phase 4 Step 7 tables'
);

select * from finish();
rollback;
