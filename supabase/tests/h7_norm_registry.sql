-- H-7 Norm Sample Registry — discipline tests
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='norm_samples'
                    and column_name='is_continuous_norming')
    then raise exception 'h7: norm_samples.is_continuous_norming missing'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='norm_samples'
                    and column_name='adapted_from_citation_id')
    then raise exception 'h7: norm_samples.adapted_from_citation_id missing'; end if;
  if not exists (select 1 from information_schema.tables
                  where table_schema='public' and table_name='norm_sample_adaptations')
    then raise exception 'h7: norm_sample_adaptations missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='norm_sample_reuse_ready')
    then raise exception 'h7: norm_sample_reuse_ready missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_norm_sample_signoff')
    then raise exception 'h7: rpc_norm_sample_signoff missing'; end if;
  raise notice 'h7: schema/RPC presence ok';
end$$;

do $$
declare v_validated int;
begin
  select count(*) into v_validated from public.norm_samples where validity_status='validated';
  if v_validated <> 0 then raise exception 'h7: % validated samples — DISCIPLINE', v_validated; end if;
  raise notice 'h7: 0 validated norm samples';
end$$;

-- reuse_ready function with synthetic samples
do $$
declare v_id uuid; v_result jsonb;
begin
  -- Insert a tiny / unfit sample
  insert into public.norm_samples (org_id, instrument_key, sample_n, validity_status)
  values (null, 'h7-test', 50, 'dev_stub')
  returning id into v_id;

  v_result := public.norm_sample_reuse_ready(v_id);
  if (v_result->>'ready')::boolean <> false then
    raise exception 'h7: small dev_stub sample should not be ready, got %', v_result;
  end if;
  -- Should have at least: not_validated, sample_n_below_100, country_code_missing, repr_missing
  if jsonb_array_length(v_result->'reasons') < 3 then
    raise exception 'h7: expected >=3 reasons, got %', v_result;
  end if;

  -- Now mark it acceptable
  update public.norm_samples
     set sample_n = 500, country_code = 'NO',
         representativeness_notes = 'Representative of Norwegian working-age adults; quota-sampled across regions.',
         validity_status = 'validated', _dev_stub = false,
         signoff_actor_id = (select id from public.people limit 1),
         signoff_at = now(),
         signoff_rationale = 'Tested sample meets reuse criteria. We have a 500-person quota-sampled set with documented representativeness across Norwegian regions and age cohorts.'
   where id = v_id;

  v_result := public.norm_sample_reuse_ready(v_id);
  if (v_result->>'ready')::boolean <> true then
    raise exception 'h7: validated sample should be ready, got %', v_result;
  end if;

  -- Cleanup
  delete from public.norm_samples where id = v_id;
  raise notice 'h7: reuse_ready transitions stub→ready when criteria met';
end$$;

-- norm_sample_adaptations role enum
do $$
declare v_sid uuid; v_cid uuid;
begin
  select id into v_cid from public.citations where citation_key='follesdal-soto-2022-frontpsy';
  insert into public.norm_samples (org_id, instrument_key, sample_n)
  values (null, 'h7-adapt-test', 200)
  returning id into v_sid;
  begin
    insert into public.norm_sample_adaptations (sample_id, citation_id, role)
    values (v_sid, v_cid, 'bogus_role');
    raise exception 'h7: bogus role accepted';
  exception when check_violation then null;
  end;
  insert into public.norm_sample_adaptations (sample_id, citation_id, role)
  values (v_sid, v_cid, 'methodology_source');
  delete from public.norm_samples where id = v_sid;
  raise notice 'h7: adaptation role enum enforced';
end$$;
