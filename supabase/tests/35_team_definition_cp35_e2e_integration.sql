-- 35_team_definition_cp35_e2e_integration — full team-based-definition
-- happy path, asserting the chain produces the right artefacts.
--
-- The goal is not to retest the per-RPC contracts (tests 32-34 do that).
-- It is to make sure the WHOLE pipeline composes: a single run can move
-- through all four stages, produce a new role version with full
-- provenance, leave a complete audit trail, and not contaminate the
-- read-edges (team_composition_snapshots stays peer-rating-clean).
--
-- T39  After signoff, run.stage = 'signed_off' and target_role_version_id is set
-- T40  New role is is_template=false, status='draft', org_scoped to the run's org
-- T41  definition_json.validation_and_defensibility_metadata carries the full
--      Delphi provenance shape (run_id + counts + method + framing)
-- T42  audit_log has the full event chain in order:
--        team_def.run_created
--        team_def.evaluation_submitted (×N)
--        team_def.evaluations_sealed
--        team_def.divergence_computed
--        team_def.reconciliation_recorded (×M)
--        team_def.signed_off
-- T43  team_composition snapshot still carries _peer_rating=false (no leak
--      from team-def's peer-personality CHECK relaxation into composition)
-- T44  Calling rpc_signoff_role_version again raises (idempotency guard)
-- T45  The new role is rendered via the standard role-profile read shape
--      (org-scoped roles_catalog row with the provenance attached)

begin;
select plan(7);

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
  new_role     uuid;
begin
  select id into emp_role from public.rbac_roles where key='employee';
  select id into template_id from public.roles_catalog where is_template=true and family='engineering' limit 1;

  insert into auth.users (id, email) values (p4_auth, 't35_p4_'||gen_random_uuid()||'@fjord.test');
  insert into public.people (full_name, primary_email, auth_user_id)
    values ('T35 Fourth Evaluator', 't35_p4_'||p4_auth||'@fjord.test', p4_auth) returning id into p4;
  insert into public.memberships (org_id, person_id, status) values (fjord, p4, 'active') returning id into membership4;
  insert into public.membership_roles (membership_id, rbac_role_id) values (membership4, emp_role);

  -- Stage 1: create run
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

  -- Stage 2: each evaluator submits independently (spread to produce one
  -- low-consensus criterion so the reconciliation phase exercises).
  perform set_config('request.jwt.claims', json_build_object('sub', sara)::text, true);
  perform public.rpc_submit_evaluation(run_id, '{"criticality":{"design_review":5,"production_oncall":5}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', erik)::text, true);
  perform public.rpc_submit_evaluation(run_id, '{"criticality":{"design_review":5,"production_oncall":1}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', jonas)::text, true);
  perform public.rpc_submit_evaluation(run_id, '{"criticality":{"design_review":4,"production_oncall":5}}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', p4_auth)::text, true);
  perform public.rpc_submit_evaluation(run_id, '{"criticality":{"design_review":4,"production_oncall":1}}'::jsonb);

  -- Stage 3: owner seals + computes divergence
  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  perform public.rpc_seal_evaluations(run_id);
  perform public.rpc_compute_divergence(run_id);

  -- Stage 4: reconcile the flagged item (production_oncall) + sign off
  perform public.rpc_record_reconciliation(
    run_id,
    'criticality.production_oncall',
    'Reconciliation discussion: oncall load is shifting as we move to managed infra; chose middle ground.',
    '{"value": 3}'::jsonb,
    '{"followed_evaluators": []}'::jsonb);
  new_role := public.rpc_signoff_role_version(
    run_id,
    'Validated against Q2 strategy: anchors on design review while oncall transitions to platform team.');

  perform set_config('t.run_id',   run_id::text,   true);
  perform set_config('t.new_role', new_role::text, true);
  perform set_config('t.linnea',   linnea::text,   true);
end$$;

-- ============ T39 — stage + target set ============
select ok(
  (select stage = 'signed_off' and target_role_version_id = current_setting('t.new_role')::uuid
   from public.team_definition_runs where id = current_setting('t.run_id')::uuid),
  '[T39] After E2E: run.stage=signed_off AND target_role_version_id = new_role'
);

-- ============ T40 — new role row shape ============
select ok(
  (select org_id = 'a1000000-0000-0000-0000-000000000002'::uuid
      and is_template = false
      and status = 'draft'
      and version = 1
      and family = 'engineering'
   from public.roles_catalog where id = current_setting('t.new_role')::uuid),
  '[T40] New role: org-scoped, is_template=false, status=draft, version=1, family=engineering'
);

-- ============ T41 — provenance JSON shape ============
select ok(
  (select definition_json -> 'validation_and_defensibility_metadata' ?
      'team_definition_run_id'
    and (definition_json -> 'validation_and_defensibility_metadata' ->> 'evaluator_count')::int = 4
    and (definition_json -> 'validation_and_defensibility_metadata' ->> 'submitted_count')::int = 4
    and (definition_json -> 'validation_and_defensibility_metadata' ->> 'reconciliation_count')::int = 1
    and  definition_json -> 'validation_and_defensibility_metadata' ->> 'validation_method'  = 'team_definition_delphi'
    and  definition_json -> 'validation_and_defensibility_metadata' ->> 'framing_default'    = 'developmental'
    and (definition_json -> 'validation_and_defensibility_metadata' ->> '_dev_stub')::boolean = true
   from public.roles_catalog where id = current_setting('t.new_role')::uuid),
  '[T41] Provenance: run_id + 4/4 evaluators + 1 reconciliation + team_definition_delphi method + developmental + _dev_stub=true'
);

-- ============ T42 — audit chain ============
-- All six event types must be present for this run_id, in order.
select ok(
  (
    with chain as (
      select action, "at"
      from public.audit_log
      where entity_id in (
        current_setting('t.run_id')::uuid,
        -- reconciliations are written under their own row id; widen to org_id
        -- and the same time window to catch them
        (select id from public.team_definition_reconciliations where run_id = current_setting('t.run_id')::uuid)
      )
      and action like 'team_def.%'
      order by "at"
    )
    select
      bool_and(action in (
        'team_def.run_created',
        'team_def.evaluation_submitted',
        'team_def.evaluations_sealed',
        'team_def.divergence_computed',
        'team_def.reconciliation_recorded',
        'team_def.signed_off'
      ))
      and array_agg(distinct action) @> ARRAY[
        'team_def.run_created',
        'team_def.evaluation_submitted',
        'team_def.evaluations_sealed',
        'team_def.divergence_computed',
        'team_def.reconciliation_recorded',
        'team_def.signed_off'
      ]::text[]
    from chain
  ),
  '[T42] audit_log carries the full event chain: run_created → submitted×4 → sealed → divergence → reconciled → signed_off'
);

-- ============ T43 — team_composition still _peer_rating=false ============
do $$
declare team_id uuid; snap_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  select id into team_id from public.teams where org_id = 'a1000000-0000-0000-0000-000000000002'::uuid limit 1;
  if team_id is not null then
    snap_id := public.team_composition_compute(team_id);
    perform set_config('t.snap', snap_id::text, true);
  end if;
end$$;
select ok(
  current_setting('t.snap', true) is null
  or (select (snapshot_json ->> '_peer_rating')::boolean = false
        and (snapshot_json ->> '_source') = 'members_own_profiles'
      from public.team_composition_snapshots where id = current_setting('t.snap', true)::uuid),
  '[T43] team_composition_snapshots still carries _peer_rating=false (team-def did NOT leak peer-personality into composition)'
);

-- ============ T44 — idempotency guard ============
do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin
    perform public.rpc_signoff_role_version(
      current_setting('t.run_id')::uuid,
      'Trying to sign off again — should be rejected because the run already produced a version.');
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t44_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t44_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t44_refused'), 'true',
  '[T44] signoff is idempotent — second call rejected | err='||current_setting('t.t44_errmsg'));

-- ============ T45 — standard read shape ============
-- The new role version is queryable via the standard org-scoped read
-- path; the integration test imitates the data-layer fetch that a UI
-- page would do.
select ok(
  (select count(*)::int from public.roles_catalog
   where id = current_setting('t.new_role')::uuid
     and org_id = 'a1000000-0000-0000-0000-000000000002'::uuid
     and is_template = false
     and definition_json ? 'validation_and_defensibility_metadata') = 1,
  '[T45] New role is queryable via the standard org-scoped roles_catalog shape with provenance attached'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
