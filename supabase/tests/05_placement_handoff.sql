-- 05_placement_handoff — §9: a placement performs a consent-gated cross-org
-- profile hand-off, fully audited.

begin;

select plan(7);

-- ============ Execute the placement as Magnus (recruiter) ============
do $$
declare placement_id uuid;
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true);
  placement_id := public.placement_execute(
    'a3000000-0000-0000-0000-000000000001'::uuid,   -- requisition
    'b1000000-0000-0000-0000-000000000007'::uuid,   -- Petra
    'a1000000-0000-0000-0000-000000000002'::uuid,   -- FjordTech
    'f1000000-0000-0000-0000-000000000002'::uuid    -- profile_portability consent
  );
  perform set_config('t.placement', placement_id::text, true);
end$$;

-- 1. Placement row exists with status=transferred.
select is(
  (select count(*) from public.placements
    where id = current_setting('t.placement')::uuid
      and status = 'transferred'),
  1::bigint,
  'placement row created with status=transferred'
);

-- 2. Profile copied into FjordTech with source=import, linked to the same consent.
select is(
  (select count(*) from public.profiles
    where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
      and org_id    = 'a1000000-0000-0000-0000-000000000002'::uuid
      and source    = 'import'
      and consent_id = 'f1000000-0000-0000-0000-000000000002'::uuid),
  1::bigint,
  'profile copied into FjordTech under the profile_portability consent'
);

-- 3. Filled position created in FjordTech for Petra.
select is(
  (select count(*) from public.positions
    where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
      and org_id    = 'a1000000-0000-0000-0000-000000000002'::uuid
      and status    = 'filled'),
  1::bigint,
  'filled position created in FjordTech for Petra'
);

-- 4. Placement is in the audit_log.
select ok(
  (select count(*) from public.audit_log
    where entity_type = 'placements'
      and entity_id   = current_setting('t.placement')::uuid
      and action      = 'insert') >= 1,
  'placement INSERT is captured in audit_log'
);

-- 5. Profile copy is in the audit_log.
select ok(
  (select count(*) from public.audit_log
    where entity_type = 'profiles'
      and action      = 'insert'
      and (after_json->>'source') = 'import') >= 1,
  'profile copy is captured in audit_log'
);

-- 6. Position creation is in the audit_log.
select ok(
  (select count(*) from public.audit_log
    where entity_type = 'positions'
      and action      = 'insert'
      and (after_json->>'person_id') = 'b1000000-0000-0000-0000-000000000007') >= 1,
  'position creation is captured in audit_log'
);

-- 7. Rejection: wrong consent purpose throws.
select throws_ok(
  $$select public.placement_execute(
      'a3000000-0000-0000-0000-000000000001'::uuid,
      'b1000000-0000-0000-0000-000000000007'::uuid,
      'a1000000-0000-0000-0000-000000000002'::uuid,
      'f1000000-0000-0000-0000-000000000001'::uuid  -- hiring_decision, wrong purpose
    )$$,
  'P0001',
  'placement_execute rejects wrong-purpose consent'
);

select * from finish();
rollback;
