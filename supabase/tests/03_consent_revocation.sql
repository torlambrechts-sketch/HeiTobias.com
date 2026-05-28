-- 03_consent_revocation — §9: revoking a consent_grant removes access to the dependent profile.
-- Linnea (FjordTech people_ops_admin) tries to read Petra's profile through the placement flow.

begin;

-- Setup: run a placement so FjordTech has a copy of Petra's profile.
-- We do this as service-role-equivalent (postgres bypasses RLS), simulating Magnus.
do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true);  -- Magnus
  perform public.placement_execute(
    'a3000000-0000-0000-0000-000000000001'::uuid,   -- the seeded requisition
    'b1000000-0000-0000-0000-000000000007'::uuid,   -- Petra
    'a1000000-0000-0000-0000-000000000002'::uuid,   -- FjordTech
    'f1000000-0000-0000-0000-000000000002'::uuid    -- her profile_portability consent
  );
end$$;

-- ============ As Linnea (people_ops_admin in FjordTech) ============
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);

select plan(3);

-- 1. While consent is active, Linnea sees Petra's profile in FjordTech.
select is(
  (select count(*) from public.profiles where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
     and org_id = 'a1000000-0000-0000-0000-000000000002'::uuid),
  1::bigint,
  'linnea sees petra''s migrated profile while consent is active'
);

-- Switch to postgres-context to revoke; bypasses RLS for the update.
reset role;
update public.consent_grants
  set status = 'revoked', revoked_at = now()
  where id = 'f1000000-0000-0000-0000-000000000002'::uuid;

-- 2. After revoke, Linnea should no longer see the profile.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
select is(
  (select count(*) from public.profiles where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
     and org_id = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  'linnea LOSES access to petra''s profile after consent revoke (§9 acceptance)'
);

-- 3. The data subject (Petra) always sees her own profile via is_self.
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000007"}', true);
select ok(
  (select count(*) from public.profiles where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid) >= 1,
  'petra (data subject) can still see her own profile via is_self'
);

select * from finish();
rollback;
