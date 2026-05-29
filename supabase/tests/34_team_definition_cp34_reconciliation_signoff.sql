-- 34_team_definition_cp34_reconciliation_signoff — end-to-end Stage 4.
--
-- T26  rpc_record_reconciliation rejects < 20-char discussion notes
-- T27  rpc_signoff_role_version rejects < 20-char rationale
-- T28  rpc_signoff_role_version refuses without role.signoff
-- T29  Happy path: after signoff, run.target_role_version_id is set +
--      new roles_catalog row carries the Delphi provenance JSON
-- T30  rpc_record_reconciliation transitions divergence -> reconciliation
-- T31  rpc_signoff_role_version transitions to signed_off + sets
--      completed_at

begin;
select plan(7);

do $$
declare
  fjord        constant uuid := 'a1000000-0000-0000-0000-000000000002';
  linnea       constant uuid := 'b1000000-0000-0000-0000-000000000003';  -- role.signoff (people_ops_admin)
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

  insert into auth.users (id, email) values (p4_auth, 't34_p4_'||gen_random_uuid()||'@fjord.test');
  insert into public.people (full_name, primary_email, auth_user_id)
    values ('T34 Fourth Evaluator', 't34_p4_'||p4_auth||'@fjord.test', p4_auth) returning id into p4;
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
  -- Diverse ratings → at least one low-consensus criterion.
  perform set_config('request.jwt.claims', json_build_object('sub', sara)::text, true);
  perform public.rpc_submit_evaluation(run_id,
    '{"criticality":{"design_review":5,"production_oncall":5}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', erik)::text, true);
  perform public.rpc_submit_evaluation(run_id,
    '{"criticality":{"design_review":5,"production_oncall":1}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', jonas)::text, true);
  perform public.rpc_submit_evaluation(run_id,
    '{"criticality":{"design_review":4,"production_oncall":5}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', p4_auth)::text, true);
  perform public.rpc_submit_evaluation(run_id,
    '{"criticality":{"design_review":4,"production_oncall":1}}'::jsonb);

  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  perform public.rpc_seal_evaluations(run_id);

  perform set_config('t.run_id',  run_id::text,  true);
  perform set_config('t.linnea',  linnea::text,  true);
  perform set_config('t.sara',    sara::text,    true);
end$$;

-- ============ T26 — discussion_notes < 20 chars rejected ============
do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin
    perform public.rpc_record_reconciliation(
      current_setting('t.run_id')::uuid, 'criticality.production_oncall', 'too short', '{"value": 3}'::jsonb);
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t26_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t26_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t26_refused'), 'true',
  '[T26] rpc_record_reconciliation refuses < 20-char notes | err='||current_setting('t.t26_errmsg'));

-- ============ T27 — rationale < 20 chars rejected ============
-- First, record a real reconciliation so we can reach signoff state with
-- a valid argument set.
do $$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  perform public.rpc_record_reconciliation(
    current_setting('t.run_id')::uuid,
    'criticality.production_oncall',
    'Discussed Sept-on-call rotation; oncall load is shifting as we migrate to managed infra.',
    '{"value": 3}'::jsonb,
    '{"followed_evaluators": []}'::jsonb);
end$$;

do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin
    perform public.rpc_signoff_role_version(current_setting('t.run_id')::uuid, 'tiny');
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t27_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t27_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t27_refused'), 'true',
  '[T27] rpc_signoff_role_version refuses < 20-char rationale | err='||current_setting('t.t27_errmsg'));

-- ============ T28 — signoff requires role.signoff ============
do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.sara'))::text, true);  -- sara = manager, no role.signoff
  begin
    perform public.rpc_signoff_role_version(
      current_setting('t.run_id')::uuid,
      'Long enough rationale, but sara should not be allowed to sign off because she lacks role.signoff.');
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t28_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t28_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t28_refused'), 'true',
  '[T28] rpc_signoff_role_version refuses caller lacking role.signoff | err='||current_setting('t.t28_errmsg'));

-- ============ T30 — record_reconciliation transitions divergence → reconciliation ============
-- Already did the transition above; check it stuck.
select is(
  (select stage::text from public.team_definition_runs where id = current_setting('t.run_id')::uuid),
  'reconciliation',
  '[T30] Recording a reconciliation row transitions run.stage to reconciliation');

-- ============ T29 + T31 — happy path: signoff produces new role version + transitions ============
do $$
declare new_role uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  new_role := public.rpc_signoff_role_version(
    current_setting('t.run_id')::uuid,
    'Validated against Q2 OKRs: oncall load is shifting to platform team, so the role anchors on design review.');
  perform set_config('t.new_role', new_role::text, true);
end$$;

select is(
  (select target_role_version_id from public.team_definition_runs where id = current_setting('t.run_id')::uuid),
  current_setting('t.new_role')::uuid,
  '[T29a] After signoff, run.target_role_version_id points to the new role version');

select ok(
  (select definition_json -> 'validation_and_defensibility_metadata' ->> 'team_definition_run_id'
   from public.roles_catalog where id = current_setting('t.new_role')::uuid)
  = current_setting('t.run_id'),
  '[T29b] New role version carries validation_and_defensibility_metadata.team_definition_run_id = run_id');

select is(
  (select stage::text from public.team_definition_runs where id = current_setting('t.run_id')::uuid),
  'signed_off',
  '[T31] rpc_signoff_role_version transitions run.stage to signed_off');

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
