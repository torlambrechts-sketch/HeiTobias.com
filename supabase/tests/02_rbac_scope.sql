-- 02_rbac_scope — §9: manager / employee / admin see exactly their scoped rows.
-- Walks the seeded position chain: Erik (top) <- Sara <- Jonas.

begin;

-- ============ As Sara (manager) ============
-- Sara should see her OWN position (via is_self leg of in_scope) and Jonas's
-- (Jonas is downstream on her manager chain). She should NOT see Erik's
-- (Erik is above her).
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000005"}', true);

select plan(8);

select is(
  (select count(*) from public.positions where id = 'e1000000-0000-0000-0000-000000000002'::uuid),
  1::bigint,
  'sara sees her own position (is_self)'
);

select is(
  (select count(*) from public.positions where id = 'e1000000-0000-0000-0000-000000000003'::uuid),
  1::bigint,
  'sara sees jonas''s position (he reports to her — manager chain)'
);

select is(
  (select count(*) from public.positions where id = 'e1000000-0000-0000-0000-000000000001'::uuid),
  0::bigint,
  'sara does NOT see erik''s position (erik is above her on the chain)'
);

-- has_permission for Sara
select ok(
  public.has_permission('a1000000-0000-0000-0000-000000000002'::uuid, 'position.read'),
  'sara has position.read in FjordTech (manager role grants it)'
);

select ok(
  not public.has_permission('a1000000-0000-0000-0000-000000000002'::uuid, 'placement.transfer'),
  'sara does NOT have placement.transfer (manager role does not grant it)'
);

-- in_scope checks
select ok(
  public.in_scope('a1000000-0000-0000-0000-000000000002'::uuid, 'b1000000-0000-0000-0000-000000000006'::uuid),
  'in_scope(FjordTech, jonas) = true for sara (she manages him)'
);

select ok(
  not public.in_scope('a1000000-0000-0000-0000-000000000002'::uuid, 'b1000000-0000-0000-0000-000000000004'::uuid),
  'in_scope(FjordTech, erik) = false for sara (erik is above her)'
);

-- ============ As Jonas (employee, leaf of chain) ============
-- Jonas should only see himself.
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000006"}', true);

select is(
  (select count(*) from public.positions),
  0::bigint,
  'jonas (employee) does NOT see his own position (position.read not granted)'
);
-- ^ Note: employee role has only org.read + consent.read — not position.read.
-- Employee sees their own profile (via is_self) but not their position row directly.

select * from finish();
rollback;
