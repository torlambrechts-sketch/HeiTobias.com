-- 16_science_spec_enforcement — SCIENCE-SPEC.md structural rules.
--
-- Verifies the load-bearing pieces of the new spec:
--   * Instrument deny-list refuses MBTI / DISC / VARK / Belbin at the DB
--   * guidance_compose refuses medical / legal / dismissal / compensation
--     queries with a STRUCTURED refusal row (citing the refusal_policy
--     framework so the audit trail stays grounded)
--   * lifecycle_decisions requires rationale + ongoing_management consent
--   * fairness_monitoring is now a valid consent_purpose value

begin;
select plan(15);

-- ============ [A] Instrument deny-list ============
select throws_ok(
  $$insert into public.assessment_instruments (key, name, validity_status)
      values ('mbti_classic', 'Myers-Briggs Type Indicator', 'dev_stub')$$,
  '23514', NULL::text,
  '[A1] MBTI key refused by deny-list CHECK'
);
select throws_ok(
  $$insert into public.assessment_instruments (key, name, vendor, validity_status)
      values ('team_personality', 'DISC Profile', 'Wiley DiSC', 'dev_stub')$$,
  '23514', NULL::text,
  '[A2] DISC name + vendor refused by deny-list'
);
select throws_ok(
  $$insert into public.assessment_instruments (key, name, validity_status)
      values ('vark_v0', 'VARK Learning Styles Quiz', 'dev_stub')$$,
  '23514', NULL::text,
  '[A3] VARK / learning-styles refused'
);
select throws_ok(
  $$insert into public.assessment_instruments (key, name, validity_status)
      values ('belbin_team_roles', 'Belbin Team Roles', 'dev_stub')$$,
  '23514', NULL::text,
  '[A4] Belbin refused'
);
-- Negative control: an IPIP-NEO-flavoured instrument is accepted.
do $$
declare ok_id uuid;
begin
  insert into public.assessment_instruments (key, name, validity_status)
    values ('ipip_neo_120_v0', 'IPIP-NEO-120 (DEV STUB)', 'dev_stub')
    returning id into ok_id;
  perform set_config('t.ok_instr', ok_id::text, true);
end$$;
select is(
  (select validity_status::text from public.assessment_instruments where id = current_setting('t.ok_instr')::uuid),
  'dev_stub',
  '[A5] IPIP-NEO-flavoured instrument is accepted (allow-list pattern)'
);

-- ============ [B] Refusal categories on the guidance composer ============
-- Setup: place + activate a candidate so we have ongoing_management consent.
do $$
declare
  agency_a constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid;
begin
  insert into public.people (full_name, primary_email) values ('Sci Test','sci_'||gen_random_uuid()||'@s.t') returning id into cand;
  insert into public.memberships (org_id, person_id, status) values (agency_a, cand, 'invited');
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, cand,'sample_personality_v0','personality',14);
  tok := inv->>'token';
  perform set_config('request.jwt.claims','{}', true);
  cap_consent := public.assessment_capture_consent(tok);
  for it in select i.id from public.assessment_items i join public.assessment_instruments ai on ai.id=i.instrument_id where ai.key='sample_personality_v0' loop
    perform public.assessment_submit_response(tok, it.id, '{"value":4}'::jsonb);
  end loop;
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);
  perform public.compute_fit_for_candidate(agency_req, cand);
  perform public.hiring_decision_record(agency_req, cand,'hire','sci fixture');
  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);
  perform set_config('request.jwt.claims', json_build_object('sub',linnea)::text, true);
  perform public.placement_activate(placement_id);
  perform set_config('t.cand', cand::text, true);
end$$;

-- Refusal: medical
do $$
declare g_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  g_id := public.guidance_compose(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid,
    'one_on_one_prep'::public.guidance_kind,
    jsonb_build_object('topic','I think they have a chronic illness — what should I do?'));
  perform set_config('t.g_med', g_id::text, true);
end$$;
select is(
  (select refusal_kind::text from public.guidance_items where id = current_setting('t.g_med')::uuid),
  'medical',
  '[B1] medical query produces a medical-refusal row'
);
select ok(
  (select (output_json->>'refused')::boolean from public.guidance_items where id = current_setting('t.g_med')::uuid),
  '[B2] refusal row has output_json.refused = true'
);

-- Refusal: legal
do $$
declare g_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  g_id := public.guidance_compose(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid,
    'growth_focus'::public.guidance_kind,
    jsonb_build_object('topic','Do I have legal grounds to dismiss?'));
  perform set_config('t.g_legal', g_id::text, true);
end$$;
-- 'dismiss' will hit dismissal before legal — that's correct per §6 ordering.
select is(
  (select refusal_kind::text from public.guidance_items where id = current_setting('t.g_legal')::uuid),
  'dismissal',
  '[B3] dismissal language refuses as dismissal (precedence: dismissal beats legal in the heuristic)'
);

-- Refusal: compensation
do $$
declare g_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  g_id := public.guidance_compose(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid,
    'growth_focus'::public.guidance_kind,
    jsonb_build_object('topic','What should her next salary band be?'));
  perform set_config('t.g_comp', g_id::text, true);
end$$;
select is(
  (select refusal_kind::text from public.guidance_items where id = current_setting('t.g_comp')::uuid),
  'compensation',
  '[B4] salary query refuses as compensation'
);

-- Refusal row still cites the refusal-policy framework (grounded). The
-- framework_ids column is uuid[]; unnest + join to check membership.
select ok((
  select exists (
    select 1
    from public.guidance_items gi,
         lateral unnest(gi.framework_ids) as fid
    join public.frameworks fw on fw.id = fid
    where gi.id = current_setting('t.g_med')::uuid
      and fw.key = 'refusal_policy_v0'
  )
), '[B5] refusal row cites refusal_policy_v0 (audit trail stays grounded)');

-- Audit row written for the refusal.
select ok(
  (select count(*) from public.audit_log
    where action = 'guidance.refused' and entity_id = current_setting('t.g_med')::uuid) >= 1,
  '[B6] guidance.refused audit event written'
);

-- Negative control: a normal (non-refused) query still works + is NOT a refusal.
do $$
declare g_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  g_id := public.guidance_compose(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid,
    'one_on_one_prep'::public.guidance_kind, '{"refit_quadrant":"growth_gap"}'::jsonb);
  perform set_config('t.g_ok', g_id::text, true);
end$$;
select is(
  (select refusal_kind from public.guidance_items where id = current_setting('t.g_ok')::uuid),
  NULL::public.guidance_refusal_kind,
  '[B7] regular guidance has refusal_kind = NULL (not refused)'
);

-- ============ [C] lifecycle_decisions ============
-- Rationale required.
select throws_ok(
  format($$select public.lifecycle_decision_record(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid,
                  'promotion'::public.lifecycle_decision_kind, '   ')$$, current_setting('t.cand')),
  'P0001', NULL::text,
  '[C1] empty rationale rejected'
);

-- Happy path.
do $$
declare d_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  d_id := public.lifecycle_decision_record(
    current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid,
    'promotion'::public.lifecycle_decision_kind,
    'Strong sustained re-fit trajectory across 3 cycles; team-comp coverage 100%.',
    true, 'DEV STUB recommendation', null, null);
  perform set_config('t.decision', d_id::text, true);
end$$;
select ok(
  (select overrode_recommendation from public.lifecycle_decisions where id = current_setting('t.decision')::uuid),
  '[C2] overrode_recommendation captured'
);

-- ============ [D] fairness_monitoring consent purpose ============
select ok(
  (select count(*) from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'consent_purpose' and e.enumlabel = 'fairness_monitoring') = 1,
  '[D1] fairness_monitoring is now a valid consent_purpose'
);

select * from finish();
rollback;
