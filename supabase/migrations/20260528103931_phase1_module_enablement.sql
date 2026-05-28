-- phase1_module_enablement — Phase 1 Step 7 (acceptance gap).
--
-- Phase 1 §7 acceptance: "All 5 modules registered + enabled per agency via
-- org_modules". phase1_module_registration registered them globally; this
-- migration ENABLES them for the seeded agency (Nordic Recruit) and the
-- seeded employer (FjordTech). Idempotent.
--
-- For each (org, module) the config_json starts empty; per-module behavior
-- (e.g. min_evaluators for team_definition) reads sensible defaults when
-- no config key is present.

do $$
declare
  v_org_id uuid;
  v_module_key text;
  v_phase1_modules constant text[] := array[
    'role_architecture',
    'team_definition',
    'assessment_engine',
    'fit_scoring',
    'candidate_experience'
  ];
begin
  for v_org_id in
    select id from public.organizations
    where id in (
      'a1000000-0000-0000-0000-000000000001'::uuid,  -- Nordic Recruit (agency)
      'a1000000-0000-0000-0000-000000000002'::uuid   -- FjordTech (employer)
    )
  loop
    foreach v_module_key in array v_phase1_modules
    loop
      insert into public.org_modules (org_id, module_key, enabled, config_json)
        values (v_org_id, v_module_key, true, '{}'::jsonb)
        on conflict (org_id, module_key) do update set enabled = true;
    end loop;
  end loop;
end$$;
