-- 26_workspace_admin — §E Workspace Admin acceptance.
-- Verifies the admin RPCs created in 20260528203200_hardening_e_admin_rpcs:
--   admin_overview, org_settings_update, org_invite_user, org_change_role,
--   org_deactivate_user, data_export_request_create.
--
-- Pattern: READ → CREATE → MODIFY → re-READ → audit verification → security
-- check (non-admin refused).

begin;
select plan(13);

-- ============ [A] admin_overview — READ ============
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);

select ok(
  (public.admin_overview('a1000000-0000-0000-0000-000000000002'::uuid)) ? 'organization',
  '[A1] admin_overview returns organization section'
);
select ok(
  jsonb_array_length((public.admin_overview('a1000000-0000-0000-0000-000000000002'::uuid)) -> 'members') >= 1,
  '[A2] admin_overview returns member list with >=1 row'
);

-- ============ [B] org_settings_update — MODIFY ============
do $$
declare v jsonb;
begin
  v := public.org_settings_update(
    'a1000000-0000-0000-0000-000000000002'::uuid,
    null, 'FjordTech AS Pty Test', '#3a4d3f',
    'https://example.test/logo.png', 'https://example.test/dpa');
  perform set_config('t.settings_after', v::text, true);
end$$;
select is(
  ((current_setting('t.settings_after')::jsonb) -> 'settings' ->> 'legal_name'),
  'FjordTech AS Pty Test',
  '[B1] org_settings_update persists legal_name into settings_json'
);
select ok(
  (select count(*) from public.audit_log
    where action='org.settings_updated' and entity_id='a1000000-0000-0000-0000-000000000002') >= 1,
  '[B2] org_settings_updated audit event written'
);

-- ============ [C] org_invite_user — CREATE ============
do $$
declare m_id uuid;
begin
  m_id := public.org_invite_user(
    'a1000000-0000-0000-0000-000000000002'::uuid,
    'review.test+'||gen_random_uuid()::text||'@fjord.test',
    'hiring_manager', 'Review Test User');
  perform set_config('t.new_membership', m_id::text, true);
end$$;
select is(
  (select status::text from public.memberships where id = current_setting('t.new_membership')::uuid),
  'invited',
  '[C1] new member created with status=invited'
);
select ok(
  exists(select 1 from public.membership_roles mr
    join public.rbac_roles r on r.id = mr.rbac_role_id
    where mr.membership_id = current_setting('t.new_membership')::uuid and r.key = 'hiring_manager'),
  '[C2] new member assigned hiring_manager role'
);
select ok(
  (select count(*) from public.audit_log where action='org.user_invited' and entity_id = current_setting('t.new_membership')::uuid) >= 1,
  '[C3] org.user_invited audit event written'
);

-- ============ [C4] BUG FIX: re-inviting an ACTIVE user does NOT regress status ============
do $$
declare m_id uuid; before_status text; after_status text;
begin
  select status::text into before_status from public.memberships m
    where m.person_id='b1000000-0000-0000-0000-000000000005' and m.org_id='a1000000-0000-0000-0000-000000000002';
  -- Re-invite Sara (active manager)
  m_id := public.org_invite_user('a1000000-0000-0000-0000-000000000002'::uuid, 'sara.vik@fjordtech.test', 'manager', null);
  select status::text into after_status from public.memberships where id = m_id;
  perform set_config('t.sara_change', before_status || '->' || after_status, true);
end$$;
select is(current_setting('t.sara_change'), 'active->active',
  '[C4] re-inviting active user keeps status=active (bug fix verified)');

-- ============ [D] org_change_role — MODIFY ============
do $$
begin
  perform public.org_change_role(current_setting('t.new_membership')::uuid, 'people_ops_admin');
end$$;
select ok(
  exists(select 1 from public.membership_roles mr
    join public.rbac_roles r on r.id = mr.rbac_role_id
    where mr.membership_id = current_setting('t.new_membership')::uuid and r.key = 'people_ops_admin'),
  '[D1] org_change_role assigned new role'
);

-- ============ [E] org_deactivate_user — MODIFY ============
do $$
begin
  perform public.org_deactivate_user(current_setting('t.new_membership')::uuid);
end$$;
select is(
  (select status::text from public.memberships where id = current_setting('t.new_membership')::uuid),
  'suspended',
  '[E1] org_deactivate_user sets status=suspended'
);

-- ============ [F] data_export_request_create — CREATE ============
do $$
declare x_id uuid;
begin
  x_id := public.data_export_request_create('a1000000-0000-0000-0000-000000000002'::uuid,
    jsonb_build_object('scope','full','format','csv'), 'test fixture');
  perform set_config('t.export', x_id::text, true);
end$$;
select is(
  (select status from public.data_export_requests where id = current_setting('t.export')::uuid),
  'pending',
  '[F1] data_export_request status=pending'
);
select ok(
  (select count(*) from public.audit_log where action='data_export.requested' and entity_id = current_setting('t.export')::uuid) >= 1,
  '[F2] data_export.requested audit event written'
);

-- ============ [G] SECURITY: non-admin (Sara, manager) is refused ============
reset role;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000005"}', true);  -- Sara
select throws_ok(
  $$select public.org_settings_update('a1000000-0000-0000-0000-000000000002'::uuid, 'attack-attempt')$$,
  'P0001', NULL::text,
  '[G1] non-admin (Sara, manager) refused from org_settings_update'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
