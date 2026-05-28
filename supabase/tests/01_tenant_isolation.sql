-- 01_tenant_isolation — §9: agency and employer can coexist with provably isolated data.
-- Runs as Magnus (Nordic Recruit recruiter). Asserts cross-org reads return zero.

begin;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true);

select plan(6);

select is(
  (select count(*) from public.organizations where id = 'a1000000-0000-0000-0000-000000000001'::uuid),
  1::bigint,
  'magnus sees Nordic Recruit (his own org)'
);

select is(
  (select count(*) from public.organizations where id = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  'magnus does NOT see FjordTech (cross-org isolation)'
);

select is(
  (select count(*) from public.organizations),
  1::bigint,
  'magnus sees exactly 1 organization (default-deny + own membership)'
);

select is(
  (select count(*) from public.requisitions where id = 'a3000000-0000-0000-0000-000000000001'::uuid),
  1::bigint,
  'magnus sees the Nordic Recruit requisition'
);

select is(
  (select count(*) from public.roles_catalog where org_id = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  'magnus does NOT see FjordTech role instances'
);

select is(
  (select count(*) from public.roles_catalog where org_id = 'a1000000-0000-0000-0000-000000000001'::uuid),
  1::bigint,
  'magnus sees Nordic Recruit role'
);

select * from finish();
rollback;
