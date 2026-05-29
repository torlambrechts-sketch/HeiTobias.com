-- 39_ops_part2_surfaces — contract tests for Part 2 RPCs.
-- T1  rpc_req_add_candidate refuses <20-char rationale
-- T2  rpc_req_add_candidate refuses non-recruiter
-- T3  rpc_req_add_candidate happy path: creates candidate + mints take-token + audit
-- T4  rpc_req_candidates returns the candidates we created
-- T5  rpc_me_self_view returns person + memberships + consents + activity

begin;
select plan(5);

do $$
declare
  fjord   constant uuid := 'a1000000-0000-0000-0000-000000000002';
  linnea  constant uuid := 'b1000000-0000-0000-0000-000000000003';
  jonas   constant uuid := 'b1000000-0000-0000-0000-000000000006';
  v_req   uuid;
begin
  -- Use an existing FjordTech requisition
  select id into v_req from public.requisitions where org_id = fjord limit 1;
  perform set_config('t.linnea', linnea::text, true);
  perform set_config('t.jonas',  jonas::text,  true);
  perform set_config('t.req',    v_req::text,  true);
end$$;

do $$
declare refused boolean := false;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin perform public.rpc_req_add_candidate(current_setting('t.req')::uuid, 't39@test.test', 'T', 'short');
  exception when others then refused := true; end;
  perform set_config('t.r1', case when refused then 'true' else 'false' end, true);
end$$;
select is(current_setting('t.r1'), 'true', '[T1] add_candidate short rationale refused');

do $$
declare refused boolean := false;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.jonas'))::text, true);
  begin perform public.rpc_req_add_candidate(current_setting('t.req')::uuid,
    't39_'||gen_random_uuid()||'@test.test', 'Test',
    'Jonas tries to add a candidate — should be refused for lacking requisition.write permission.');
  exception when others then refused := true; end;
  perform set_config('t.r2', case when refused then 'true' else 'false' end, true);
end$$;
select is(current_setting('t.r2'), 'true', '[T2] add_candidate refuses non-recruiter');

do $$
declare r jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  r := public.rpc_req_add_candidate(current_setting('t.req')::uuid,
    't39_'||gen_random_uuid()||'@test.test', 'T39 Demo',
    'Adding T39 to the pipeline; sourced via the test scenario for ops-part2 e2e verification.');
  perform set_config('t.rc_id', (r->>'requisition_candidate_id'), true);
  perform set_config('t.tok',   (r->>'take_token'), true);
end$$;
select ok(
  (current_setting('t.rc_id') is not null) and (length(current_setting('t.tok')) > 10)
  and exists (select 1 from public.audit_log where entity_id = current_setting('t.rc_id')::uuid and action = 'requisition.candidate_added'),
  '[T3] add_candidate happy path: candidate row + take_token + audit row');

do $$
declare n int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  select count(*) into n from public.rpc_req_candidates(current_setting('t.req')::uuid);
  perform set_config('t.r4', n::text, true);
end$$;
select ok(current_setting('t.r4')::int >= 1, '[T4] req_candidates returns >=1 candidate');

do $$
declare r jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  r := public.rpc_me_self_view();
  perform set_config('t.r5_ok',
    case when r ? 'person' and r ? 'memberships' and r ? 'consents' and r ? 'recent_activity' then 'true' else 'false' end,
    true);
end$$;
select is(current_setting('t.r5_ok'), 'true', '[T5] self_view returns 4 expected sections');

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
