-- 00_smoke — proves the test runner can execute pgTAP assertions.
-- Wraps in a transaction so the test leaves the database untouched.

begin;

select plan(2);

select has_extension('pgtap',         'pgtap extension is installed');
select has_extension('pg_jsonschema', 'pg_jsonschema extension is installed');

select * from finish();

rollback;
