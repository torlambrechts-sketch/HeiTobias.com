-- H-5 DIF Harness — discipline tests

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='dif_runs' and column_name='validity_status')
    then raise exception 'h5: dif_runs.validity_status missing'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='dif_items' and column_name='mh_dif_classification')
    then raise exception 'h5: dif_items.mh_dif_classification missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='dif_classify_mh')
    then raise exception 'h5: dif_classify_mh missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_dif_run_signoff')
    then raise exception 'h5: rpc_dif_run_signoff missing'; end if;
  raise notice 'h5: schema/RPC presence ok';
end$$;

do $$
declare v_dr int; v_di int;
begin
  select count(*) into v_dr from public.dif_runs where validity_status='validated';
  select count(*) into v_di from public.dif_items where validity_status='validated';
  if v_dr+v_di <> 0 then raise exception 'h5: validated rows present (DISCIPLINE)'; end if;
  raise notice 'h5: 0 validated rows';
end$$;

-- ETS classifier truth-table
do $$
begin
  if public.dif_classify_mh(0.5,  0.01) <> 'A' then raise exception 'h5: |.5| should be A'; end if;
  if public.dif_classify_mh(1.2,  0.01) <> 'B' then raise exception 'h5: |1.2| sig should be B'; end if;
  if public.dif_classify_mh(1.2,  0.50) <> 'A' then raise exception 'h5: |1.2| NS should be A'; end if;
  if public.dif_classify_mh(2.0,  0.01) <> 'C' then raise exception 'h5: |2.0| should be C'; end if;
  if public.dif_classify_mh(-1.8, 0.05) <> 'C' then raise exception 'h5: |-1.8| sign-invariant'; end if;
  if public.dif_classify_mh(null, null) is not null then raise exception 'h5: null should null-out'; end if;
  raise notice 'h5: dif_classify_mh ETS classification correct';
end$$;

-- Trigger derives bias_review_required from classification
do $$
declare v_org uuid; v_run_id uuid;
begin
  select id into v_org from public.organizations limit 1;
  if v_org is null then raise notice 'h5: no org; skipping'; return; end if;

  insert into public.dif_runs (org_id, instrument_key, reference_group, focal_group, method)
  values (v_org, 'h5-test', 'ref', 'focal', 'mantel_haenszel') returning id into v_run_id;

  insert into public.dif_items (run_id, item_key, effect_size, p_value, mh_dif_classification)
  values (v_run_id, 'item1', 0.4, 0.10, 'A');
  if exists (select 1 from public.dif_items where run_id=v_run_id and bias_review_required=true) then
    raise exception 'h5: A class should NOT require review';
  end if;

  update public.dif_items set mh_dif_classification='C' where run_id=v_run_id;
  if not exists (select 1 from public.dif_items where run_id=v_run_id and bias_review_required=true) then
    raise exception 'h5: C class should require review';
  end if;

  -- Cleanup
  delete from public.dif_items where run_id=v_run_id;
  delete from public.dif_runs where id=v_run_id;
  raise notice 'h5: bias_review_required trigger fires on classification change';
end$$;

-- RPC source guards
do $$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_dif_run_signoff';
  if v_src not like '%modeling.signoff%' then
    raise exception 'h5: rpc missing modeling.signoff gate'; end if;
  if v_src not like '%flagged items lack expert review%' then
    raise exception 'h5: rpc missing flagged-item review gate'; end if;
  raise notice 'h5: RPC guards present';
end$$;
