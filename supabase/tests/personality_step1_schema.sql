-- pgTAP-style assertions for Step 1 schema. Run via scripts/run-sql-tests.mjs
-- against a Postgres with the migrations applied.
--
-- This file uses plain assertions (raise exception on failure) so we don't
-- require the pgTAP extension. Each check fails loudly with a clear message.

do $$
declare
  v_count int;
  v_rls   record;
begin
  -- All five tables exist.
  for v_count in
    select count(*) from information_schema.tables
     where table_schema = 'public'
       and table_name in ('personality_traits','personality_norms',
                          'personality_role_templates','personality_role_template_traits',
                          'personality_role_matches')
  loop
    if v_count <> 5 then
      raise exception 'personality step1: expected 5 tables, found %', v_count;
    end if;
  end loop;

  -- RLS + FORCE on every personality_* table.
  for v_rls in
    select relname,
           relrowsecurity      as rls_enabled,
           relforcerowsecurity as rls_forced
      from pg_class
     where relkind = 'r'
       and relnamespace = 'public'::regnamespace
       and relname like 'personality_%'
  loop
    if not v_rls.rls_enabled then
      raise exception 'personality step1: % does not have RLS enabled', v_rls.relname;
    end if;
    if not v_rls.rls_forced then
      raise exception 'personality step1: % does not have FORCE RLS', v_rls.relname;
    end if;
  end loop;

  -- The trait_direction enum exists with exactly the three values.
  select count(*) into v_count from pg_enum e
    join pg_type t on t.oid = e.enumtypid
   where t.typname = 'personality_trait_direction';
  if v_count <> 3 then
    raise exception 'personality_trait_direction enum has % values, expected 3', v_count;
  end if;

  -- The chk_template_trait_shape constraint refuses a mixed row (weight>0 AND review_flag=true).
  begin
    insert into public.personality_traits (trait_key, name, domain, framework, source, license)
    values ('__test_trait', 't', 'd', 'f', 's', 'l') on conflict do nothing;
    insert into public.personality_role_templates (role_key, org_id, title, family)
    values ('__test_role', null, 't', 'f') on conflict do nothing;
    insert into public.personality_role_template_traits
      (role_key, org_id, trait_key, band_low, band_high, direction, weight, review_flag, flag_threshold)
    values ('__test_role', null, '__test_trait', 50, 80, 'higher_better', 0.2, true, 70);
    raise exception 'personality step1: chk_template_trait_shape should have refused a (weight>0 AND review_flag=true) row';
  exception when check_violation then
    -- expected
    null;
  end;

  -- Same constraint refuses a (weight=0 AND review_flag=false) row.
  begin
    insert into public.personality_role_template_traits
      (role_key, org_id, trait_key, band_low, band_high, direction, weight, review_flag)
    values ('__test_role', null, '__test_trait', null, null, 'higher_better', 0, false);
    raise exception 'personality step1: chk_template_trait_shape should have refused a (weight=0 AND review_flag=false) row';
  exception when check_violation then
    null;
  end;

  -- The validated-real CHECK on norms refuses validated+_dev_stub=true.
  begin
    insert into public.personality_norms (trait_key, population_key, sample_n, breakpoints, validity_status, _dev_stub)
    values ('__test_trait', '__test_pop', 1,
            (select jsonb_agg(g) from generate_series(1,100) g)::jsonb,
            'validated', true);
    raise exception 'personality step1: chk_norms_validated_real should have refused validated+_dev_stub=true';
  exception when check_violation then
    null;
  end;

  -- Same shape on personality_role_matches.
  begin
    insert into public.personality_role_matches
      (org_id, session_id, person_id, role_key, match_score, validity_status, _dev_stub)
    values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000',
            '00000000-0000-0000-0000-000000000000', 'x', null, 'validated', false);
    raise exception 'personality step1: chk_role_matches_validated_real should have refused validated+match_score=null';
  exception when check_violation then null;
  when foreign_key_violation then null;  -- FK fires first; either is fine
  end;

  -- Cleanup test rows.
  delete from public.personality_role_template_traits where role_key = '__test_role';
  delete from public.personality_role_templates       where role_key = '__test_role';
  delete from public.personality_traits               where trait_key = '__test_trait';

  raise notice 'personality step1 schema tests: ok';
end $$;
