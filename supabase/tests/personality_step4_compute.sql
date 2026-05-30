-- Personality Step 4 — server-side compute tests.
--
-- Strategy: feed a deterministic, known-answer input set into the
-- PL/pgSQL helpers and the main RPC, then assert the outputs match the
-- numbers we'd get from the TypeScript engine (which has 47 tests of
-- its own). This is the cross-engine consistency check.
--
-- Note on RPC end-to-end: the full RPC needs a session + invite +
-- assessment row + responses, which means inserting through several
-- FK-bound tables in a transaction. We do that with hardcoded UUIDs
-- in a transaction that we rollback at the end so production data
-- isn't touched.

-- ─── 1. Pure-math helper checks ──────────────────────────────────────
do $$
declare
  v_t int;
  v_p int;
  v_z numeric;
begin
  -- percentile_to_t midpoint: 50th percentile → T=50.
  v_t := public._personality_percentile_to_t(50);
  if v_t <> 50 then raise exception 'percentileToT(50) expected 50, got %', v_t; end if;
  -- 84th → T≈60 (z=1)
  v_t := public._personality_percentile_to_t(84);
  if v_t not between 59 and 61 then raise exception 'percentileToT(84) expected 59..61, got %', v_t; end if;
  -- 16th → T≈40 (z=-1)
  v_t := public._personality_percentile_to_t(16);
  if v_t not between 39 and 41 then raise exception 'percentileToT(16) expected 39..41, got %', v_t; end if;
  -- 98th → T≈72 (z=2.17 because of +0.5 continuity correction; matches TS)
  v_t := public._personality_percentile_to_t(98);
  if v_t not between 70 and 73 then raise exception 'percentileToT(98) expected 70..73, got %', v_t; end if;

  -- invNormCdf sanity: p=0.5 → ~0
  v_z := public._personality_inv_norm_cdf(0.5);
  if abs(v_z) > 1e-4 then raise exception 'invNormCdf(0.5) expected ~0, got %', v_z; end if;
  -- p=0.8413 → ~1
  v_z := public._personality_inv_norm_cdf(0.8413);
  if abs(v_z - 1) > 1e-2 then raise exception 'invNormCdf(0.8413) expected ~1, got %', v_z; end if;

  -- Percentile lookup against a small deterministic breakpoints array.
  -- A 100-element [1, 2, 2, 2, ..., 5] would be ugly; use a fake "every
  -- bp = its index" so percentile(x) = floor(x) for x in 1..99.
  -- Construct: breakpoints = [1.5, 2.5, 3.5, ..., 100.5]
  v_p := public._personality_percentile(
    50.7,
    (select jsonb_agg((i::numeric) + 0.5) from generate_series(1, 100) i)
  );
  -- breakpoints below 50.7: those with i+0.5 < 50.7 → i ≤ 50 → 50 values
  if v_p <> 50 then raise exception 'percentile(50.7, sequential) expected 50, got %', v_p; end if;

  -- Clamp at 0 / 99 edges.
  v_p := public._personality_percentile(-100, (select jsonb_agg((i::numeric)+0.5) from generate_series(1,100) i));
  if v_p <> 0 then raise exception 'percentile(-100) expected 0, got %', v_p; end if;
  v_p := public._personality_percentile(1000, (select jsonb_agg((i::numeric)+0.5) from generate_series(1,100) i));
  if v_p <> 99 then raise exception 'percentile(1000) expected 99, got %', v_p; end if;

  raise notice 'personality step4: pure-math helpers ok';
end $$;

-- ─── 2. End-to-end RPC inside a rolled-back transaction ─────────────
-- We need: an org, a person, a consent, an assessment, an invite, a
-- session, and at least one personality response.  All keyed off
-- deterministic UUIDs that we clean up at the end via rollback.
do $$
declare
  v_org_id          uuid := '00000000-0000-0000-0000-0000000000a1';
  v_person_id       uuid := '00000000-0000-0000-0000-0000000000a2';
  v_consent_id      uuid := '00000000-0000-0000-0000-0000000000a3';
  v_assessment_id   uuid := '00000000-0000-0000-0000-0000000000a4';
  v_invite_id       uuid := '00000000-0000-0000-0000-0000000000a5';
  v_session_id      uuid := '00000000-0000-0000-0000-0000000000a6';
  v_instrument_id   uuid;
  v_item_id         uuid;
  v_result          jsonb;
  v_score_count     int;
  v_match_count     int;
  v_match           public.personality_role_matches%rowtype;
  r record;
begin
  -- Skip if the personality instrument isn't seeded yet (this test must
  -- still pass-by-skip on a CI env that has only run schema migrations).
  select id into v_instrument_id
    from public.assessment_instruments
   where key = 'personality_v1' and org_id is null and version = '1.0.0';
  if v_instrument_id is null then
    raise notice 'personality step4: instrument not seeded; skipping end-to-end test';
    return;
  end if;

  -- Seed minimal supporting rows. on conflict do nothing in case a
  -- prior test left stale data behind (we rollback, but if the test
  -- file is rerun outside a tx, conflicts shouldn't error).
  --
  -- NOTE: schema verification during audit revealed:
  --   * organizations has no `org_id` defaults; type enum is agency|employer
  --   * people doesn't take `org_id` directly (membership table separate)
  --   * assessments has NO consent_id column, uses `instrument_key` (text)
  --     not `instrument_id`, and requires `type` enum.
  --   * assessment_responses.consent_id IS NOT NULL.
  insert into public.organizations (id, name, type) values (v_org_id, '__test_org_personality', 'employer')
    on conflict (id) do nothing;
  insert into public.people (id, primary_email, full_name)
    values (v_person_id, '__test_personality@example.test', 'Test Person')
    on conflict (id) do nothing;
  -- Consent grant: minimal shape (purpose='hiring_decision').
  insert into public.consent_grants (id, person_id, granted_to_org_id, purpose)
    values (v_consent_id, v_person_id, v_org_id, 'hiring_decision')
    on conflict (id) do nothing;
  -- Assessment row uses instrument_key (text) not instrument_id (uuid).
  insert into public.assessments (id, org_id, person_id, type, instrument_key, status)
    values (v_assessment_id, v_org_id, v_person_id, 'personality', 'personality_v1', 'in_progress')
    on conflict (id) do nothing;
  -- Invite + session.
  insert into public.assessment_invites (id, org_id, assessment_id, person_id, consent_recorded_id, token, expires_at)
    values (v_invite_id, v_org_id, v_assessment_id, v_person_id, v_consent_id,
            '__test_personality_tok', now() + interval '14 days')
    on conflict (id) do nothing;
  insert into public.assessment_sessions
    (id, invite_id, invite_token, org_id, person_id, demo_mode, status, sections_json)
  values (v_session_id, v_invite_id, '__test_personality_tok', v_org_id, v_person_id, false,
          'in_progress', '{}'::jsonb)
    on conflict (id) do nothing;

  -- Submit a "5" (positive-keyed) for every conscientiousness item and
  -- a "1" (reverse-keyed) for every reverse one — both produce keyed=5
  -- so the trait mean = 5, which is at the top of the synthetic norms
  -- and should produce percentile=99.
  for r in
    select i.id, (i.item_json->>'reverse_score')::boolean as reverse
      from public.assessment_items i
     where i.instrument_id = v_instrument_id
       and i.item_json->>'trait_key' = 'conscientiousness'
  loop
    insert into public.assessment_responses
      (org_id, assessment_id, item_id, person_id, consent_id, response_json)
    values (v_org_id, v_assessment_id, r.id, v_person_id, v_consent_id,
            case when r.reverse then jsonb_build_object('value', 1)
                                else jsonb_build_object('value', 5) end)
    on conflict (assessment_id, item_id) do nothing;
  end loop;

  -- Submit similar full-bottom for psychopathy so we can verify the
  -- flag does NOT raise (low psychopathy stays well below the 75-85 thresholds).
  for r in
    select i.id, (i.item_json->>'reverse_score')::boolean as reverse
      from public.assessment_items i
     where i.instrument_id = v_instrument_id
       and i.item_json->>'trait_key' = 'psychopathy'
  loop
    insert into public.assessment_responses
      (org_id, assessment_id, item_id, person_id, consent_id, response_json)
    values (v_org_id, v_assessment_id, r.id, v_person_id, v_consent_id,
            case when r.reverse then jsonb_build_object('value', 5)
                                else jsonb_build_object('value', 1) end)
    on conflict (assessment_id, item_id) do nothing;
  end loop;

  -- Run the compute RPC.
  v_result := public.personality_compute_scores(v_session_id);
  if (v_result->>'ok')::boolean is not true then
    raise exception 'compute did not return ok=true: %', v_result;
  end if;

  select count(*) into v_score_count
    from public.assessment_scores
   where assessment_id = v_assessment_id
     and scale_key like 'trait:%';
  if v_score_count < 2 then
    raise exception 'expected at least 2 trait scores written (conscientiousness, psychopathy), got %', v_score_count;
  end if;

  -- Conscientiousness should be top-of-distribution → percentile=99,
  -- T near 78 (algorithm with +0.5 → invNormCdf(0.995) ~ 2.576 → T=76).
  declare
    v_pct int;
    v_t   int;
  begin
    select (validity_flags_json->>'percentile')::int, scaled_score::int
      into v_pct, v_t
      from public.assessment_scores
     where assessment_id = v_assessment_id and scale_key = 'trait:conscientiousness';
    if v_pct < 95 then raise exception 'expected conscientiousness percentile >= 95, got %', v_pct; end if;
    if v_t < 70 or v_t > 80 then raise exception 'expected conscientiousness T in 70..80, got %', v_t; end if;
  end;

  -- Every score row carries dev_stub provenance (norms are dev_stub).
  if exists (
    select 1 from public.assessment_scores
     where assessment_id = v_assessment_id and scale_key like 'trait:%'
       and (validity_status <> 'dev_stub' or _dev_stub is false)
  ) then
    raise exception 'personality scores must inherit dev_stub from synthetic norms';
  end if;

  -- Role matches: we expect 10 (one per seeded global template).
  select count(*) into v_match_count
    from public.personality_role_matches where session_id = v_session_id;
  if v_match_count < 10 then
    raise exception 'expected at least 10 role matches written, got %', v_match_count;
  end if;

  -- Every match row is dev_stub.
  if exists (
    select 1 from public.personality_role_matches
     where session_id = v_session_id
       and (validity_status <> 'dev_stub' or _dev_stub is false)
  ) then
    raise exception 'personality role matches must ship as dev_stub';
  end if;

  -- A high-conscientiousness candidate should score well on the
  -- lead_software_developer template's CON contribution.
  select * into v_match from public.personality_role_matches
   where session_id = v_session_id and role_key = 'lead_software_developer';
  if not found then raise exception 'no role match for lead_software_developer'; end if;
  if v_match.match_score is null then raise exception 'match_score should be non-null'; end if;
  -- Psychopathy flag at percentile <80 should NOT be raised.
  if jsonb_array_length(v_match.flags_json) > 0
     and exists (
       select 1 from jsonb_array_elements(v_match.flags_json) f
        where f->>'trait' = 'psychopathy'
     ) then
    raise exception 'low-psychopathy candidate should not raise a psychopathy flag';
  end if;

  raise notice 'personality step4: end-to-end compute ok (% scores, % matches)',
    v_score_count, v_match_count;

  -- Cleanup so re-runs are idempotent.
  delete from public.personality_role_matches where session_id = v_session_id;
  delete from public.assessment_scores         where assessment_id = v_assessment_id;
  delete from public.assessment_responses      where assessment_id = v_assessment_id;
  delete from public.assessment_sessions       where id = v_session_id;
  delete from public.assessment_invites        where id = v_invite_id;
  delete from public.assessments               where id = v_assessment_id;
  delete from public.consent_grants            where id = v_consent_id;
  delete from public.people                    where id = v_person_id;
  delete from public.organizations             where id = v_org_id;
end $$;
