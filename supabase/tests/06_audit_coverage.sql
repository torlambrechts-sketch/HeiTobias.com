-- 06_audit_coverage — §9: every consequential mutation lands in audit_log,
-- and audit_log is immutable.

begin;

select plan(6);

-- 1. Triggers attached to every domain table (19 tables: 13 core + 4 RBAC + 4 modularity − audit_log itself = 19, actually 18 excluding audit_log + we have 22 total domain so 21 minus audit_log = 21 ... let me just count via pg_trigger).
select is(
  (select count(*)
   from pg_trigger t
   join pg_class c on c.oid = t.tgrelid
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and t.tgname like 'trg_audit_%'),
  18::bigint,
  'every domain table (except audit_log) has an _audit_row trigger (18 total)'
);

-- 2. audit_log itself has the immutability triggers.
select ok(
  exists (select 1 from pg_trigger where tgname = 'trg_audit_log_no_update'),
  'audit_log has an UPDATE-blocking trigger'
);
select ok(
  exists (select 1 from pg_trigger where tgname = 'trg_audit_log_no_delete'),
  'audit_log has a DELETE-blocking trigger'
);

-- 3. Mutations DO produce audit rows. We do a write + check.
do $$
declare org_b uuid;
begin
  insert into public.organizations (name, type) values ('AuditCheck Inc', 'employer') returning id into org_b;
  perform set_config('t.org_b', org_b::text, true);
end$$;

select ok(
  (select count(*) from public.audit_log
    where entity_type = 'organizations'
      and entity_id = current_setting('t.org_b')::uuid
      and action = 'insert') >= 1,
  'new organization INSERT lands in audit_log'
);

-- 4. UPDATE on audit_log is rejected by the immutability trigger.
select throws_ok(
  $$update public.audit_log set action = 'tampered' where entity_type = 'organizations' limit 1$$,
  'P0001',
  'UPDATE on audit_log is rejected'
);

-- 5. DELETE on audit_log is rejected by the immutability trigger.
select throws_ok(
  $$delete from public.audit_log where entity_type = 'organizations'$$,
  'P0001',
  'DELETE on audit_log is rejected'
);

select * from finish();
rollback;
