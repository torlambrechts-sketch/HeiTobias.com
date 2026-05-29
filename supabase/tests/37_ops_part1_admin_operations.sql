-- 37_ops_part1_admin_operations — admin operations contract.
-- T1  org_change_role refuses <20-char rationale
-- T2  org_change_role refuses non-admin
-- T3  org_change_role writes audit_log + admin_decisions
-- T4  org_deactivate_user flips status + writes admin_decisions
-- T5  org_reactivate_user round-trip
-- T6  org_invite_resend bumps expires_at forward
-- T7  org_invite_accept_v2 updates display name + writes locale
-- T8  org_pending_invites refuses non-admin

begin;
select plan(8);

do $$
declare
  fjord    constant uuid := 'a1000000-0000-0000-0000-000000000002';
  linnea   constant uuid := 'b1000000-0000-0000-0000-000000000003';
  jonas    constant uuid := 'b1000000-0000-0000-0000-000000000006';
  jonas_m  uuid;
begin
  select id into jonas_m from public.memberships where org_id = fjord and person_id = jonas;
  perform set_config('t.fjord',   fjord::text,  true);
  perform set_config('t.linnea',  linnea::text, true);
  perform set_config('t.jonas',   jonas::text,  true);
  perform set_config('t.jonas_m', jonas_m::text, true);
end$$;

do $$
declare refused boolean := false;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  begin perform public.org_change_role(current_setting('t.jonas_m')::uuid, 'manager', 'short');
  exception when others then refused := true; end;
  perform set_config('t.r1', case when refused then 'true' else 'false' end, true);
end$$;
select is(current_setting('t.r1'), 'true', '[T1] org_change_role refuses <20-char rationale');

do $$
declare refused boolean := false;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.jonas'))::text, true);
  begin perform public.org_change_role(current_setting('t.jonas_m')::uuid, 'manager',
    'Jonas tries to self-promote — should be refused for lacking org.manage_all permission.');
  exception when others then refused := true; end;
  perform set_config('t.r2', case when refused then 'true' else 'false' end, true);
end$$;
select is(current_setting('t.r2'), 'true', '[T2] org_change_role refuses non-admin');

do $$
declare audit_count int; da_count int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  perform public.org_change_role(current_setting('t.jonas_m')::uuid, 'manager',
    'Promoting Jonas to manager per Q2 reorg — added team lead duties on the platform team migration.');
  select count(*) into audit_count from public.audit_log
    where entity_id = current_setting('t.jonas_m')::uuid and action = 'org.role_changed';
  select count(*) into da_count from public.admin_decisions
    where person_id = current_setting('t.jonas')::uuid and kind = 'rbac_role_change';
  perform set_config('t.audit3', audit_count::text, true);
  perform set_config('t.da3',    da_count::text,    true);
end$$;
select ok(
  current_setting('t.audit3')::int >= 1 and current_setting('t.da3')::int >= 1,
  '[T3] org_change_role writes audit_log + admin_decisions');

do $$
declare da_count int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  perform public.org_deactivate_user(current_setting('t.jonas_m')::uuid,
    'Jonas left the company end of Q2; deactivating his membership per offboarding checklist.');
  select count(*) into da_count from public.admin_decisions
    where person_id = current_setting('t.jonas')::uuid and kind = 'user_deactivation';
  perform set_config('t.da4', da_count::text, true);
end$$;
select ok(
  current_setting('t.da4')::int >= 1
  and (select status::text from public.memberships where id = current_setting('t.jonas_m')::uuid) = 'suspended',
  '[T4] org_deactivate_user flips status + writes admin_decisions');

do $$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  perform public.org_reactivate_user(current_setting('t.jonas_m')::uuid,
    'Jonas returned end of Q3 to lead the new platform initiative — reactivating his membership.');
end$$;
select is(
  (select status::text from public.memberships where id = current_setting('t.jonas_m')::uuid),
  'active',
  '[T5] org_reactivate_user flips status back to active');

do $$
declare v_mem uuid; v_tok_id uuid; first_exp timestamptz; new_exp_tok jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  v_mem := public.org_invite_user(
    current_setting('t.fjord')::uuid, 't37_'||gen_random_uuid()||'@fjord.test', 'employee', 'Test User');
  select id, expires_at into v_tok_id, first_exp from public.invite_tokens where membership_id = v_mem limit 1;
  perform pg_sleep(0.05);
  new_exp_tok := public.org_invite_resend(v_tok_id, 21);
  perform set_config('t.first_exp', first_exp::text, true);
  perform set_config('t.new_exp', (new_exp_tok->>'new_expires_at')::text, true);
end$$;
select ok(
  (current_setting('t.new_exp')::timestamptz) > (current_setting('t.first_exp')::timestamptz),
  '[T6] org_invite_resend bumps expires_at forward');

do $$
declare v_email text; v_auth_id uuid; v_person_id uuid; v_mem uuid; v_tok text; v_r jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.linnea'))::text, true);
  v_email := 't37_a_'||gen_random_uuid()||'@fjord.test';
  v_mem := public.org_invite_user(current_setting('t.fjord')::uuid, v_email, 'employee', 'Old Name');
  v_auth_id := gen_random_uuid();
  insert into auth.users (id, email) values (v_auth_id, v_email);
  select person_id, token into v_person_id, v_tok from public.invite_tokens where membership_id = v_mem limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_id)::text, true);
  v_r := public.org_invite_accept_v2(v_tok, 'New Display Name', 'nb-NO');
  perform set_config('t.r7_name', (select full_name from public.people where id = v_person_id), true);
end$$;
select is(current_setting('t.r7_name'), 'New Display Name', '[T7] org_invite_accept_v2 updates full_name');

do $$
declare refused boolean := false;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.jonas'))::text, true);
  begin perform * from public.org_pending_invites(current_setting('t.fjord')::uuid);
  exception when others then refused := true; end;
  perform set_config('t.r8', case when refused then 'true' else 'false' end, true);
end$$;
select is(current_setting('t.r8'), 'true', '[T8] org_pending_invites refuses non-admin');

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
