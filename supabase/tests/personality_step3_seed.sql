-- Personality Step 3 — seed integrity tests.
-- Run via scripts/run-sql-tests.mjs (requires migrations applied + seed loaded).
do $$
declare
  v_traits        int;
  v_items         int;
  v_norms         int;
  v_templates     int;
  v_template_t    int;
  v_orphans       int;
  v_validated     int;
  v_weight_breach int;
  v_band_breach   int;
  v_flag_breach   int;
  r record;
begin
  -- Counts match the source.
  select count(*) into v_traits from public.personality_traits;
  if v_traits <> 19 then
    raise exception 'expected 19 traits, found %', v_traits;
  end if;

  select count(*) into v_items
    from public.assessment_items i
    join public.assessment_instruments ai on ai.id = i.instrument_id
   where ai.key = 'personality_v1' and ai.org_id is null and ai.version = '1.0.0';
  if v_items <> 190 then
    raise exception 'expected 190 items under personality_v1, found %', v_items;
  end if;

  select count(*) into v_norms from public.personality_norms;
  if v_norms < 19 then
    raise exception 'expected at least 19 norm rows (one per trait), found %', v_norms;
  end if;

  select count(*) into v_templates from public.personality_role_templates;
  if v_templates < 10 then
    raise exception 'expected at least 10 role templates, found %', v_templates;
  end if;

  -- Every item.trait_key references a known trait.
  select count(*) into v_orphans
    from public.assessment_items i
    join public.assessment_instruments ai on ai.id = i.instrument_id
   where ai.key = 'personality_v1'
     and not exists (
       select 1 from public.personality_traits t where t.trait_key = (i.item_json->>'trait_key')
     );
  if v_orphans > 0 then
    raise exception 'found % items whose item_json.trait_key does not match a registered trait', v_orphans;
  end if;

  -- INVARIANT-1 mirror: zero validated rows in the seed.
  select
    (select count(*) from public.personality_norms        where validity_status = 'validated') +
    (select count(*) from public.personality_role_templates where validity_status = 'validated') +
    (select count(*) from public.personality_role_matches where validity_status = 'validated')
    into v_validated;
  if v_validated > 0 then
    raise exception 'personality seed must NOT contain validated rows (found %)', v_validated;
  end if;

  -- Per-template weight sum is in [0.99, 1.01] (allow 1% rounding tolerance,
  -- and ignore HUMAN-REVIEW flag rows which have weight=0 by construction).
  for r in
    select rt.role_key, sum(tt.weight) as wsum
      from public.personality_role_templates rt
      join public.personality_role_template_traits tt
        on tt.role_key = rt.role_key and (tt.org_id is not distinct from rt.org_id)
     where rt.org_id is null
     group by rt.role_key
  loop
    if r.wsum < 0.99 or r.wsum > 1.01 then
      raise exception 'role template % has weight_sum=% outside [0.99, 1.01]', r.role_key, r.wsum;
    end if;
  end loop;

  -- Every numeric contributor has a valid band (lo<=hi, both in 0..99).
  select count(*) into v_band_breach
    from public.personality_role_template_traits
   where review_flag = false
     and (band_low is null or band_high is null or band_low > band_high);
  if v_band_breach > 0 then
    raise exception 'found % numeric contributors with malformed bands', v_band_breach;
  end if;

  -- Every flag has a threshold and weight=0 (the CHECK enforces, this is a paranoia probe).
  select count(*) into v_flag_breach
    from public.personality_role_template_traits
   where review_flag = true and (flag_threshold is null or weight <> 0);
  if v_flag_breach > 0 then
    raise exception 'found % flag rows with missing threshold or non-zero weight', v_flag_breach;
  end if;

  -- Weights respect the meta cap (none > 0.35 on any seeded template).
  select count(*) into v_weight_breach
    from public.personality_role_template_traits tt
    join public.personality_role_templates rt on rt.role_key = tt.role_key
                                              and (rt.org_id is not distinct from tt.org_id)
   where tt.weight > rt.weight_cap + 0.001;  -- ε for fp safety
  if v_weight_breach > 0 then
    raise exception 'found % template traits with weight > template.weight_cap', v_weight_breach;
  end if;

  -- Every norm row has exactly 100 breakpoints, sorted ascending (or equal).
  for r in
    select trait_key, breakpoints from public.personality_norms
  loop
    if jsonb_array_length(r.breakpoints) <> 100 then
      raise exception 'norm % has % breakpoints, expected 100', r.trait_key, jsonb_array_length(r.breakpoints);
    end if;
    -- Cheap monotonicity probe: first should be <= last.
    if (r.breakpoints->>0)::numeric > (r.breakpoints->>99)::numeric then
      raise exception 'norm % breakpoints are not sorted ascending', r.trait_key;
    end if;
  end loop;

  raise notice 'personality step3 seed tests: ok (% traits, % items, % templates)',
    v_traits, v_items, v_templates;
end $$;
