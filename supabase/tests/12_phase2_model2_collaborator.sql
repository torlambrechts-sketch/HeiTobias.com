-- 12_phase2_model2_collaborator — PHASE2 Step 4 (shared workspace).
-- Employer invites an agency as a scoped collaborator on a single requisition.
-- The agency sees the requisition + its candidates ONLY; nothing else in
-- the employer org. No data movement — purely RBAC + RLS.

begin;
select plan(8);

-- Setup: employer creates a fresh requisition in FjordTech, adds a Nordic
-- Recruit candidate to it, invites Nordic Recruit as collaborator.
do $$
declare
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_a   constant uuid := 'a1000000-0000-0000-0000-000000000001';
  linnea     constant uuid := 'b1000000-0000-0000-0000-000000000003';   -- FjordTech people_ops_admin (req.write)
  fj_role uuid;
  fj_req  uuid;
  cand    uuid;
begin
  -- A role in FjordTech for the requisition.
  insert into public.roles_catalog (org_id, title, family, is_template, status, version, definition_json)
    values (employer_a, 'FjordTech Senior Backend', 'engineering', false, 'active', 1,
      jsonb_build_object('competencies', jsonb_build_array(jsonb_build_object('key','sample','weight',1)),
                         'trait_targets', '[]'::jsonb))
    returning id into fj_role;

  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  insert into public.requisitions (org_id, role_id, status)
    values (employer_a, fj_role, 'open')
    returning id into fj_req;

  -- A candidate person + req_candidate row.
  insert into public.people (full_name, primary_email)
    values ('M2 Candidate', 'm2_'||gen_random_uuid()||'@p2.test') returning id into cand;
  insert into public.requisition_candidates (org_id, requisition_id, person_id, stage)
    values (employer_a, fj_req, cand, 'screening');

  -- Invite Nordic Recruit as collaborator.
  perform public.requisition_invite_collaborator(fj_req, agency_a);

  perform set_config('t.fj_req', fj_req::text, true);
  perform set_config('t.fj_role', fj_role::text, true);
  perform set_config('t.cand', cand::text, true);
end$$;

-- ============ As Magnus (Nordic Recruit recruiter) ============
-- He has requisition.read in Nordic Recruit. Model 2 should let him SEE the
-- FjordTech requisition + its candidates BUT NOTHING ELSE.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002"}', true);

-- [A] Magnus sees the shared requisition (Phase 0 already supported this
-- via the collaborating_org_id leg of requisitions_select).
select is(
  (select count(*) from public.requisitions where id = current_setting('t.fj_req')::uuid),
  1::bigint,
  '[A1] collaborator can SEE the shared requisition'
);

-- [B] Magnus sees the requisition_candidates on the shared requisition.
-- This is the NEW Step 4 behavior — was broken pre-Step 4.
select is(
  (select count(*) from public.requisition_candidates
    where requisition_id = current_setting('t.fj_req')::uuid),
  1::bigint,
  '[B1] collaborator can read requisition_candidates on the shared requisition'
);

-- [C] Magnus does NOT see other FjordTech requisitions or roles or anything
-- else in the employer org.
-- (We only created one FjordTech requisition in this test, but verify he
-- doesn''t see FjordTech-owned requisition_candidates from any other req.)
select is(
  (select count(*) from public.requisitions
    where org_id = 'a1000000-0000-0000-0000-000000000002'::uuid
      and id <> current_setting('t.fj_req')::uuid),
  0::bigint,
  '[C1] collaborator does NOT see other FjordTech requisitions'
);

-- [D] is_requisition_collaborator helper agrees.
select ok(
  public.is_requisition_collaborator(current_setting('t.fj_req')::uuid),
  '[D1] is_requisition_collaborator returns true for the shared req'
);

-- ============ Remove the collaborator → Magnus loses access ============
reset role;
do $$ begin perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true); end$$;
do $$ begin perform public.requisition_remove_collaborator(current_setting('t.fj_req')::uuid); end$$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002"}', true);
select is(
  (select count(*) from public.requisitions where id = current_setting('t.fj_req')::uuid),
  0::bigint,
  '[E1] after removal, collaborator loses visibility on the requisition'
);
select is(
  (select count(*) from public.requisition_candidates where requisition_id = current_setting('t.fj_req')::uuid),
  0::bigint,
  '[E2] after removal, collaborator loses visibility on the candidates'
);

-- ============ AuthZ on the invite RPC ============
reset role;
do $$ begin perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002"}', true); end$$;
-- Magnus has requisition.write in Nordic Recruit but NOT in FjordTech.
-- He cannot invite a collaborator to a FjordTech-owned requisition.
select throws_ok(
  format($$select public.requisition_invite_collaborator(%L::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid)$$,
    current_setting('t.fj_req')),
  'P0001', NULL::text,
  '[F1] caller without req.write in owner org cannot invite a collaborator'
);

-- Self-collaborator rejected.
do $$ begin perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true); end$$;
select throws_ok(
  format($$select public.requisition_invite_collaborator(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid)$$,
    current_setting('t.fj_req')),
  'P0001', NULL::text,
  '[F2] collaborator must be a different org'
);

select * from finish();
rollback;
