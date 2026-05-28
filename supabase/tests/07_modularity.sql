-- 07_modularity — §9: module + template registries allow enabling a capability
-- per org WITHOUT core schema changes.

begin;

select plan(4);

-- 1. Add a brand-new module — no schema change required.
insert into public.modules (key, name, status, config_schema_json) values (
  'pulse_cadence',
  'Pulse Cadence',
  'beta',
  '{"type":"object","required":["frequency_days"],"properties":{"frequency_days":{"type":"number","minimum":1,"maximum":90}}}'::jsonb
);

select is(
  (select count(*) from public.modules where key = 'pulse_cadence'),
  1::bigint,
  'new module added to registry (no schema change)'
);

-- 2. Enable it for FjordTech with a valid config — no schema change required.
insert into public.org_modules (org_id, module_key, config_json) values (
  'a1000000-0000-0000-0000-000000000002',
  'pulse_cadence',
  '{"frequency_days": 14}'::jsonb
);

select is(
  (select count(*) from public.org_modules
    where org_id = 'a1000000-0000-0000-0000-000000000002'::uuid
      and module_key = 'pulse_cadence'
      and (config_json->>'frequency_days') = '14'),
  1::bigint,
  'module enabled per org with config (no schema change)'
);

-- 3. Invalid config (missing required key) is REJECTED by pg_jsonschema.
-- pgTAP signature: throws_ok(query, errcode, errmsg, description); pass NULL
-- for errmsg to assert SQLSTATE only.
select throws_ok(
  $$insert into public.org_modules (org_id, module_key, config_json)
    values ('a1000000-0000-0000-0000-000000000001', 'pulse_cadence', '{"unrelated":1}'::jsonb)$$,
  'P0001', NULL::text,
  'invalid org config rejected by the schema-driven validator'
);

-- 4. Templates: a new layout template can be added without a schema change.
insert into public.templates (kind, key, body_json, status) values
  ('layout', 'pulse_overview', '{"slots":[{"slot":"hero","component":"pulse_kpi"}]}'::jsonb, 'active');

select is(
  (select count(*) from public.templates
    where kind = 'layout' and key = 'pulse_overview' and org_id is null),
  1::bigint,
  'new global template added (no schema change)'
);

select * from finish();
rollback;
