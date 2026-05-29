-- 36_requisition_attach_role — contract tests for rpc_requisition_attach_role.
--
-- T51  Refuses < 20-char rationale
-- T52  Refuses caller lacking requisition.write (Jonas = employee)
-- T53  Refuses attaching a template (is_template=true) — must instantiate first
-- T54  Refuses attaching a role from a different org
-- T55  Refuses re-attaching the same role (no-op guard)
-- T56  Happy path: updates requisition.role_id + writes audit row
--      with before_json {role_id: old}, after_json {role_id: new,
--      role_version, rationale_excerpt}

begin;
select plan(6);

do $$
declare
  fjord       constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency      constant uuid := 'a1000000-0000-0000-0000-000000000001';
  linnea      constant uuid := 'b1000000-0000-0000-0000-000000000003';
  jonas       constant uuid := 'b1000000-0000-0000-0000-000000000006';
  template_id uuid;
  old_role_id uuid;
  new_role_id uuid;
  agency_role uuid;
  req_id      uuid;
  team_id     uuid;
begin
  select id into template_id from public.roles_catalog where is_template=true and family='engineering' limit 1;

  -- definition_json must satisfy chk_role_definition_shape:
  -- competencies + trait_targets required; optimum direction requires
  -- a centre/lower/upper band (SCIENCE-SPEC §2 — Le 2011, Pierce 2013).
  declare
    v_def jsonb := '{"competencies":[{"key":"x","weight":0.5}],"trait_targets":[{"trait":"conscientiousness","direction":"optimum","centre":3,"lower":2,"upper":4}]}'::jsonb;
  begin
    insert into public.roles_catalog (org_id, title, family, is_template, version, status, definition_json)
      values (fjord, 'Senior Eng (old)', 'engineering', false, 1, 'draft', v_def)
      returning id into old_role_id;
    insert into public.roles_catalog (org_id, title, family, is_template, version, status, definition_json)
      values (fjord, 'Senior Eng (revised)', 'engineering', false, 2, 'draft',
              v_def || '{"validation_and_defensibility_metadata":{"team_definition_run_id":"deadbeef-0000-0000-0000-000000000000"}}'::jsonb)
      returning id into new_role_id;
    insert into public.roles_catalog (org_id, title, family, is_template, version, status, definition_json)
      values (agency, 'Agency Role', 'engineering', false, 1, 'draft', v_def)
      returning id into agency_role;
  end;

  -- Get a team in FjordTech to satisfy the requisitions FK.
  select id into team_id from public.teams where org_id = fjord limit 1;

  -- Set up the requisition.
  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  insert into public.requisitions (org_id, role_id, team_id, status, created_by)
    values (fjord, old_role_id, team_id, 'open', linnea)
    returning id into req_id;

  perform set_config('t.req',         req_id::text,      true);
  perform set_config('t.old_role',    old_role_id::text, true);
  perform set_config('t.new_role',    new_role_id::text, true);
  perform set_config('t.template',    template_id::text, true);
  perform set_config('t.agency_role', agency_role::text, true);
  perform set_config('t.linnea',      linnea::text,      true);
  perform set_config('t.jonas',       jonas::text,       true);
end$$;

-- T51 — short rationale
do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin
    perform public.rpc_requisition_attach_role(
      current_setting('t.req')::uuid, current_setting('t.new_role')::uuid, 'short');
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t51_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t51_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t51_refused'), 'true',
  '[T51] short rationale refused | err='||current_setting('t.t51_errmsg'));

-- T52 — caller lacks requisition.write (Jonas = employee)
do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.jonas'))::text, true);
  begin
    perform public.rpc_requisition_attach_role(
      current_setting('t.req')::uuid, current_setting('t.new_role')::uuid,
      'Long enough rationale, but Jonas should be refused because employee lacks requisition.write.');
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t52_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t52_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t52_refused'), 'true',
  '[T52] requisition.write required | err='||current_setting('t.t52_errmsg'));

-- T53 — template refused
do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin
    perform public.rpc_requisition_attach_role(
      current_setting('t.req')::uuid, current_setting('t.template')::uuid,
      'Trying to attach a template — should be refused (instantiate via team-def first).');
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t53_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t53_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t53_refused'), 'true',
  '[T53] template refused | err='||current_setting('t.t53_errmsg'));

-- T54 — cross-org role refused
do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin
    perform public.rpc_requisition_attach_role(
      current_setting('t.req')::uuid, current_setting('t.agency_role')::uuid,
      'Trying to attach a role that belongs to a different org — should be refused.');
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t54_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t54_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t54_refused'), 'true',
  '[T54] cross-org role refused | err='||current_setting('t.t54_errmsg'));

-- T55 — same role refused (no-op guard)
do $$
declare refused boolean := false; v_errmsg text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin
    perform public.rpc_requisition_attach_role(
      current_setting('t.req')::uuid, current_setting('t.old_role')::uuid,
      'Trying to attach the same role that is already attached — should be refused.');
  exception when others then refused := true; v_errmsg := sqlerrm;
  end;
  perform set_config('t.t55_refused', case when refused then 'true' else 'false' end, true);
  perform set_config('t.t55_errmsg',  coalesce(v_errmsg,''), true);
end$$;
select is(current_setting('t.t55_refused'), 'true',
  '[T55] re-attaching same role refused | err='||current_setting('t.t55_errmsg'));

-- T56 — happy path: updates + audit row
do $$
declare r jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  r := public.rpc_requisition_attach_role(
    current_setting('t.req')::uuid, current_setting('t.new_role')::uuid,
    'Switching to the team-definition-derived role v2: it carries the reconciled Delphi provenance.');
  perform set_config('t.t56_result', r::text, true);
end$$;

select ok(
  -- a) requisitions.role_id flipped
  (select role_id = current_setting('t.new_role')::uuid
   from public.requisitions where id = current_setting('t.req')::uuid)
  -- b) audit row with before/after exists
  and exists (
    select 1 from public.audit_log
    where entity_id = current_setting('t.req')::uuid
      and action = 'requisition.role_attached'
      and before_json ->> 'role_id' = current_setting('t.old_role')
      and after_json  ->> 'role_id' = current_setting('t.new_role')
      and after_json  ?  'rationale_excerpt'
  ),
  '[T56] happy path: role_id flipped + audit row carries before/after + rationale_excerpt'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
