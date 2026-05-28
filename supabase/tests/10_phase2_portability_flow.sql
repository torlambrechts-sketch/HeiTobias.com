-- 10_phase2_portability_flow — PHASE2 §7 acceptance.
-- The candidate-owned portability flow + the placement_execute gate it feeds:
-- 1. transfer is blocked without an active profile_portability grant
-- 2. candidate grants via consent dashboard → placement succeeds
-- 3. candidate revokes via consent dashboard → subsequent placement is blocked

begin;
select plan(13);

-- ============ Setup: fresh candidate with full lifecycle through hire decision ============
do $$
declare
  agency_a   constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid     constant uuid := 'b1000000-0000-0000-0000-000000000001';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
begin
  insert into public.people (full_name, primary_email)
    values ('Portability Cand', 'pf_'||gen_random_uuid()||'@p2.test') returning id into cand;
  insert into public.memberships (org_id, person_id, status) values (agency_a, cand, 'invited');

  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, cand, 'sample_personality_v0','personality',14);
  tok := inv->>'token';
  perform set_config('request.jwt.claims','{}', true);
  cap_consent := public.assessment_capture_consent(tok);
  for it in select i.id from public.assessment_items i
    join public.assessment_instruments ai on ai.id=i.instrument_id
    where ai.key='sample_personality_v0'
  loop perform public.assessment_submit_response(tok, it.id, '{"value":4}'::jsonb); end loop;
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);
  perform public.compute_fit_for_candidate(agency_req, cand);
  perform public.hiring_decision_record(agency_req, cand, 'hire',
    'Phase 2 step 2 fixture: hire so the portability gate is what we''re testing.');

  -- Pluck the long-lived consent token minted during capture.
  select token into ct_token from public.consent_tokens
    where person_id = cand and revoked_at is null and expires_at > now() limit 1;

  perform set_config('t.cand', cand::text, true);
  perform set_config('t.ct_token', ct_token, true);
end$$;

-- ============ [A] new RPCs behave per spec ============

-- A1: dashboard_state returns identity + at least one grant (the hiring_decision).
select ok(
  (public.consent_dashboard_state(current_setting('t.ct_token'))->'person'->>'id')
    = current_setting('t.cand'),
  '[A1] consent_dashboard_state returns the data subject identity'
);
select ok(
  jsonb_array_length(public.consent_dashboard_state(current_setting('t.ct_token'))->'grants') >= 1,
  '[A1b] dashboard state shows the hiring_decision grant from capture'
);

-- A2: invalid token rejected.
select throws_ok(
  $$select public.consent_dashboard_state('not-a-real-token')$$,
  'P0001', NULL::text,
  '[A2] consent_dashboard_state rejects invalid token'
);

-- ============ [B] transfer is BLOCKED before portability_grant ============

select throws_ok(
  format($$select public.placement_execute(
      'a3000000-0000-0000-0000-000000000001'::uuid,
      %L::uuid,
      'a1000000-0000-0000-0000-000000000002'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid)$$, current_setting('t.cand')),
  'P0001', NULL::text,
  '[B1] placement_execute with a nonexistent consent_id is rejected'
);

-- ============ [C] candidate grants portability via the dashboard, then placement succeeds ============
do $$
declare port_grant_id uuid;
begin
  port_grant_id := public.portability_grant(
    current_setting('t.ct_token'),
    'a1000000-0000-0000-0000-000000000002'::uuid
  );
  perform set_config('t.port_grant', port_grant_id::text, true);
end$$;

select ok(
  (select status::text from public.consent_grants where id = current_setting('t.port_grant')::uuid) = 'active',
  '[C1] portability_grant produced an active profile_portability consent'
);
select ok(
  (select purpose::text from public.consent_grants where id = current_setting('t.port_grant')::uuid) = 'profile_portability',
  '[C2] purpose = profile_portability'
);
select ok(
  (select count(*) from public.audit_log
    where action='consent.granted' and entity_id = current_setting('t.port_grant')::uuid) >= 1,
  '[C3] consent.granted audit event written'
);

-- Idempotent: calling portability_grant again returns the same id, doesn't create a duplicate.
select ok(
  public.portability_grant(current_setting('t.ct_token'), 'a1000000-0000-0000-0000-000000000002'::uuid)
    = current_setting('t.port_grant')::uuid,
  '[C4] portability_grant is idempotent (same id on second call)'
);

-- Now placement_execute should succeed with the newly granted consent.
do $$
declare placement_id uuid;
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true);  -- Magnus
  placement_id := public.placement_execute(
    'a3000000-0000-0000-0000-000000000001'::uuid,
    current_setting('t.cand')::uuid,
    'a1000000-0000-0000-0000-000000000002'::uuid,
    current_setting('t.port_grant')::uuid
  );
  perform set_config('t.placement', placement_id::text, true);
end$$;
select ok(
  (select status::text from public.placements where id = current_setting('t.placement')::uuid) = 'transferred',
  '[C5] placement_execute succeeds once portability is granted via the dashboard'
);

-- ============ [D] revoke halts a fresh transfer attempt ============
-- Create a second portability-eligible candidate to retest the gate with revoke.
do $$
declare
  agency_a   constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid     constant uuid := 'b1000000-0000-0000-0000-000000000001';
  cand2 uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; port_grant uuid; it record;
begin
  insert into public.people (full_name, primary_email)
    values ('PortRevoke Cand', 'pr_'||gen_random_uuid()||'@p2.test') returning id into cand2;
  insert into public.memberships (org_id, person_id, status) values (agency_a, cand2, 'invited');
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, cand2, 'sample_personality_v0','personality',14);
  tok := inv->>'token';
  perform set_config('request.jwt.claims','{}', true);
  cap_consent := public.assessment_capture_consent(tok);
  for it in select i.id from public.assessment_items i
    join public.assessment_instruments ai on ai.id=i.instrument_id where ai.key='sample_personality_v0'
  loop perform public.assessment_submit_response(tok, it.id, '{"value":3}'::jsonb); end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);
  perform public.compute_fit_for_candidate(agency_req, cand2);
  -- Decision required by placement_execute.
  perform public.hiring_decision_record(agency_req, cand2, 'hire', 'fixture hire 2');

  select token into ct_token from public.consent_tokens
    where person_id = cand2 and revoked_at is null and expires_at > now() limit 1;
  port_grant := public.portability_grant(ct_token, employer_a);

  -- Candidate revokes via dashboard.
  perform public.consent_revoke(ct_token, port_grant);

  perform set_config('t.cand2', cand2::text, true);
  perform set_config('t.port_grant2', port_grant::text, true);
end$$;

select ok(
  (select status::text from public.consent_grants where id = current_setting('t.port_grant2')::uuid) = 'revoked',
  '[D1] candidate-driven consent_revoke flips status to revoked'
);
select ok(
  (select count(*) from public.audit_log
    where action='consent.revoked' and entity_id = current_setting('t.port_grant2')::uuid) >= 1,
  '[D2] consent.revoked audit event written'
);
select throws_ok(
  format($$select public.placement_execute(
      'a3000000-0000-0000-0000-000000000001'::uuid,
      %L::uuid,
      'a1000000-0000-0000-0000-000000000002'::uuid,
      %L::uuid)$$, current_setting('t.cand2'), current_setting('t.port_grant2')),
  'P0001', NULL::text,
  '[D3] placement_execute is BLOCKED once the candidate has revoked portability'
);

-- ============ [E] cross-person guard ============
do $$
declare other_cand uuid; other_grant uuid;
begin
  insert into public.people (full_name, primary_email)
    values ('Other', 'oth_'||gen_random_uuid()||'@p2.test') returning id into other_cand;
  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis)
    values (other_cand, 'a1000000-0000-0000-0000-000000000002'::uuid, 'profile_portability', 'consent')
    returning id into other_grant;
  perform set_config('t.other_grant', other_grant::text, true);
end$$;
select throws_ok(
  format($$select public.consent_revoke(%L, %L::uuid)$$, current_setting('t.ct_token'), current_setting('t.other_grant')),
  'P0001', NULL::text,
  '[E1] candidate cannot revoke a different person''s consent with their own token'
);

select * from finish();
rollback;
