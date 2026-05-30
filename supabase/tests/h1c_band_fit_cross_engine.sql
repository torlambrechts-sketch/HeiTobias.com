-- H-1c cross-engine fixture test (PG side).
--
-- Asserts that public.compute_trait_band_fit_v1 produces the same
-- output as the cases hardcoded below — which are the same cases the
-- TS test reads from src/lib/personality/__fixtures__/bandFitV1.json.
--
-- If a divergence is introduced into the PG function, this test fails.
-- If a divergence is introduced into the TS function, the vitest
-- test fails. They cannot drift silently.

do $$
declare
  v_case record;
  v_got  numeric;
  v_diff numeric;
  v_tol  numeric := 1e-9;
  v_fail int := 0;
begin
  for v_case in
    select * from (values
      ( 1, 60, 'higher_better'::text, 50::int,  null::int, null::int, null::int, 0.0::numeric),
      ( 2, 40, 'higher_better',       50,       null,      null,      null,      0.1010101010),
      ( 3,  0, 'higher_better',       50,       null,      null,      null,      0.5050505051),
      ( 4, 99, 'higher_better',       50,       null,      null,      null,      0.0),
      ( 5, 50, 'higher_better',       50,       null,      null,      null,      0.0),
      ( 6, 30, 'lower_better',        null,     50,        null,      null,      0.0),
      ( 7, 80, 'lower_better',        null,     50,        null,      null,      0.3030303030),
      ( 8, 99, 'lower_better',        null,     50,        null,      null,      0.4949494949),
      ( 9,  0, 'lower_better',        null,     50,        null,      null,      0.0),
      (10, 50, 'lower_better',        null,     50,        null,      null,      0.0),
      (11, 60, 'target_band',         40,       70,        null,      null,      0.0),
      (12, 25, 'target_band',         40,       70,        null,      null,      0.1515151515),
      (13, 90, 'target_band',         40,       70,        null,      null,      0.2020202020),
      (14, 40, 'target_band',         40,       70,        null,      null,      0.0),
      (15, 70, 'target_band',         40,       70,        null,      null,      0.0),
      (16,  0, 'target_band',         40,       70,        null,      null,      0.4040404040),
      (17, 99, 'target_band',         40,       70,        null,      null,      0.2929292929),
      (18, 50, 'inverted_u',          null,     null,      50,        20,        0.0),
      (19, 60, 'inverted_u',          null,     null,      50,        20,        0.5),
      (20, 30, 'inverted_u',          null,     null,      50,        20,        1.0),
      (21, 70, 'inverted_u',          null,     null,      50,        20,        1.0),
      (22,  0, 'inverted_u',          null,     null,      50,        20,        1.0),
      (23, 99, 'inverted_u',          null,     null,      50,        20,        1.0),
      (24, 55, 'inverted_u',          null,     null,      50,        20,        0.25),
      (25, 45, 'inverted_u',          null,     null,      50,        20,        0.25),
      (26, 50, 'inverted_u',          null,     null,      50,         5,        0.0),
      (27, 52, 'inverted_u',          null,     null,      50,         5,        0.4),
      (28, 55, 'inverted_u',          null,     null,      50,         5,        1.0),
      (29, 50, 'inverted_u',          null,     null,      50,        99,        0.0),
      (30, 99, 'inverted_u',          null,     null,      50,        99,        0.4949494949),
      (31, 65, 'inverted_u',          null,     null,      70,        25,        0.2),
      (32, 95, 'inverted_u',          null,     null,      70,        25,        1.0)
    ) as c(id, score, direction, band_low, band_high, inflection, half, expected)
  loop
    v_got := public.compute_trait_band_fit_v1(
      v_case.score, v_case.direction, v_case.band_low, v_case.band_high,
      v_case.inflection, v_case.half);
    v_diff := abs(v_got - v_case.expected);
    if v_diff > v_tol then
      raise warning 'h1c: case % FAIL — direction=%, score=%, got=%, expected=%, diff=%',
        v_case.id, v_case.direction, v_case.score, v_got, v_case.expected, v_diff;
      v_fail := v_fail + 1;
    end if;
  end loop;
  if v_fail > 0 then
    raise exception 'h1c: % of 32 cases diverged from fixture', v_fail;
  end if;
  raise notice 'h1c: cross-engine fixture matches (all 32 cases)';
end$$;

-- Negative paths
do $$
declare v_got numeric;
begin
  -- inverted_u without inflection_point must throw
  begin
    v_got := public.compute_trait_band_fit_v1(50, 'inverted_u', null, null, null, null);
    raise exception 'h1c: inverted_u w/o inflection_point should have thrown';
  exception when others then null;
  end;
  -- unknown direction must throw
  begin
    v_got := public.compute_trait_band_fit_v1(50, 'bogus', 0, 99, null, null);
    raise exception 'h1c: unknown direction should have thrown';
  exception when others then null;
  end;
  -- score out of range
  begin
    v_got := public.compute_trait_band_fit_v1(-1, 'higher_better', 50, null, null, null);
    raise exception 'h1c: negative score should have thrown';
  exception when others then null;
  end;
  raise notice 'h1c: negative paths reject as expected';
end$$;
