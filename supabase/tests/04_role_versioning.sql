-- 04_role_versioning — §9: a roles_catalog version is retained after a new version supersedes it.

begin;

-- Use Astrid (org_admin at Nordic Recruit) — has role.create.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000001"}', true);

select plan(5);

-- Call role_version_create on the seeded role.
do $$
declare v2 uuid;
begin
  v2 := public.role_version_create(
    'd1000000-0000-0000-0000-000000000001'::uuid,
    '{"competencies":[{"key":"systems","weight":0.4},{"key":"code_craft","weight":0.3},{"key":"team_dev","weight":0.3}]}'::jsonb
  );
  perform set_config('t.v2', v2::text, true);
end$$;

-- 1. v1 still exists.
select is(
  (select count(*) from public.roles_catalog where id = 'd1000000-0000-0000-0000-000000000001'::uuid),
  1::bigint,
  'v1 of role is retained after versioning'
);

-- 2. v2 exists with version=2, supersedes_id=v1, status=draft.
select is(
  (select count(*) from public.roles_catalog
    where id = current_setting('t.v2')::uuid
      and version = 2
      and supersedes_id = 'd1000000-0000-0000-0000-000000000001'::uuid
      and status = 'draft'),
  1::bigint,
  'v2 created with version=2, supersedes=v1, draft'
);

-- 3. Trying to insert with same (org_id, title, version=1) is rejected.
-- (Switch back to postgres so the FK lookup works in throws_ok — pgTAP runs the
--  query in a savepoint; the policy is irrelevant for the unique-constraint test.)
reset role;
select throws_ok(
  $$insert into public.roles_catalog (org_id, title, is_template, status, version)
    values ('a1000000-0000-0000-0000-000000000001', 'Senior Backend Engineer', false, 'active', 1)$$,
  '23505',
  'duplicate (org_id, title, version=1) is rejected by unique constraint'
);

-- 4. Cannot delete the superseded v1 — FK restrict via supersedes_id.
select throws_ok(
  $$delete from public.roles_catalog where id = 'd1000000-0000-0000-0000-000000000001'::uuid$$,
  '23503',
  'cannot delete a role that has a successor (FK restrict)'
);

-- 5. Role versioning is audited (insert on roles_catalog for v2).
select ok(
  (select count(*) from public.audit_log
    where entity_type = 'roles_catalog'
      and entity_id = current_setting('t.v2')::uuid
      and action = 'insert') >= 1,
  'role versioning is captured in audit_log'
);

select * from finish();
rollback;
