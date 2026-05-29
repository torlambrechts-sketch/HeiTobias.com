-- 33_team_definition_cp33_divergence — rpc_compute_divergence assertions.
--
-- The divergence RPC is the gate between Stage 2 sealing and Stage 3
-- review. It is also the FIRST consumer of the just-sealed evaluation
-- rows; if it leaks data pre-seal, the whole methodology breaks.
--
-- T14  rpc_compute_divergence rejects calls while run.stage = 'rating'
-- T15  Post-seal: returns a non-empty `criteria` payload with per-
--      criterion mean/min/max + per-evaluator `values` (positions,
--      not just average)
-- T16  Consensus category derives from SD: low if SD >= cutoff (1.4
--      stub), moderate if SD >= cutoff/2, otherwise high
-- T17  Rows are written to team_definition_divergence_runs and the
--      run gets a consensus_summary_json stamp
-- T18  The audit_log carries a 'team_def.divergence_computed' row

begin;
select plan(8);

do $$
declare
  fjord        constant uuid := 'a1000000-0000-0000-0000-000000000002';
  linnea       constant uuid := 'b1000000-0000-0000-0000-000000000003';
  sara         constant uuid := 'b1000000-0000-0000-0000-000000000005';
  erik         constant uuid := 'b1000000-0000-0000-0000-000000000004';
  jonas        constant uuid := 'b1000000-0000-0000-0000-000000000006';
  p4_auth      uuid := gen_random_uuid();
  p4           uuid;
  membership4  uuid;
  emp_role     uuid;
  template_id  uuid;
  run_id       uuid;
begin
  select id into emp_role from public.rbac_roles where key='employee';
  select id into template_id from public.roles_catalog where is_template=true and family='engineering' limit 1;

  insert into auth.users (id, email) values (p4_auth, 't33_p4_'||gen_random_uuid()||'@fjord.test');
  insert into public.people (full_name, primary_email, auth_user_id)
    values ('T33 Fourth Evaluator', 't33_p4_'||p4_auth||'@fjord.test', p4_auth) returning id into p4;
  insert into public.memberships (org_id, person_id, status) values (fjord, p4, 'active') returning id into membership4;
  insert into public.membership_roles (membership_id, rbac_role_id) values (membership4, emp_role);

  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  run_id := public.rpc_create_role_definition_run(
    fjord, 'engineering', template_id, 'initial_definition', now() + interval '14 days',
    jsonb_build_array(
      jsonb_build_object('person_id', sara,  'role', 'manager'),
      jsonb_build_object('person_id', erik,  'role', 'peer_team_lead'),
      jsonb_build_object('person_id', jonas, 'role', 'team_member'),
      jsonb_build_object('person_id', p4,    'role', 'team_member')
    )
  );

  -- Submit deliberately diverse ratings:
  --   criticality.design_review:    5, 5, 4, 4   -> SD~0.58  -> high consensus
  --   criticality.production_oncall: 5, 1, 5, 1  -> SD~2.31  -> low consensus (>= 1.4)
  --   competency_weights.tech:      0.30, 0.31, 0.29, 0.30 -> SD~0.008 -> high
  perform set_config('request.jwt.claims', json_build_object('sub', sara)::text, true);
  perform public.rpc_submit_evaluation(run_id,
    '{"criticality":{"design_review":5,"production_oncall":5},"competency_weights":{"tech":0.30}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', erik)::text, true);
  perform public.rpc_submit_evaluation(run_id,
    '{"criticality":{"design_review":5,"production_oncall":1},"competency_weights":{"tech":0.31}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', jonas)::text, true);
  perform public.rpc_submit_evaluation(run_id,
    '{"criticality":{"design_review":4,"production_oncall":5},"competency_weights":{"tech":0.29}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', p4_auth)::text, true);
  perform public.rpc_submit_evaluation(run_id,
    '{"criticality":{"design_review":4,"production_oncall":1},"competency_weights":{"tech":0.30}}'::jsonb);

  perform set_config('t.run_id',  run_id::text,  true);
  perform set_config('t.linnea',  linnea::text,  true);
end$$;

-- ============ T14 — rpc_compute_divergence rejects pre-seal ============
do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin
    perform public.rpc_compute_divergence(current_setting('t.run_id')::uuid);
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t14_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t14_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t14_refused'), 'true',
  '[T14] rpc_compute_divergence refuses while stage=rating | err='||current_setting('t.t14_errmsg'));

-- ============ Seal (so we can test post-seal flow) ============
do $$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  perform public.rpc_seal_evaluations(current_setting('t.run_id')::uuid);
end$$;

-- ============ Compute divergence + capture result ============
do $$
declare r jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  r := public.rpc_compute_divergence(current_setting('t.run_id')::uuid);
  perform set_config('t.div_result', r::text, true);
end$$;

-- T15: criteria array non-empty + has per-evaluator values
select ok(
  (current_setting('t.div_result')::jsonb -> 'criteria') is not null
  and jsonb_array_length(current_setting('t.div_result')::jsonb -> 'criteria') = 3,
  '[T15a] Divergence result has 3 criteria (design_review + production_oncall + tech_weight) | count='
  || jsonb_array_length(current_setting('t.div_result')::jsonb -> 'criteria')::text
);

-- T15b: per-evaluator `values` array preserves per-position (no averaging)
select ok(
  (
    select bool_and(
      jsonb_typeof(c -> 'values') = 'array'
      and jsonb_array_length(c -> 'values') = 4
    )
    from jsonb_array_elements(current_setting('t.div_result')::jsonb -> 'criteria') c
  ),
  '[T15b] Every criterion carries a `values` array of 4 per-evaluator positions (surfaced, not averaged)'
);

-- T16a: high-consensus for design_review (SD ~ 0.58, well below 1.4 cutoff)
select is(
  (
    select c ->> 'consensus_category'
    from jsonb_array_elements(current_setting('t.div_result')::jsonb -> 'criteria') c
    where c ->> 'criterion_key' = 'criticality.design_review'
    limit 1
  ),
  'high',
  '[T16a] Tight ratings (SD~0.58) → high consensus'
);

-- T16b: low-consensus for production_oncall (SD ~ 2.31, well above 1.4 cutoff)
select is(
  (
    select c ->> 'consensus_category'
    from jsonb_array_elements(current_setting('t.div_result')::jsonb -> 'criteria') c
    where c ->> 'criterion_key' = 'criticality.production_oncall'
    limit 1
  ),
  'low',
  '[T16b] Split ratings (SD~2.31) → low consensus'
);

-- T17a: rows written to team_definition_divergence_runs
select is(
  (select count(*)::int from public.team_definition_divergence_runs where run_id = current_setting('t.run_id')::uuid),
  3,
  '[T17a] 3 rows persisted in team_definition_divergence_runs'
);

-- T17b: run.consensus_summary_json gets stamped
select ok(
  (select (consensus_summary_json -> 'total_criteria')::int = 3
   and consensus_summary_json ? 'high' and consensus_summary_json ? 'moderate' and consensus_summary_json ? 'low'
   from public.team_definition_runs where id = current_setting('t.run_id')::uuid),
  '[T17b] run.consensus_summary_json stamped with high/moderate/low + total_criteria'
);

-- T18: audit_log row written
select ok(
  exists (
    select 1 from public.audit_log
    where entity_id = current_setting('t.run_id')::uuid
      and action = 'team_def.divergence_computed'
  ),
  '[T18] audit_log carries team_def.divergence_computed row'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
