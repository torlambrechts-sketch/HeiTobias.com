-- 06_audit_coverage — §9: every consequential mutation lands in audit_log,
-- and audit_log is immutable.

begin;

select plan(6);

-- 1. Every domain table (except audit_log itself) carries the _audit_row
-- trigger. The trigger COUNT grows as Phase 1+ adds tables; what matters
-- is the COVERAGE invariant — that no domain table is missing one. We
-- exclude framework tables (templates, modules, etc.) only if they were
-- explicitly omitted; here we check by trigger function:
--   every public table that calls _audit_row is covered.
-- Brittle hardcoded counts retired in favor of: "audit_log is the only
-- public table that does NOT have trg_audit_*".
select is(
  (select count(*) from information_schema.tables t
    where t.table_schema = 'public'
      and t.table_type = 'BASE TABLE'
      and t.table_name <> 'audit_log'
      and not exists (
        select 1 from pg_trigger tr
        join pg_class c on c.oid = tr.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = t.table_name
          and tr.tgname like 'trg_audit_%'
      )
  ),
  0::bigint,
  'every public domain table (except audit_log) carries an _audit_row trigger'
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
-- pgTAP signature: throws_ok(query, errcode, errmsg, description); pass NULL
-- for errmsg to assert SQLSTATE only. (PostgreSQL has no UPDATE LIMIT; scope
-- the row via id sub-select.)
select throws_ok(
  $$update public.audit_log set action = 'tampered'
      where id = (select id from public.audit_log where entity_type = 'organizations' limit 1)$$,
  'P0001', NULL::text,
  'UPDATE on audit_log is rejected'
);

-- 5. DELETE on audit_log is rejected by the immutability trigger.
select throws_ok(
  $$delete from public.audit_log where entity_type = 'organizations'$$,
  'P0001', NULL::text,
  'DELETE on audit_log is rejected'
);

select * from finish();
rollback;
