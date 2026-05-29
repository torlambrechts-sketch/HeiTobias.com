-- 32_team_definition_cp31_independence — load-bearing methodology assertions
-- for Team-Based Role Definition CP3.1 (schema + RPCs).
--
-- The whole methodology hinges on Stage 2 independence. If any of T1-T5
-- regresses, silent averaging or coercion becomes possible and the Delphi
-- guarantee is gone. T6 asserts the run state-machine gate.
--
-- IMPORTANT: every test block that exercises RLS does `set local role
-- authenticated;` first, because postgres + service_role have BYPASSRLS.
-- Setup blocks that need direct INSERTs into auth.users / public.people
-- run as the default (elevated) role; SECDEF RPC calls work from either.
--
-- T1  Evaluator A cannot direct-SELECT Evaluator B's row pre-seal
-- T2  Run owner cannot direct-SELECT any row pre-seal (counter-intuitive
--     but intentional - owner reads via the audited SECDEF RPC)
-- T3  rpc_team_definition_evaluations_for_owner during stage='rating'
--     writes audit_log row with action='team_def.read_during_seal' AND
--     returns empty rows
-- T4  After rpc_seal_evaluations: owner sees all rows + rows remain
--     immutable (no UPDATE allowed post-submit even by the evaluator)
-- T5  INSERT/UPDATE with peer-personality shape in rating_json /
--     rationale_notes_json is rejected by the DB CHECK (SCIENCE-SPEC §7)
-- T6  rpc_submit_evaluation refuses if run.stage != 'rating' (state
--     machine guard - no late submissions after seal)

begin;
select plan(9);

-- ============ Setup (elevated, then we drop to authenticated per test) ============
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

  insert into auth.users (id, email) values (p4_auth, 't32_p4_'||gen_random_uuid()||'@fjord.test');
  insert into public.people (full_name, primary_email, auth_user_id)
    values ('T32 Fourth Evaluator', 't32_p4_'||p4_auth||'@fjord.test', p4_auth) returning id into p4;
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
  perform set_config('request.jwt.claims', json_build_object('sub', sara)::text, true);
  perform public.rpc_submit_evaluation(run_id, '{"criticality":{"design_review":5,"production_oncall":4}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', erik)::text, true);
  perform public.rpc_submit_evaluation(run_id, '{"criticality":{"design_review":4,"production_oncall":5}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', jonas)::text, true);
  perform public.rpc_submit_evaluation(run_id, '{"criticality":{"design_review":5,"production_oncall":3}}'::jsonb);

  perform set_config('t.run_id',  run_id::text,  true);
  perform set_config('t.linnea',  linnea::text,  true);
  perform set_config('t.sara',    sara::text,    true);
  perform set_config('t.erik',    erik::text,    true);
  perform set_config('t.jonas',   jonas::text,   true);
  perform set_config('t.p4',      p4::text,      true);
  perform set_config('t.p4_auth', p4_auth::text, true);
end$$;

-- ============ T1 - Evaluator A cannot direct-SELECT Evaluator B's row pre-seal ============
set local role authenticated;
do $$ begin perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.sara'))::text, true); end$$;
select is(
  (select count(*)::int from public.team_definition_evaluations e
   join public.team_definition_evaluators ev on ev.id = e.evaluator_id
   where e.run_id = current_setting('t.run_id')::uuid and ev.user_id <> current_setting('t.sara')::uuid),
  0,
  '[T1] Independence: Sara cannot direct-SELECT any evaluation row other than her own during stage=rating'
);
select is(
  (select count(*)::int from public.team_definition_evaluations e
   join public.team_definition_evaluators ev on ev.id = e.evaluator_id
   where e.run_id = current_setting('t.run_id')::uuid and ev.user_id = current_setting('t.sara')::uuid),
  1,
  '[T1b] Evaluator Sara CAN see her own evaluation row during stage=rating (no own-blackout)'
);
reset role;

-- ============ T2 - Run owner cannot direct-SELECT any row pre-seal ============
set local role authenticated;
do $$ begin perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true); end$$;
select is(
  (select count(*)::int from public.team_definition_evaluations e
   where e.run_id = current_setting('t.run_id')::uuid),
  0,
  '[T2] Owner-blackout: Linnea (role.signoff) sees 0 rows via direct SELECT during stage=rating'
);
reset role;

-- ============ T3 - Owner-side read RPC during stage=rating logs the attempt + returns empty ============
do $$
declare pre_count int; post_count int; r jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  select count(*) into pre_count from public.audit_log
    where entity_id = current_setting('t.run_id')::uuid and action = 'team_def.read_during_seal';
  set local role authenticated;
  r := public.rpc_team_definition_evaluations_for_owner(current_setting('t.run_id')::uuid);
  reset role;
  select count(*) into post_count from public.audit_log
    where entity_id = current_setting('t.run_id')::uuid and action = 'team_def.read_during_seal';
  perform set_config('t.pre_audit',  pre_count::text,  true);
  perform set_config('t.post_audit', post_count::text, true);
  perform set_config('t.rpc_rows',   (r->>'rows'),     true);
  perform set_config('t.rpc_flag',   (r->>'attempted_read_during_seal'), true);
end$$;
select ok(
  current_setting('t.post_audit')::int = current_setting('t.pre_audit')::int + 1
  and current_setting('t.rpc_rows') = '[]'
  and current_setting('t.rpc_flag') = 'true',
  '[T3] rpc_team_definition_evaluations_for_owner during stage=rating: writes audit row + returns empty + attempted_read_during_seal=true'
);

-- ============ T4 - 4th evaluator submits, owner seals ============
do $$
declare run_id uuid := current_setting('t.run_id')::uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.p4_auth'))::text, true);
  perform public.rpc_submit_evaluation(run_id, '{"criticality":{"design_review":4,"production_oncall":4}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  perform public.rpc_seal_evaluations(run_id);
end$$;

-- T4a: owner sees all 4 rows post-seal via direct SELECT (RLS reveals)
set local role authenticated;
do $$ begin perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true); end$$;
select is(
  (select count(*)::int from public.team_definition_evaluations e
   where e.run_id = current_setting('t.run_id')::uuid),
  4,
  '[T4a] Post-seal: owner direct-SELECT returns all 4 evaluation rows (RLS reveals after stage transition)'
);
reset role;

-- T4b: rows immutable post-submit even for the evaluator herself
set local role authenticated;
do $$
declare row_count int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.sara'))::text, true);
  update public.team_definition_evaluations
    set rating_json = '{"criticality":{"design_review":1}}'::jsonb
    where run_id = current_setting('t.run_id')::uuid
      and evaluator_id = (select id from public.team_definition_evaluators
                          where run_id = current_setting('t.run_id')::uuid and user_id = current_setting('t.sara')::uuid);
  get diagnostics row_count = row_count;
  perform set_config('t.update_count', row_count::text, true);
end$$;
reset role;
select is(
  current_setting('t.update_count')::int,
  0,
  '[T4b] Post-seal: even the evaluator cannot UPDATE their own submitted row (immutability holds)'
);

-- ============ T5a - peer-personality CHECK defined at schema level ============
select ok(
  exists (
    select 1 from pg_constraint
    where conname = 'chk_team_def_evaluations_no_peer_personality'
      and pg_get_constraintdef(oid) ilike '%target_person_id%'
      and pg_get_constraintdef(oid) ilike '%rater_person_id%'
      and pg_get_constraintdef(oid) ilike '%rates_person%'
      and conrelid = 'public.team_definition_evaluations'::regclass
  ),
  '[T5a] CHECK chk_team_def_evaluations_no_peer_personality exists with the three peer-personality keys blocked (SCIENCE-SPEC §7 hard line)'
);

-- T5b: runtime evidence - UPDATE injecting target_person_id raises check_violation
do $$
declare
  fjord       constant uuid := 'a1000000-0000-0000-0000-000000000002';
  linnea      constant uuid := 'b1000000-0000-0000-0000-000000000003';
  sara        constant uuid := 'b1000000-0000-0000-0000-000000000005';
  v_run       uuid;
  v_ev        uuid;
  v_rejected  boolean := false;
  v_errcode   text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  v_run := public.rpc_create_role_definition_run(
    fjord, 'engineering_t5', null, 'initial_definition', now() + interval '14 days',
    jsonb_build_array(jsonb_build_object('person_id', sara, 'role', 'manager'))
  );
  select id into v_ev from public.team_definition_evaluators where run_id = v_run and user_id = sara;
  perform set_config('request.jwt.claims', json_build_object('sub', sara)::text, true);
  set local role authenticated;
  insert into public.team_definition_evaluations (run_id, evaluator_id, rating_json) values (v_run, v_ev, '{}'::jsonb);
  begin
    update public.team_definition_evaluations
      set rating_json = jsonb_build_object('target_person_id', linnea, 'big5_extraversion', 4)
      where run_id = v_run and evaluator_id = v_ev;
  exception
    when check_violation then v_rejected := true; v_errcode := sqlstate;
    when others           then v_rejected := false; v_errcode := sqlstate;
  end;
  reset role;
  perform set_config('t.peer_block_runtime',  case when v_rejected then 'true' else 'false' end, true);
  perform set_config('t.peer_block_sqlstate', coalesce(v_errcode,''), true);
end$$;
select is(
  current_setting('t.peer_block_runtime'),
  'true',
  '[T5b] Runtime: UPDATE injecting target_person_id raises check_violation (SQLSTATE 23514) - the schema CHECK actually fires'
);

-- ============ T6 - State machine: rpc_submit_evaluation refuses post-seal ============
do $$
declare
  refused boolean := false;
  v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.p4_auth'))::text, true);
  begin
    perform public.rpc_submit_evaluation(current_setting('t.run_id')::uuid, '{"criticality":{"design_review":1}}'::jsonb);
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.late_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.late_errmsg', coalesce(v_errmsg,''), true);
end$$;
select is(
  current_setting('t.late_refused'),
  'true',
  '[T6] rpc_submit_evaluation refuses calls when run.stage != rating (no late submissions after seal)'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
