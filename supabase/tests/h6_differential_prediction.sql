-- H-6 Differential Prediction + Power — discipline tests

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='fairness_runs'
                    and column_name='validity_status')
    then raise exception 'h6: fairness_runs.validity_status missing'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='fairness_runs'
                    and column_name='power_estimate')
    then raise exception 'h6: fairness_runs.power_estimate missing'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='fairness_metrics'
                    and column_name='over_prediction_flag')
    then raise exception 'h6: fairness_metrics.over_prediction_flag missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='fairness_summarize_air')
    then raise exception 'h6: fairness_summarize_air missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_fairness_run_signoff')
    then raise exception 'h6: rpc_fairness_run_signoff missing'; end if;
  raise notice 'h6: schema/RPC presence ok';
end$$;

do $$
declare v int;
begin
  select count(*) into v from public.fairness_runs where validity_status='validated';
  if v <> 0 then raise exception 'h6: % validated fairness_runs', v; end if;
  select count(*) into v from public.fairness_metrics where validity_status='validated';
  if v <> 0 then raise exception 'h6: % validated fairness_metrics', v; end if;
  raise notice 'h6: 0 validated rows';
end$$;

-- fairness_summarize_air truth table
do $$
declare v_r jsonb;
begin
  v_r := public.fairness_summarize_air(0.85, 0.40, 0.95);
  if (v_r->>'passes_four_fifths')::boolean is not true then raise exception 'h6: .85 should pass 4/5'; end if;
  if (v_r->>'statistically_significant')::boolean is not false then raise exception 'h6: p=.4 NS'; end if;
  if (v_r->>'low_power_caveat')::boolean is not false then raise exception 'h6: power .95 not low'; end if;

  v_r := public.fairness_summarize_air(0.75, 0.01, 0.95);
  if (v_r->>'passes_four_fifths')::boolean is not false then raise exception 'h6: .75 should fail 4/5'; end if;
  if (v_r->>'statistically_significant')::boolean is not true then raise exception 'h6: p=.01 sig'; end if;

  v_r := public.fairness_summarize_air(0.80, 0.10, 0.50);
  if (v_r->>'passes_four_fifths')::boolean is not true then raise exception 'h6: .80 should pass 4/5'; end if;
  if (v_r->>'low_power_caveat')::boolean is not true then raise exception 'h6: power .5 should flag low power'; end if;

  v_r := public.fairness_summarize_air(null, null, null);
  if v_r <> '{}'::jsonb then raise exception 'h6: null in empty out'; end if;

  raise notice 'h6: AIR + 4/5ths + power caveat summary correct';
end$$;

-- Interpretation enum
do $$
declare v_org uuid; v_run uuid;
begin
  select id into v_org from public.organizations limit 1;
  insert into public.fairness_runs (org_id, key, scope_json)
  values (v_org, 'h6-test', '{}'::jsonb) returning id into v_run;

  begin
    insert into public.fairness_metrics (run_id, characteristic, reference_group, protected_group,
      interpretation_by_expert)
    values (v_run, 'sex', 'male', 'female', 'bogus_value');
    raise exception 'h6: invalid interpretation accepted';
  exception when check_violation then null;
  end;

  insert into public.fairness_metrics (run_id, characteristic, reference_group, protected_group,
    interpretation_by_expert)
  values (v_run, 'sex', 'male', 'female', 'monitor');

  delete from public.fairness_metrics where run_id=v_run;
  delete from public.fairness_runs where id=v_run;
  raise notice 'h6: interpretation enum enforced';
end$$;

-- RPC source guards
do $$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_fairness_run_signoff';
  if v_src not like '%power_estimate is null%' then
    raise exception 'h6: rpc missing power guard (Aguinis 2010)'; end if;
  if v_src not like '%metrics lack expert interpretation%' then
    raise exception 'h6: rpc missing interpretation completeness guard'; end if;
  raise notice 'h6: RPC guards present';
end$$;
