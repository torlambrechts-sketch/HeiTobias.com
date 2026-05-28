-- 03_consent_revocation — §9: revoking a consent_grant removes access to the
-- dependent profile.
--
-- Phase 2 update: profile_portability authorizes the TRANSFER, not ongoing
-- viewing. To view a transferred profile, the employer org needs a separate
-- consent of an appropriate purpose (hiring_decision or ongoing_management).
-- This test now captures ongoing_management before reading and revokes
-- ongoing_management to assert visibility is lost — the same invariant
-- (revocation removes access) tested against the post-Phase-2 gate.

begin;

declare ongoing_consent uuid;
do $$
declare v_ongoing uuid;
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true);  -- Magnus
  perform public.hiring_decision_record(
    'a3000000-0000-0000-0000-000000000001'::uuid,
    'b1000000-0000-0000-0000-000000000007'::uuid,
    'hire',
    'Test fixture: confirming hire so the placement can run.'
  );
  perform public.placement_execute(
    'a3000000-0000-0000-0000-000000000001'::uuid,
    'b1000000-0000-0000-0000-000000000007'::uuid,
    'a1000000-0000-0000-0000-000000000002'::uuid,
    'f1000000-0000-0000-0000-000000000002'::uuid
  );
  -- Phase 2: the employer activation step captures ongoing_management.
  -- This test simulates that capture so the visibility assertions below mean
  -- something against the new purpose-aware gate.
  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis)
    values ('b1000000-0000-0000-0000-000000000007'::uuid,
            'a1000000-0000-0000-0000-000000000002'::uuid,
            'ongoing_management', 'consent')
    returning id into v_ongoing;
  perform set_config('t.ongoing', v_ongoing::text, true);
end$$;

-- ============ As Linnea (people_ops_admin in FjordTech) ============
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);

select plan(3);

-- 1. With ongoing_management consent active, Linnea sees Petra's profile.
select is(
  (select count(*) from public.profiles
    where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
      and org_id    = 'a1000000-0000-0000-0000-000000000002'::uuid),
  1::bigint,
  'linnea sees petra''s migrated profile while ongoing_management consent is active'
);

reset role;
update public.consent_grants
  set status = 'revoked', revoked_at = now()
  where id = current_setting('t.ongoing')::uuid;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
select is(
  (select count(*) from public.profiles
    where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid
      and org_id    = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  'linnea LOSES access after ongoing_management revoke (§9 + Phase 2 purpose ladder)'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000007"}', true);
select ok(
  (select count(*) from public.profiles where person_id = 'b1000000-0000-0000-0000-000000000007'::uuid) >= 1,
  'petra (data subject) can still see her own profile via is_self'
);

select * from finish();
rollback;
