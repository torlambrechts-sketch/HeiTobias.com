-- 40_ops_part3_gap_closures — notifications + integrations + consent_revoke_by_purpose
-- T1 notifications_enqueue creates row + audit
-- T2 enqueue refuses non-admin
-- T3 integration_connector_upsert creates row
-- T4 upsert writes admin_decision
-- T5 connectors_for_org returns row
-- T6 upsert refuses <20-char rationale

begin;
select plan(6);

do $$
declare fjord constant uuid := 'a1000000-0000-0000-0000-000000000002';
  linnea constant uuid := 'b1000000-0000-0000-0000-000000000003';
  jonas constant uuid := 'b1000000-0000-0000-0000-000000000006';
  v_notif uuid; v_conn uuid; refused boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  v_notif := public.notifications_enqueue(fjord, jonas, 'in_app', 'Test subject', 'Test body', '{}'::jsonb);
  perform set_config('t.notif', v_notif::text, true);
  refused := false;
  perform set_config('request.jwt.claims', json_build_object('sub', jonas)::text, true);
  begin perform public.notifications_enqueue(fjord, linnea, 'in_app', 'X', 'Y', '{}'::jsonb);
  exception when others then refused := true; end;
  perform set_config('t.r2', case when refused then 'true' else 'false' end, true);
  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  v_conn := public.integration_connector_upsert(fjord, 'hibob', 'HiBob (demo)', 'not_configured', '{}'::jsonb,
    'Registering HiBob connector for the FjordTech ops layer — credentials wiring pending operator.');
  perform set_config('t.conn', v_conn::text, true);
  perform set_config('t.list_n', (select count(*)::text from public.integration_connectors_for_org(fjord)), true);
  refused := false;
  begin perform public.integration_connector_upsert(fjord, 'slack', 'X', 'not_configured', '{}'::jsonb, 'short');
  exception when others then refused := true; end;
  perform set_config('t.r5', case when refused then 'true' else 'false' end, true);
end$$;

select ok(
  current_setting('t.notif') is not null
  and (select count(*) from public.notifications where id = current_setting('t.notif')::uuid) = 1,
  '[T1] notifications_enqueue creates row');

select is(current_setting('t.r2'), 'true', '[T2] enqueue refuses non-admin');

select ok(
  current_setting('t.conn') is not null
  and (select count(*) from public.integration_connectors where id = current_setting('t.conn')::uuid) = 1,
  '[T3] integration_connector_upsert creates row');

select ok(
  exists (select 1 from public.admin_decisions where kind = 'integration_connector_change' and target_entity_id = current_setting('t.conn')::uuid),
  '[T4] integration upsert writes admin_decision');

select ok(current_setting('t.list_n')::int >= 1, '[T5] connectors_for_org returns the row');

select is(current_setting('t.r5'), 'true', '[T6] integration upsert refuses <20-char rationale');

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
