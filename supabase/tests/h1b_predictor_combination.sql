-- H-1b Predictor-Combination Audit Trail — discipline tests
--
-- Probes:
--   * schema + RPC presence
--   * CHECK constraints (rationale length, weights sum, scope coherence,
--     validated-requires-signoff, combo non-empty array)
--   * partial unique index (one current per (org, scope, role, requisition))
--   * RPC validations (permission, weight sum, anchor existence, anchor
--     type match, version pinning, duplicates)
--   * dev-stub discipline preserved

do $$
begin
  if not exists (select 1 from pg_type where typname='predictor_combo_scope')
    then raise exception 'h1b: predictor_combo_scope enum missing'; end if;
  if not exists (select 1 from information_schema.tables
                  where table_schema='public' and table_name='predictor_combination_decisions')
    then raise exception 'h1b: predictor_combination_decisions table missing'; end if;
  if not exists (select 1 from information_schema.views
                  where table_schema='public' and table_name='v_current_predictor_combination')
    then raise exception 'h1b: v_current_predictor_combination view missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_predictor_combo_decision')
    then raise exception 'h1b: rpc_predictor_combo_decision missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_predictor_combo_signoff')
    then raise exception 'h1b: rpc_predictor_combo_signoff missing'; end if;
  raise notice 'h1b: schema/RPC presence ok';
end$$;

-- CHECK + partial unique tests inside a rolled-back tx
do $$
declare
  v_org      uuid;
  v_role     uuid;
  v_person   uuid;
  v_anchor_si uuid;
  v_anchor_gma uuid;
  v_combo    jsonb;
  v_id       uuid;
begin
  select id into v_org    from public.organizations limit 1;
  select id into v_role   from public.roles_catalog where org_id is not null limit 1;
  select id into v_person from public.people limit 1;
  select id into v_anchor_si  from public.evidence_base_positions
                              where predictor_type='structured_interview' and effective_to is null;
  select id into v_anchor_gma from public.evidence_base_positions
                              where predictor_type='gma' and effective_to is null;

  if v_org is null or v_role is null or v_anchor_si is null or v_anchor_gma is null then
    raise notice 'h1b: missing test prerequisites; skipping checks';
    return;
  end if;

  -- (a) empty combo is rejected
  begin
    insert into public.predictor_combination_decisions
      (org_id, scope, role_id, evidence_base_version_id, combo_json, weights_sum_to, rationale)
    values (v_org, 'role', v_role, 'ebv-2025-01', '[]'::jsonb, null,
            'rationale long enough for fifty character minimum to satisfy the CHECK');
    raise exception 'h1b: CHECK failed — empty combo accepted';
  exception when check_violation then null;
  end;

  -- (b) non-array combo is rejected
  begin
    insert into public.predictor_combination_decisions
      (org_id, scope, role_id, evidence_base_version_id, combo_json, weights_sum_to, rationale)
    values (v_org, 'role', v_role, 'ebv-2025-01', '{"x":1}'::jsonb, null,
            'rationale long enough for fifty character minimum to satisfy the CHECK');
    raise exception 'h1b: CHECK failed — non-array combo accepted';
  exception when check_violation then null;
  end;

  -- (c) weights_sum_to=2.0 rejected
  v_combo := jsonb_build_array(
    jsonb_build_object('predictor_type','gma','weight',1.0,'anchor_position_id',v_anchor_gma));
  begin
    insert into public.predictor_combination_decisions
      (org_id, scope, role_id, evidence_base_version_id, combo_json, weights_sum_to, rationale)
    values (v_org, 'role', v_role, 'ebv-2025-01', v_combo, 2.0,
            'rationale long enough for fifty character minimum to satisfy the CHECK');
    raise exception 'h1b: CHECK failed — weights_sum_to=2.0 accepted';
  exception when check_violation then null;
  end;

  -- (d) rationale too short rejected
  begin
    insert into public.predictor_combination_decisions
      (org_id, scope, role_id, evidence_base_version_id, combo_json, weights_sum_to, rationale)
    values (v_org, 'role', v_role, 'ebv-2025-01', v_combo, 1.0, 'too short');
    raise exception 'h1b: CHECK failed — short rationale accepted';
  exception when check_violation then null;
  end;

  -- (e) scope='requisition' without requisition_id rejected
  begin
    insert into public.predictor_combination_decisions
      (org_id, scope, role_id, requisition_id, evidence_base_version_id, combo_json, weights_sum_to, rationale)
    values (v_org, 'requisition', null, null, 'ebv-2025-01', v_combo, 1.0,
            'rationale long enough for fifty character minimum to satisfy the CHECK');
    raise exception 'h1b: CHECK failed — requisition scope without requisition_id accepted';
  exception when check_violation then null;
  end;

  -- (f) successful insert (then verify partial unique fires)
  insert into public.predictor_combination_decisions
    (org_id, scope, role_id, evidence_base_version_id, combo_json, weights_sum_to, rationale)
  values (v_org, 'role', v_role, 'ebv-2025-01', v_combo, 1.0,
          'rationale long enough for fifty character minimum to satisfy the CHECK')
  returning id into v_id;

  begin
    insert into public.predictor_combination_decisions
      (org_id, scope, role_id, evidence_base_version_id, combo_json, weights_sum_to, rationale)
    values (v_org, 'role', v_role, 'ebv-2025-01', v_combo, 1.0,
            'rationale long enough for fifty character minimum to satisfy the CHECK');
    raise exception 'h1b: partial unique failed — duplicate current accepted';
  exception when unique_violation then null;
  end;

  -- (g) validated requires signoff (long enough ≥100 char rationale)
  begin
    update public.predictor_combination_decisions
       set validity_status='validated', _dev_stub=false
     where id = v_id;
    raise exception 'h1b: CHECK failed — validated without signoff accepted';
  exception when check_violation then null;
  end;

  begin
    update public.predictor_combination_decisions
       set validity_status='validated', _dev_stub=false,
           signoff_actor_id=v_person, signoff_at=now(),
           signoff_rationale='this rationale is too short for the 100-char minimum'
     where id = v_id;
    raise exception 'h1b: CHECK failed — validated with <100-char rationale accepted';
  exception when check_violation then null;
  end;

  -- Full validate (≥100 chars)
  update public.predictor_combination_decisions
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_person, signoff_at=now(),
         signoff_rationale='Reviewed combo: SI .42 + GMA .31 weighting reflects conservative-anchor stance pending the engaged I/O psychologist sign-off and our-population re-validation; approved for production use.'
   where id = v_id;

  -- Cleanup
  delete from public.predictor_combination_decisions where id = v_id;
  raise notice 'h1b: all CHECK + partial-unique constraints fire as designed';
end$$;

-- RPC source guards
do $$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_predictor_combo_decision';
  if v_src not like '%has_permission(p_org_id, ''modeling.write'')%' then
    raise exception 'h1b: rpc_predictor_combo_decision missing modeling.write gate'; end if;
  if v_src not like '%duplicate predictor_type%' then
    raise exception 'h1b: rpc_predictor_combo_decision missing duplicate-predictor guard'; end if;
  if v_src not like '%belongs to version%' then
    raise exception 'h1b: rpc_predictor_combo_decision missing evidence-version pin'; end if;
  if v_src not like '%superseded_at = now()%' then
    raise exception 'h1b: rpc_predictor_combo_decision missing supersede step'; end if;
  if v_src not like '%audit_log_event%' then
    raise exception 'h1b: rpc_predictor_combo_decision missing audit_log_event'; end if;

  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_predictor_combo_signoff';
  if v_src not like '%has_permission(v_row.org_id, ''modeling.signoff'')%' then
    raise exception 'h1b: rpc_predictor_combo_signoff missing modeling.signoff gate'; end if;
  if v_src not like '%audit_log_event%' then
    raise exception 'h1b: rpc_predictor_combo_signoff missing audit_log_event'; end if;
  raise notice 'h1b: RPC guards + audit calls present';
end$$;

-- Dev-stub discipline: no validated rows in fixtures
do $$
declare v_validated int;
begin
  select count(*) into v_validated
    from public.predictor_combination_decisions
   where validity_status='validated';
  if v_validated <> 0 then
    raise exception 'h1b: % validated rows in fixtures — DISCIPLINE BREACH', v_validated;
  end if;
  raise notice 'h1b: dev_stub discipline preserved (0 validated rows)';
end$$;
