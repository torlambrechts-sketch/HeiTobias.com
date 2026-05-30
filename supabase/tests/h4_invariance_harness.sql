-- H-4 MGCFA Invariance Harness — discipline tests

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='invariance_runs'
                    and column_name='validity_status')
    then raise exception 'h4: invariance_runs.validity_status missing'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='invariance_runs'
                    and column_name='cutoff_standard')
    then raise exception 'h4: invariance_runs.cutoff_standard missing'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='invariance_results'
                    and column_name='passes_cutoff_by_standard')
    then raise exception 'h4: invariance_results.passes_cutoff_by_standard missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='invariance_evaluate_cutoffs')
    then raise exception 'h4: invariance_evaluate_cutoffs missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_invariance_run_signoff')
    then raise exception 'h4: rpc_invariance_run_signoff missing'; end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid
                  where t.relname='invariance_runs' and c.conname='ir_validated_requires_signoff')
    then raise exception 'h4: ir_validated_requires_signoff CHECK missing'; end if;
  raise notice 'h4: schema/RPC presence ok';
end$$;

-- Discipline: no validated rows
do $$
declare v_runs int; v_results int;
begin
  select count(*) into v_runs from public.invariance_runs where validity_status='validated';
  select count(*) into v_results from public.invariance_results where validity_status='validated';
  if v_runs+v_results <> 0 then
    raise exception 'h4: % runs / % results validated — DISCIPLINE BREACH', v_runs, v_results;
  end if;
  raise notice 'h4: 0 validated rows';
end$$;

-- Cutoff evaluator correctness — 5 reference cases
do $$
declare v_r jsonb;
begin
  -- All pass
  v_r := public.invariance_evaluate_cutoffs(-0.001, 0.005);
  if (v_r->>'cheung-rensvold-2002')::boolean is not true then raise exception 'h4: cr cutoff at -.001 should pass'; end if;
  if (v_r->>'meade-2008')::boolean is not true then raise exception 'h4: meade cutoff at -.001 should pass'; end if;
  if (v_r->>'chen-2007')::boolean is not true then raise exception 'h4: chen cutoff should pass'; end if;

  -- Meade fails (stricter)
  v_r := public.invariance_evaluate_cutoffs(-0.005, 0.005);
  if (v_r->>'meade-2008')::boolean is not false then raise exception 'h4: meade should fail at -.005'; end if;
  if (v_r->>'cheung-rensvold-2002')::boolean is not true then raise exception 'h4: cr should pass at -.005'; end if;

  -- All fail
  v_r := public.invariance_evaluate_cutoffs(-0.011, 0.005);
  if (v_r->>'cheung-rensvold-2002')::boolean is not false then raise exception 'h4: cr should fail at -.011'; end if;

  -- Chen fails on ΔRMSEA
  v_r := public.invariance_evaluate_cutoffs(-0.005, 0.020);
  if (v_r->>'chen-2007')::boolean is not false then raise exception 'h4: chen should fail when drmsea > .015'; end if;

  -- Null in, empty out
  v_r := public.invariance_evaluate_cutoffs(null, null);
  if v_r <> '{}'::jsonb then raise exception 'h4: null inputs should yield empty jsonb, got %', v_r; end if;

  raise notice 'h4: cutoff evaluator correct across 4 standards';
end$$;

-- Level + verdict enums
do $$
declare v_org uuid; v_run_id uuid;
begin
  select id into v_org from public.organizations limit 1;
  insert into public.invariance_runs (org_id, instrument_key, scope_json)
  values (v_org, 'h4-test-instrument', '{"groups":["a","b"]}'::jsonb)
  returning id into v_run_id;

  -- Invalid level
  begin
    insert into public.invariance_results (run_id, level)
    values (v_run_id, 'bogus');
    raise exception 'h4: invalid level accepted';
  exception when check_violation then null;
  end;

  -- Valid level
  insert into public.invariance_results (run_id, level) values (v_run_id, 'metric');

  -- Invalid verdict
  begin
    update public.invariance_results set invariance_verdict_by_expert='bogus' where run_id=v_run_id;
    raise exception 'h4: invalid verdict accepted';
  exception when check_violation then null;
  end;

  -- Valid verdict
  update public.invariance_results set invariance_verdict_by_expert='partial' where run_id=v_run_id;

  delete from public.invariance_results where run_id=v_run_id;
  delete from public.invariance_runs where id=v_run_id;
  raise notice 'h4: level + verdict enums enforced';
end$$;

-- RPC source guards
do $$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_invariance_run_signoff';
  if v_src not like '%has_permission(v_row.org_id, ''modeling.signoff'')%' then
    raise exception 'h4: rpc_invariance_run_signoff missing modeling.signoff gate'; end if;
  if v_src not like '%v_n_with_verdict <> v_n_results%' then
    raise exception 'h4: rpc_invariance_run_signoff missing verdict-completeness guard'; end if;
  if v_src not like '%cutoff_standard is null%' then
    raise exception 'h4: rpc_invariance_run_signoff missing cutoff_standard guard'; end if;
  raise notice 'h4: RPC guards present';
end$$;
