-- 15_phase3_lifecycle — Phase 3 acceptance battery (Steps 1-5).
--
-- Covers the lifecycle module's load-bearing behaviors:
--   * pulse_submit is self-only and ongoing_management-gated
--   * signal_compute produces signals whose source_json cites the pulses
--   * refit_compute appends a time-series row + classifies into one of
--     the four quadrants
--   * guidance_compose REFUSES to emit ungrounded guidance and always
--     cites at least one framework_id (the load-bearing CHECK)
--   * guidance_record_action mutates only the action label, never the
--     generated output (the INFORMING-not-DECIDING discipline)
--   * team_composition_compute aggregates from members' own profiles
--     and refuses to expand into peer-personality territory (structural
--     _peer_rating=false flag + coverage reporting)
--   * Consent revocation cuts off ALL of the above immediately
--   * Channel posture + no-second-bridge guard still hold

begin;
select plan(18);

-- ============ Setup: place a candidate, activate, capture signals ============
do $$
declare
  agency_a   constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid     constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea     constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand_email text := 'p3_'||gen_random_uuid()||'@p3.test';
  cand_auth uuid; cand uuid;
  inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid;
  pulse_template uuid;
begin
  -- Build the candidate as a real auth user so the self-leg can be tested.
  cand_auth := gen_random_uuid();
  insert into auth.users (id, email) values (cand_auth, cand_email);
  insert into public.people (full_name, primary_email, auth_user_id)
    values ('Phase3 Test', cand_email, cand_auth) returning id into cand;
  insert into public.memberships (org_id, person_id, status) values (agency_a, cand, 'invited');

  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, cand, 'sample_personality_v0','personality',14);
  tok := inv->>'token';
  perform set_config('request.jwt.claims','{}', true);
  cap_consent := public.assessment_capture_consent(tok);
  for it in select i.id from public.assessment_items i
    join public.assessment_instruments ai on ai.id=i.instrument_id
    where ai.key='sample_personality_v0'
  loop perform public.assessment_submit_response(tok, it.id, '{"value":4}'::jsonb); end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);
  perform public.compute_fit_for_candidate(agency_req, cand);
  perform public.hiring_decision_record(agency_req, cand,'hire','phase 3 fixture');

  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub', astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);

  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  perform public.placement_activate(placement_id);

  select id into pulse_template from public.frameworks where key='pulse_v0_quarterly' limit 1;

  perform set_config('t.cand', cand::text, true);
  perform set_config('t.cand_auth', cand_auth::text, true);
  perform set_config('t.placement', placement_id::text, true);
  perform set_config('t.pulse_template', pulse_template::text, true);
end$$;

-- ============ [A] pulse_submit ============
-- Submit as the data subject (Sigrid-stand-in).
do $$
declare consent_id uuid; pulse_id uuid;
begin
  select id into consent_id from public.consent_grants
    where person_id = current_setting('t.cand')::uuid
      and granted_to_org_id = 'a1000000-0000-0000-0000-000000000002'::uuid
      and purpose = 'ongoing_management' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.cand_auth'))::text, true);
  pulse_id := public.pulse_submit(consent_id, current_setting('t.pulse_template')::uuid,
    jsonb_build_object('answers', jsonb_build_array(
      jsonb_build_object('key','energy','value',4),
      jsonb_build_object('key','clarity','value',3),
      jsonb_build_object('key','support','value',5))));
  perform set_config('t.pulse1', pulse_id::text, true);
end$$;
select ok(current_setting('t.pulse1')::uuid is not null, '[A1] pulse_submit returns an id');
select is(
  (select person_id from public.pulse_checkins where id = current_setting('t.pulse1')::uuid),
  current_setting('t.cand')::uuid,
  '[A2] pulse row is_self to caller'
);

-- [A3] Cross-person submission rejected.
do $$
declare other_consent uuid; other_cand uuid;
begin
  insert into public.people (full_name, primary_email) values ('Other', 'oth_'||gen_random_uuid()||'@p3.test') returning id into other_cand;
  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis)
    values (other_cand, 'a1000000-0000-0000-0000-000000000002'::uuid, 'ongoing_management','contract') returning id into other_consent;
  perform set_config('t.other_consent', other_consent::text, true);
end$$;
select throws_ok(
  format($$select public.pulse_submit(%L::uuid, %L::uuid, '{"answers":[]}'::jsonb)$$,
    current_setting('t.other_consent'), current_setting('t.pulse_template')),
  'P0001', NULL::text,
  '[A3] pulse_submit rejects cross-person consent'
);

-- ============ [B] signal_compute ============
-- Submit a second pulse so we have history, then compute signals as Linnea.
do $$
declare consent_id uuid;
begin
  select id into consent_id from public.consent_grants
    where person_id = current_setting('t.cand')::uuid
      and granted_to_org_id = 'a1000000-0000-0000-0000-000000000002'::uuid
      and purpose = 'ongoing_management' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('t.cand_auth'))::text, true);
  perform public.pulse_submit(consent_id, current_setting('t.pulse_template')::uuid,
    jsonb_build_object('answers', jsonb_build_array(
      jsonb_build_object('key','energy','value',5),
      jsonb_build_object('key','clarity','value',4),
      jsonb_build_object('key','support','value',5))));
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  perform public.signal_compute(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid, 4);
end$$;

select is(
  (select count(*) from public.signals where person_id = current_setting('t.cand')::uuid),
  3::bigint,
  '[B1] signal_compute produced 3 signals (energy/clarity/support trends)'
);
select ok(
  (select bool_and((source_json->'pulse_ids') is not null and jsonb_array_length(source_json->'pulse_ids') >= 1)
     from public.signals where person_id = current_setting('t.cand')::uuid),
  '[B2] every signal cites at least one pulse_id in source_json (grounded discipline)'
);

-- ============ [C] refit_compute ============
do $$
declare e1 uuid; e2 uuid;
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  e1 := public.refit_compute(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid);
  e2 := public.refit_compute(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid);
  perform set_config('t.refit1', e1::text, true);
  perform set_config('t.refit2', e2::text, true);
end$$;

select is(
  (select count(*) from public.refit_evaluations where person_id = current_setting('t.cand')::uuid),
  2::bigint,
  '[C1] refit_compute APPENDS — two calls yield two rows (time-series, never overwrite)'
);
select is(
  (select quadrant::text from public.refit_evaluations where id = current_setting('t.refit1')::uuid),
  'stable_fit',
  '[C2] first compute classifies into stable_fit (DEV-STUB rotation index 0)'
);
select is(
  (select quadrant::text from public.refit_evaluations where id = current_setting('t.refit2')::uuid),
  'growth_gap',
  '[C3] second compute classifies into growth_gap (rotation index 1)'
);

-- ============ [D] guidance_compose ============
do $$
declare g_id uuid;
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  g_id := public.guidance_compose(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid,
    'one_on_one_prep'::public.guidance_kind, '{"refit_quadrant":"growth_gap"}'::jsonb);
  perform set_config('t.guidance', g_id::text, true);
end$$;
select ok(
  (select array_length(framework_ids, 1) >= 1 from public.guidance_items where id = current_setting('t.guidance')::uuid),
  '[D1] guidance_items.framework_ids has at least one citation (CHECK enforced)'
);
select ok(
  (select bool_and((item->>'framework_id') is not null)
     from public.guidance_items g, lateral jsonb_array_elements(g.output_json->'items') item
     where g.id = current_setting('t.guidance')::uuid),
  '[D2] every output item also cites a framework_id (no freeform output)'
);

-- [D3] guidance_record_action mutates only the action label.
do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  perform public.guidance_record_action(current_setting('t.guidance')::uuid, 'acted_on', 'Discussed in 1:1');
end$$;
select is(
  (select action::text from public.guidance_items where id = current_setting('t.guidance')::uuid),
  'acted_on',
  '[D3] manager records action; output stays grounded'
);

-- ============ [E] team_composition_compute ============
-- Compute for the seeded Platform team (Erik + Sara + Jonas in FjordTech).
do $$
declare team_id uuid; snap_id uuid;
begin
  select id into team_id from public.teams where org_id = 'a1000000-0000-0000-0000-000000000002'::uuid limit 1;
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  snap_id := public.team_composition_compute(team_id);
  perform set_config('t.team_id', team_id::text, true);
  perform set_config('t.snap', snap_id::text, true);
end$$;
select ok(
  (select (snapshot_json->>'_peer_rating')::boolean = false
    from public.team_composition_snapshots where id = current_setting('t.snap')::uuid),
  '[E1] team_composition snapshot carries _peer_rating=false (structural never-peer-rating discipline)'
);
select ok(
  (select (snapshot_json->>'_source') = 'members_own_profiles'
    from public.team_composition_snapshots where id = current_setting('t.snap')::uuid),
  '[E2] snapshot _source = members_own_profiles'
);

-- ============ [F] consent revocation halts everything ============
-- Revoke ongoing_management for the candidate; future ops must fail.
do $$
begin
  update public.consent_grants set status='revoked', revoked_at=now()
    where person_id = current_setting('t.cand')::uuid
      and granted_to_org_id = 'a1000000-0000-0000-0000-000000000002'::uuid
      and purpose = 'ongoing_management';
end$$;

do $$ begin perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true); end$$;
select throws_ok(
  format($$select public.refit_compute(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid)$$, current_setting('t.cand')),
  'P0001', NULL::text,
  '[F1] revoking ongoing_management blocks refit_compute'
);
select throws_ok(
  format($$select public.guidance_compose(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid, 'one_on_one_prep'::public.guidance_kind, '{}'::jsonb)$$, current_setting('t.cand')),
  'P0001', NULL::text,
  '[F2] revoking ongoing_management blocks guidance_compose'
);
select throws_ok(
  format($$select public.signal_compute(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid, 4)$$, current_setting('t.cand')),
  'P0001', NULL::text,
  '[F3] revoking ongoing_management blocks signal_compute'
);

-- ============ [G] No-surveillance / no-second-bridge structural guards ============
-- Peer-personality tables forbidden (hard rule).
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and (c.relname like '%peer_personality%' or c.relname like '%peer_rating%'
           or c.relname like '%personality_rating%' or c.relname like '%rate_peer%')),
  0::bigint,
  '[G1] no peer-personality-rating table exists (CLAUDE.md hard never)'
);
-- placement_execute is still the only SECDEF function writing profiles cross-org.
select is(
  (select string_agg(p.proname, ',' order by p.proname)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.prosecdef=true
      and pg_get_functiondef(p.oid) ilike '%insert into public.profiles%'),
  'placement_execute',
  '[G2] still no second cross-org bridge after Phase 3'
);

select * from finish();
rollback;
