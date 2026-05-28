-- 11_phase2_employer_activation — PHASE2 Step 3 receiving-employer flow.
-- A placement_execute transfers the profile under profile_portability, but
-- post-Step 1 the row is invisible until a separate ongoing_management
-- consent is captured. Step 3 RPC placement_activate captures that consent
-- on the data subject's behalf with legal_basis='contract', idempotently.
-- Activation surface (employer_activations_state) reflects the queue.

begin;
select plan(11);

do $$
declare
  agency_a   constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid     constant uuid := 'b1000000-0000-0000-0000-000000000001';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid;
begin
  insert into public.people (full_name, primary_email)
    values ('Activation Cand', 'av_'||gen_random_uuid()||'@p2.test') returning id into cand;
  insert into public.memberships (org_id, person_id, status) values (agency_a, cand, 'invited');
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, cand,'sample_personality_v0','personality',14);
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
  perform public.hiring_decision_record(agency_req, cand,'hire','fixture hire');
  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);
  perform set_config('t.cand', cand::text, true);
  perform set_config('t.placement', placement_id::text, true);
end$$;

-- [A] Before activation: ongoing_management is NOT yet active for (cand, employer).
select ok(
  not public.consent_active_for(
    current_setting('t.cand')::uuid,
    'a1000000-0000-0000-0000-000000000002'::uuid,
    'ongoing_management'
  ),
  '[A1] no ongoing_management before activation'
);

-- [B] placement_activate as Linnea (FjordTech people_ops_admin) captures the consent.
do $$
declare result jsonb;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  result := public.placement_activate(current_setting('t.placement')::uuid);
  perform set_config('t.activate1', result::text, true);
end$$;

select ok(
  not ((current_setting('t.activate1')::jsonb)->>'already_active')::boolean,
  '[B1] first activation reports already_active = false'
);
select ok(
  public.consent_active_for(
    current_setting('t.cand')::uuid,
    'a1000000-0000-0000-0000-000000000002'::uuid,
    'ongoing_management'
  ),
  '[B2] ongoing_management is active after placement_activate'
);
select is(
  (select legal_basis::text from public.consent_grants
    where id = ((current_setting('t.activate1')::jsonb)->>'ongoing_consent_id')::uuid),
  'contract',
  '[B3] activation-created consent has legal_basis = contract'
);
select ok(
  (select count(*) from public.audit_log
    where action='placement.activated' and entity_id = current_setting('t.placement')::uuid) >= 1,
  '[B4] placement.activated audit event written'
);
select ok(
  (select count(*) from public.audit_log
    where action='consent.granted'
      and entity_id = ((current_setting('t.activate1')::jsonb)->>'ongoing_consent_id')::uuid) >= 1,
  '[B5] consent.granted audit for the new ongoing_management consent'
);

-- [C] Idempotent: second activation returns the same consent_id + already_active=true.
do $$
declare result jsonb;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  result := public.placement_activate(current_setting('t.placement')::uuid);
  perform set_config('t.activate2', result::text, true);
end$$;
select ok(
  ((current_setting('t.activate2')::jsonb)->>'already_active')::boolean,
  '[C1] second activation reports already_active = true'
);
select is(
  (current_setting('t.activate1')::jsonb)->>'ongoing_consent_id',
  (current_setting('t.activate2')::jsonb)->>'ongoing_consent_id',
  '[C2] same ongoing_consent_id across activations (idempotent)'
);

-- [D] AuthZ: a caller without org.manage_all in the to_org is rejected.
-- Magnus (Nordic Recruit recruiter) does not have org.manage_all in FjordTech.
do $$
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002"}', true);
end$$;
select throws_ok(
  format($$select public.placement_activate(%L::uuid)$$, current_setting('t.placement')),
  'P0001', NULL::text,
  '[D1] caller without org.manage_all in to_org is rejected'
);

-- [E] activations_state queue reflects the activated row.
do $$
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
end$$;
select ok(
  exists (
    select 1 from jsonb_array_elements(
      (public.employer_activations_state('a1000000-0000-0000-0000-000000000002'::uuid))->'placements'
    ) e
    where (e->>'placement_id')::uuid = current_setting('t.placement')::uuid
      and (e->>'activated')::boolean = true
  ),
  '[E1] activations_state includes the placement, marked activated=true'
);

-- [F] AuthZ: someone without org.manage_all in the org is rejected by the read RPC too.
do $$
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002"}', true);
end$$;
select throws_ok(
  $$select public.employer_activations_state('a1000000-0000-0000-0000-000000000002'::uuid)$$,
  'P0001', NULL::text,
  '[F1] employer_activations_state rejects callers without org.manage_all'
);

select * from finish();
rollback;
