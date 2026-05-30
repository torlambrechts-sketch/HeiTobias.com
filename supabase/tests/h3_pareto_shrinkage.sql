-- H-3 Pareto + Shrinkage Corrections — discipline tests

do $$
begin
  -- New columns on pareto_curves
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='pareto_curves'
                    and column_name='is_cross_validated')
    then raise exception 'h3: pareto_curves.is_cross_validated missing'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='pareto_curves'
                    and column_name='power_estimate')
    then raise exception 'h3: pareto_curves.power_estimate missing'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='pareto_curves'
                    and column_name='shrinkage_estimate')
    then raise exception 'h3: pareto_curves.shrinkage_estimate missing'; end if;
  -- New columns on pareto_weight_choices
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='pareto_weight_choices'
                    and column_name='validity_status')
    then raise exception 'h3: pareto_weight_choices.validity_status missing'; end if;
  -- CHECK constraint
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid
                  where t.relname='pareto_curves'
                    and c.conname='pc_validated_requires_cv_and_signoff')
    then raise exception 'h3: pc_validated_requires_cv_and_signoff CHECK missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_pareto_curve_signoff')
    then raise exception 'h3: rpc_pareto_curve_signoff missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_pareto_weight_choice_signoff')
    then raise exception 'h3: rpc_pareto_weight_choice_signoff missing'; end if;
  raise notice 'h3: schema/RPC presence ok';
end$$;

-- Discipline: no validated curves/choices in fixtures
do $$
declare v int;
begin
  select count(*) into v from public.pareto_curves where validity_status='validated';
  if v <> 0 then raise exception 'h3: % validated curves — DISCIPLINE BREACH', v; end if;
  select count(*) into v from public.pareto_weight_choices where validity_status='validated';
  if v <> 0 then raise exception 'h3: % validated weight_choices — DISCIPLINE BREACH', v; end if;
  raise notice 'h3: 0 validated rows across pareto surfaces';
end$$;

-- CHECK gates fire (uses real tx/rollback to seed prerequisites)
do $$
declare v_org uuid; v_curve_id uuid; v_person uuid; v_fv uuid;
begin
  select id into v_org from public.organizations limit 1;
  select id into v_person from public.people limit 1;
  if v_org is null or v_person is null then
    raise notice 'h3: no fixtures; skipping'; return; end if;

  -- Seed a feature_view + curve inline so the test is hermetic
  insert into public.feature_views (org_id, key, version, description, feature_kind, source_tables, feature_spec)
  values (v_org, 'h3-discipline-test-fv', 'v0', 'test', 'trait_range_fit',
          array['noop']::text[], '{}'::jsonb)
  returning id into v_fv;

  insert into public.pareto_curves
    (org_id, feature_view_id, key, default_weight_validity, validity_status, _dev_stub,
     is_cross_validated, sample_size)
  values (v_org, v_fv, 'h3-discipline-test', 0.5, 'dev_stub', true, false, 200)
  returning id into v_curve_id;

  -- (a) validated without is_cross_validated → CHECK fail
  begin
    update public.pareto_curves
       set validity_status='validated', _dev_stub=false,
           signoff_actor_id=v_person, signoff_at=now(),
           signoff_rationale='rationale that is at least one hundred characters long for testing the signoff path of pareto curves validated promotion'
     where id = v_curve_id;
    raise exception 'h3: validated w/o CV accepted';
  exception when check_violation then null; end;

  -- (b) validated WITH cv but WITHOUT power → CHECK fail
  update public.pareto_curves set is_cross_validated=true where id=v_curve_id;
  begin
    update public.pareto_curves
       set validity_status='validated', _dev_stub=false,
           signoff_actor_id=v_person, signoff_at=now(),
           signoff_rationale='rationale that is at least one hundred characters long for testing the signoff path of pareto curves validated promotion'
     where id = v_curve_id;
    raise exception 'h3: validated w/o power_estimate accepted';
  exception when check_violation then null; end;

  -- (c) full validate → ok
  update public.pareto_curves set power_estimate=0.85 where id=v_curve_id;
  update public.pareto_curves
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_person, signoff_at=now(),
         signoff_rationale='rationale that is at least one hundred characters long for testing the signoff path of pareto curves validated promotion'
   where id = v_curve_id;

  -- Cleanup
  delete from public.pareto_curves where id=v_curve_id;
  delete from public.feature_views where id=v_fv;
  raise notice 'h3: CHECK gates fire';
end$$;

-- RPC source guards
do $$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_pareto_curve_signoff';
  if v_src not like '%is_cross_validated is not true%' then
    raise exception 'h3: rpc_pareto_curve_signoff missing CV guard (Song 2017)'; end if;
  if v_src not like '%power_estimate is null%' then
    raise exception 'h3: rpc_pareto_curve_signoff missing power guard (Aguinis 2010)'; end if;

  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_pareto_weight_choice_signoff';
  if v_src not like '%underlying curve is not validated%' then
    raise exception 'h3: rpc_pareto_weight_choice_signoff missing underlying-curve check'; end if;
  raise notice 'h3: RPC source guards present (CV + power + chain)';
end$$;
