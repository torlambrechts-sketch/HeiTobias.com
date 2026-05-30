-- Personality Module — Step 4: server-side compute.
--
-- Three layers:
--   1. Pure-math helpers (Acklam inverse-normal CDF, percentile lookup,
--      percentile→T conversion) — mirror src/lib/personality/scoring.ts
--      so the two engines stay congruent. The cross-engine test in
--      supabase/tests/personality_step4_compute.sql asserts this.
--   2. personality_compute_scores(p_session_id) — main RPC. Reads
--      assessment_responses for the session's personality items, computes
--      keyed-mean → percentile → T per trait, then evaluates every
--      relevant role template's match. Writes assessment_scores +
--      personality_role_matches rows. Audit-logs.
--   3. personality_role_match_recompute(p_session_id, p_role_key) —
--      single-template recompute helper (e.g. when a template changes).
--
-- All three are SECURITY DEFINER with `set search_path = ''` per the
-- platform's hardening discipline. Writes only run when called with
-- service-role privileges OR by an authenticated user with fit.compute
-- on the session's org. The function checks that explicitly.
--
-- Provenance: every score / match row written by this function carries
-- validity_status='dev_stub' + _dev_stub=true, because the norms it
-- bisects against are dev_stub. When H-2 closes (real Nordic norms
-- with population_key='nordic_v1' + validity_status='validated'), this
-- function's body needs ONE LINE change to read the new norms — the
-- flag-propagation logic computes the right validity_status
-- automatically from the worst-of (norm.validity_status,
-- template.validity_status).

-- ─── 1a. Acklam inverse-normal CDF (PL/pgSQL port) ───────────────────
create or replace function public._personality_inv_norm_cdf(p numeric)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  -- Coefficients (Acklam 2003). Same values as src/lib/personality/scoring.ts.
  a constant numeric[] := array[-3.969683028665376e+01, 2.209460984245205e+02,
                                -2.759285104469687e+02, 1.383577518672690e+02,
                                -3.066479806614716e+01, 2.506628277459239e+00];
  b constant numeric[] := array[-5.447609879822406e+01, 1.615858368580409e+02,
                                -1.556989798598866e+02, 6.680131188771972e+01,
                                -1.328068155288572e+01];
  c constant numeric[] := array[-7.784894002430293e-03, -3.223964580411365e-01,
                                -2.400758277161838e+00, -2.549732539343734e+00,
                                 4.374664141464968e+00,  2.938163982698783e+00];
  d constant numeric[] := array[7.784695709041462e-03,  3.224671290700398e-01,
                                2.445134137142996e+00,  3.754408661907416e+00];
  plow  constant numeric := 0.02425;
  phigh constant numeric := 0.97575;  -- 1 - plow
  q numeric;
  r numeric;
begin
  if p is null then return null; end if;
  if p < plow then
    q := sqrt(-2 * ln(p));
    return (((((c[1]*q + c[2])*q + c[3])*q + c[4])*q + c[5])*q + c[6]) /
           ((((d[1]*q + d[2])*q + d[3])*q + d[4])*q + 1);
  end if;
  if p <= phigh then
    q := p - 0.5;
    r := q * q;
    return (((((a[1]*r + a[2])*r + a[3])*r + a[4])*r + a[5])*r + a[6]) * q /
           (((((b[1]*r + b[2])*r + b[3])*r + b[4])*r + b[5])*r + 1);
  end if;
  q := sqrt(-2 * ln(1 - p));
  return -(((((c[1]*q + c[2])*q + c[3])*q + c[4])*q + c[5])*q + c[6]) /
          ((((d[1]*q + d[2])*q + d[3])*q + d[4])*q + 1);
end;
$$;
revoke execute on function public._personality_inv_norm_cdf(numeric) from public;
grant  execute on function public._personality_inv_norm_cdf(numeric) to service_role, authenticated;

-- ─── 1b. Percentile lookup against a 100-breakpoint norm row ────────
-- Mirrors percentile() in scoring.ts: strict-less comparison, clamped to
-- 0..99. With 100 breakpoints, count(*) where bp < raw is itself the
-- percentile rank (no division needed).
create or replace function public._personality_percentile(p_raw numeric, p_bp jsonb)
returns int
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_count int;
begin
  if p_raw is null or p_bp is null or jsonb_array_length(p_bp) = 0 then
    return null;
  end if;
  select count(*) into v_count
    from jsonb_array_elements_text(p_bp) e
   where e::numeric < p_raw;
  return greatest(0, least(99, v_count));
end;
$$;
revoke execute on function public._personality_percentile(numeric, jsonb) from public;
grant  execute on function public._personality_percentile(numeric, jsonb) to service_role, authenticated;

-- ─── 1c. percentile → T-score ────────────────────────────────────────
-- Mirrors percentileToT() in scoring.ts: (p+0.5)/100 continuity
-- correction, clamped to [0.001, 0.999], then T = 50 + 10*z.
create or replace function public._personality_percentile_to_t(p int)
returns int
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_prob numeric;
  v_z    numeric;
begin
  if p is null then return null; end if;
  v_prob := least(0.999, greatest(0.001, (p + 0.5) / 100.0));
  v_z := public._personality_inv_norm_cdf(v_prob);
  return round(50 + 10 * v_z)::int;
end;
$$;
revoke execute on function public._personality_percentile_to_t(int) from public;
grant  execute on function public._personality_percentile_to_t(int) to service_role, authenticated;

-- ─── 2. personality_compute_scores(session_id) ───────────────────────
-- Main RPC. Reads the candidate's personality responses, computes per-
-- trait scores + every relevant role-template match, writes them all.
-- Idempotent: upserts on (assessment_id, scale_key) and
-- (session_id, role_key).
--
-- Authorization: anon / authenticated callers must hold fit.compute on
-- the session's org, OR be the session's own person (self-recompute),
-- OR be a platform_admin. service_role bypasses the check.
create or replace function public.personality_compute_scores(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session       public.assessment_sessions%rowtype;
  v_invite        public.assessment_invites%rowtype;
  v_instrument_id uuid;
  v_actor         uuid := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
  v_is_service    boolean := (select current_user = 'service_role');
  v_trait_count   int := 0;
  v_match_count   int := 0;
  r record;
  tt record;
  v_norm          public.personality_norms%rowtype;
  v_raw           numeric;
  v_percentile    int;
  v_t_score       int;
  v_template_org  uuid;
  v_pcts          jsonb;
  v_penalty       numeric;
  v_contribs      jsonb;
  v_flags         jsonb;
  v_match         int;
  v_match_stub    boolean;
begin
  select * into v_session from public.assessment_sessions where id = p_session_id;
  if not found then
    raise exception 'personality_compute_scores: session not found';
  end if;
  select * into v_invite from public.assessment_invites where id = v_session.invite_id;

  -- AuthZ. service_role bypasses; otherwise need fit.compute, or be the
  -- session's own person, or platform_admin.
  if not v_is_service
     and not public.has_permission(v_session.org_id, 'fit.compute')
     and not public.is_self(v_session.person_id)
     and not coalesce(public.is_platform_admin(), false) then
    raise exception 'personality_compute_scores: forbidden';
  end if;

  select id into v_instrument_id
    from public.assessment_instruments
   where key = 'personality_v1' and org_id is null and version = '1.0.0';
  if v_instrument_id is null then
    raise exception 'personality_compute_scores: instrument personality_v1 not found';
  end if;

  -- Build a CTE-driven trait-mean table from responses, joined to items
  -- so we know the trait + reverse-score for each response. Then persist
  -- per-trait scores into assessment_scores.
  --
  -- The keyed mean is computed inline:
  --   keyed_val = case reverse_score
  --                 when true  then (5 + 1) - response
  --                 else                  response
  --               end
  -- (5 because all items use Likert-5; future scales would read item_json.scale.)

  for r in
    with resp as (
      select i.item_json->>'trait_key' as trait_key,
             (i.item_json->>'reverse_score')::boolean as reverse_score,
             (rsp.response_json->>'value')::numeric as response
        from public.assessment_responses rsp
        join public.assessment_items i on i.id = rsp.item_id
       where rsp.assessment_id = v_invite.assessment_id
         and i.instrument_id = v_instrument_id
    ),
    keyed as (
      select trait_key,
             case when reverse_score then (5 + 1) - response else response end as keyed_val
        from resp
       where response is not null
    ),
    means as (
      select trait_key,
             avg(keyed_val)::numeric as mean,
             count(*)::int as n
        from keyed
       group by trait_key
    )
    select m.trait_key, m.mean, m.n,
           pn.breakpoints, pn.validity_status::text as norm_status,
           pn._dev_stub as norm_stub
      from means m
      left join public.personality_norms pn
             on pn.trait_key = m.trait_key
            and pn.population_key = 'global_dev_stub'  -- TODO: switch to nordic_v1 when H-2 closes
  loop
    v_raw        := r.mean;
    v_percentile := public._personality_percentile(v_raw, r.breakpoints);
    v_t_score    := public._personality_percentile_to_t(v_percentile);

    insert into public.assessment_scores
      (org_id, assessment_id, person_id, consent_id,
       scale_key, raw_score, scaled_score, norm_band,
       validity_status, _dev_stub, validity_flags_json)
    values (
      v_session.org_id, v_invite.assessment_id, v_session.person_id, v_invite.consent_recorded_id,
      'trait:' || r.trait_key,
      v_raw,                              -- the trait mean is a real number
      v_t_score,                          -- T-score; null if no percentile
      case
        when v_percentile is null      then null
        when v_percentile < 30         then 'low'
        when v_percentile < 70         then 'mid'
        else                                'high'
      end,
      coalesce(r.norm_status, 'dev_stub')::public.validity_status,
      coalesce(r.norm_stub, true) or r.n < 5,     -- < 5 keyed items also stubs the score
      jsonb_build_object(
        'percentile', v_percentile,
        'n_keyed_responses', r.n,
        'norm_population', 'global_dev_stub',
        'note', case when r.n < 5 then 'fewer than 5 keyed items — score is exploratory only'
                                  else null end
      )
    )
    on conflict (assessment_id, scale_key) do update set
      raw_score = excluded.raw_score,
      scaled_score = excluded.scaled_score,
      norm_band = excluded.norm_band,
      validity_status = excluded.validity_status,
      _dev_stub = excluded._dev_stub,
      validity_flags_json = excluded.validity_flags_json,
      computed_at = now(),
      updated_at = now();
    v_trait_count := v_trait_count + 1;
  end loop;

  -- Build a per-trait percentile lookup blob for the role-match loop.
  select coalesce(jsonb_object_agg(
    replace(scale_key, 'trait:', ''),
    (validity_flags_json->>'percentile')::int
  ), '{}'::jsonb)
    into v_pcts
    from public.assessment_scores
   where assessment_id = v_invite.assessment_id
     and scale_key like 'trait:%';

  -- For every role template (global), compute a match. The
  -- match-template-trait join filters out flag rows from the
  -- contributing-trait loop; flags are computed separately.
  for r in
    select * from public.personality_role_templates where org_id is null
  loop
    v_penalty := 0;
    v_contribs := '[]'::jsonb;
    v_flags    := '[]'::jsonb;
    v_match_stub := true;  -- the templates themselves are dev_stub today
    v_template_org := r.org_id;

    -- Contributors (review_flag = false).
    for tt in
      select trait_key, band_low, band_high, direction::text as direction, weight
        from public.personality_role_template_traits
       where role_key = r.role_key and (org_id is not distinct from r.org_id)
         and review_flag = false
    loop
      declare
        v_pct numeric := nullif(v_pcts->>tt.trait_key, '')::numeric;
        v_dist numeric;
        v_severity numeric;
        v_p numeric;
      begin
        if v_pct is null then continue; end if;
        if tt.direction = 'higher_better' then
          v_dist := case when v_pct < tt.band_low then (tt.band_low - v_pct) else 0 end;
        elsif tt.direction = 'lower_better' then
          v_dist := case when v_pct > tt.band_high then (v_pct - tt.band_high) else 0 end;
        else  -- target_band
          v_dist := case
            when v_pct < tt.band_low  then (tt.band_low  - v_pct)
            when v_pct > tt.band_high then (v_pct - tt.band_high)
            else 0
          end;
        end if;
        v_severity := least(1, v_dist / r.match_tolerance_ref);
        v_p := tt.weight * v_severity;
        v_penalty := v_penalty + v_p;
        v_contribs := v_contribs || jsonb_build_object(
          'trait', tt.trait_key,
          'percentile', v_pct::int,
          'band', jsonb_build_array(tt.band_low, tt.band_high),
          'direction', tt.direction,
          'weight', tt.weight,
          'severity', round(v_severity::numeric, 3),
          'penalty',  round(v_p::numeric, 3)
        );
      end;
    end loop;

    -- HUMAN-REVIEW flags (review_flag = true). Never affect the score.
    for tt in
      select trait_key, flag_threshold
        from public.personality_role_template_traits
       where role_key = r.role_key and (org_id is not distinct from r.org_id)
         and review_flag = true
    loop
      declare
        v_pct numeric := nullif(v_pcts->>tt.trait_key, '')::numeric;
      begin
        if v_pct is not null and tt.flag_threshold is not null and v_pct >= tt.flag_threshold then
          v_flags := v_flags || jsonb_build_object(
            'trait', tt.trait_key,
            'percentile', v_pct::int,
            'threshold', tt.flag_threshold
          );
        end if;
      end;
    end loop;

    -- Sort contributions by penalty desc (mirrors TS engine).
    select coalesce(jsonb_agg(c order by (c->>'penalty')::numeric desc), '[]'::jsonb)
      into v_contribs
      from jsonb_array_elements(v_contribs) c;

    v_match := greatest(0, least(100, round(100 * (1 - v_penalty))::int));

    insert into public.personality_role_matches
      (org_id, session_id, person_id, role_key, role_template_org_id,
       match_score, contributions_json, flags_json,
       validity_status, _dev_stub)
    values (
      v_session.org_id, v_session.id, v_session.person_id, r.role_key, v_template_org,
      v_match, v_contribs, v_flags,
      'dev_stub',           -- inherits worst-of (norm, template) provenance — both are dev_stub today
      true
    )
    on conflict (session_id, role_key) do update set
      match_score = excluded.match_score,
      contributions_json = excluded.contributions_json,
      flags_json = excluded.flags_json,
      validity_status = excluded.validity_status,
      _dev_stub = excluded._dev_stub,
      computed_at = now(),
      updated_at = now();
    v_match_count := v_match_count + 1;
  end loop;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
  values (
    v_session.org_id, v_actor, 'personality.compute', 'assessment_sessions', v_session.id,
    jsonb_build_object('traits_scored', v_trait_count, 'role_matches_written', v_match_count)
  );

  return jsonb_build_object(
    'ok', true,
    'session_id', v_session.id,
    'traits_scored', v_trait_count,
    'role_matches_written', v_match_count
  );
end;
$$;
revoke execute on function public.personality_compute_scores(uuid) from public;
grant  execute on function public.personality_compute_scores(uuid) to authenticated, service_role;

-- ─── 3. personality_role_match_recompute(session_id, role_key) ──────
-- Convenience wrapper: re-run the role-match leg for one template,
-- assuming the trait scores already exist. Calls into
-- personality_compute_scores when scores are missing (so the recompute
-- path always produces a consistent state). For Phase 1 simplicity we
-- just call the full RPC; a future split can be done if perf demands.
create or replace function public.personality_role_match_recompute(
  p_session_id uuid, p_role_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Validate the role_key exists; surfaces a clear error early.
  if not exists (select 1 from public.personality_role_templates where role_key = p_role_key) then
    raise exception 'personality_role_match_recompute: role_key % not found', p_role_key;
  end if;
  return public.personality_compute_scores(p_session_id);
end;
$$;
revoke execute on function public.personality_role_match_recompute(uuid, text) from public;
grant  execute on function public.personality_role_match_recompute(uuid, text) to authenticated, service_role;

comment on function public.personality_compute_scores(uuid) is
  'Compute personality trait scores + role matches for a session. Idempotent. Writes to assessment_scores + personality_role_matches; audit-logs personality.compute. All output rows ship as validity_status=dev_stub until H-2 closes (real Nordic norms) and H-3 + H-7 close (validated role templates).';
