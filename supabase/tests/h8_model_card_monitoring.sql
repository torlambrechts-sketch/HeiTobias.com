-- H-8 Model Card + Monitoring discipline tests
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='model_cards'
                    and column_name='monitoring_plan_json')
    then raise exception 'h8: model_cards.monitoring_plan_json missing'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='model_cards'
                    and column_name='human_oversight_plan')
    then raise exception 'h8: model_cards.human_oversight_plan missing'; end if;
  if not exists (select 1 from pg_constraint where conname='mc_validated_requires_full')
    then raise exception 'h8: mc_validated_requires_full CHECK missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_model_card_signoff')
    then raise exception 'h8: rpc_model_card_signoff missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_monitoring_alert_acknowledge')
    then raise exception 'h8: rpc_monitoring_alert_acknowledge missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_monitoring_incident_close')
    then raise exception 'h8: rpc_monitoring_incident_close missing'; end if;
  raise notice 'h8: schema/RPC presence ok';
end$$;

-- Discipline + CHECK
do $$
declare v_org uuid; v_model_id uuid; v_card_id uuid; v_person uuid;
begin
  select id into v_org from public.organizations limit 1;
  select id into v_person from public.people limit 1;
  if v_org is null then raise notice 'h8: no fixtures'; return; end if;

  -- Insert minimal model + card
  insert into public.model_registry (org_id, key, version, family, validity_status, _dev_stub)
  values (v_org, 'h8-test-model', 'v0', 'fit', 'dev_stub', true) returning id into v_model_id;

  insert into public.model_cards (model_id, intended_use, validity_status, _dev_stub)
  values (v_model_id, 'short use', 'dev_stub', true) returning id into v_card_id;

  -- Try to validate without the required fields → CHECK should fire
  begin
    update public.model_cards
       set validity_status='validated', _dev_stub=false,
           signed_off_by=v_person, signed_off_at=now(),
           signoff_rationale='rationale long enough for the 100-char minimum to clear the load-bearing CHECK constraint requiring full validation metadata'
     where id = v_card_id;
    raise exception 'h8: validated with short intended_use accepted';
  exception when check_violation then null;
  end;

  -- Fill in full metadata, then validate succeeds
  update public.model_cards
     set intended_use = repeat('detailed intended use describing what this model is for, how it should be used, who the users are, what it predicts, ', 2),
         ethical_considerations = repeat('detailed ethical considerations covering fairness, transparency, accountability, and potential harms; ', 2),
         human_oversight_plan = 'human-in-the-loop required for every consequential decision per AI Act Art. 14',
         transparency_disclosures_text = 'this model outputs a fit indicator to support human hiring decisions, not to auto-decide',
         monitoring_plan_json = '{"cadence":"monthly","metrics":["air","calibration","drift"]}'::jsonb,
         limits_json = '{"min_sample":100,"contraindications":["under-18 candidates"]}'::jsonb,
         data_lineage_json = '{"sources":["assessment_responses"],"versions":{"feature_view":"v1"}}'::jsonb,
         fairness_metrics_json = '{"air":0.85,"slope_test_p":0.40}'::jsonb,
         validity_status='validated', _dev_stub=false,
         signed_off_by=v_person, signed_off_at=now(),
         signoff_rationale='rationale long enough for the 100-char minimum to clear the load-bearing CHECK constraint requiring full validation metadata'
   where id = v_card_id;

  -- Cleanup
  delete from public.model_cards where id = v_card_id;
  delete from public.model_registry where id = v_model_id;
  raise notice 'h8: model card validated only after full metadata + signoff';
end$$;

-- Monitoring alert status + severity enums
do $$
declare v_org uuid; v_run_id uuid; v_alert_id uuid; v_model_id uuid;
begin
  select id into v_org from public.organizations limit 1;
  insert into public.model_registry (org_id, key, version, family) values (v_org, 'h8-alert-model', 'v0', 'fit') returning id into v_model_id;
  insert into public.monitoring_runs (org_id, model_id, kind, payload_json)
  values (v_org, v_model_id, 'drift_check', '{}'::jsonb) returning id into v_run_id;

  -- Invalid severity
  begin
    insert into public.monitoring_alerts (org_id, run_id, severity, message)
    values (v_org, v_run_id, 'bogus', 'test');
    raise exception 'h8: bogus severity accepted';
  exception when check_violation then null;
  end;
  -- Invalid status
  begin
    insert into public.monitoring_alerts (org_id, run_id, severity, message, status)
    values (v_org, v_run_id, 'warning', 'test', 'bogus');
    raise exception 'h8: bogus status accepted';
  exception when check_violation then null;
  end;

  -- Valid insert
  insert into public.monitoring_alerts (org_id, run_id, severity, message, status)
  values (v_org, v_run_id, 'critical', 'test', 'open') returning id into v_alert_id;

  -- Cleanup
  delete from public.monitoring_alerts where id = v_alert_id;
  delete from public.monitoring_runs where id = v_run_id;
  delete from public.model_registry where id = v_model_id;
  raise notice 'h8: alert severity + status enums enforced';
end$$;
