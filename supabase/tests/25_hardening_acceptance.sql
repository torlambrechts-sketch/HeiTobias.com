-- 25_hardening_acceptance — verifies the corrective migrations from
-- the Phase 0 Hardening + Workspace Admin prompt + audit findings F-1
-- through F-4 and P-2/P-3/P-4/P-5.

begin;
select plan(13);

-- [A1] F-3 fixed: every domain table (except audit_log) has trg_audit_*.
select is(
  (select count(*) from information_schema.tables t
    where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
      and t.table_name <> 'audit_log'
      and not exists (select 1 from pg_trigger tr
        join pg_class c on c.oid = tr.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relname = t.table_name and tr.tgname like 'trg_audit_%')),
  0::bigint, '[A1] F-3 fixed: every domain table has trg_audit_*'
);

-- [B1] F-1 fixed: trait_target with direction=optimum but no band is rejected.
select throws_ok(
  $$insert into public.roles_catalog (org_id, title, is_template, status, version, definition_json)
    values ('a1000000-0000-0000-0000-000000000001'::uuid, 'BadOptimum_'||gen_random_uuid()::text, false, 'draft', 1,
      '{"competencies":[{"key":"x","weight":1}],"trait_targets":[{"trait":"openness","direction":"optimum","centre":0.5}]}'::jsonb)$$,
  'P0001', NULL::text,
  '[B1] F-1: direction=optimum without centre+lower+upper band is REJECTED at the DB'
);

-- [B2] direction=maximum_threshold without justification is rejected.
select throws_ok(
  $$insert into public.roles_catalog (org_id, title, is_template, status, version, definition_json)
    values ('a1000000-0000-0000-0000-000000000001'::uuid, 'BadMax_'||gen_random_uuid()::text, false, 'draft', 1,
      '{"competencies":[{"key":"x","weight":1}],"trait_targets":[{"trait":"emotional_stability","direction":"maximum_threshold"}]}'::jsonb)$$,
  'P0001', NULL::text,
  '[B2] F-1: direction=maximum_threshold without justification is REJECTED'
);

-- [B3] Legacy {trait,min,max} shape still passes (back-compat).
do $$
declare new_id uuid;
begin
  insert into public.roles_catalog (org_id, title, is_template, status, version, definition_json)
    values ('a1000000-0000-0000-0000-000000000001'::uuid, 'LegacyShape_'||gen_random_uuid()::text, false, 'draft', 1,
      '{"competencies":[{"key":"x","weight":1}],"trait_targets":[{"trait":"openness","min":0.4,"max":0.8}]}'::jsonb)
    returning id into new_id;
  perform set_config('t.legacy_role', new_id::text, true);
end$$;
select isnt(current_setting('t.legacy_role',true), '', '[B3] F-1: legacy {trait,min,max} shape still inserts (backward compat)');

-- [B4] Valid band shape inserts.
do $$
declare new_id uuid;
begin
  insert into public.roles_catalog (org_id, title, is_template, status, version, definition_json)
    values ('a1000000-0000-0000-0000-000000000001'::uuid, 'BandShape_'||gen_random_uuid()::text, false, 'draft', 1,
      '{"competencies":[{"key":"x","weight":1}],"trait_targets":[{"trait":"conscientiousness","direction":"optimum","centre":0.7,"lower":0.55,"upper":0.85,"justification":"sample band for hardening test"}]}'::jsonb)
    returning id into new_id;
  perform set_config('t.band_role', new_id::text, true);
end$$;
select isnt(current_setting('t.band_role',true), '', '[B4] F-1: valid band shape (direction=optimum with centre+lower+upper) inserts');

-- [C1] F-2 fixed: organizations data_region must be eu.
select throws_ok(
  $$insert into public.organizations (name, type, data_region) values ('NonEU_'||gen_random_uuid()::text, 'employer', 'us')$$,
  '23514', NULL::text,
  '[C1] F-2: cannot insert organization with data_region <> eu'
);
select is(
  (select count(*) from public.organizations where data_region <> 'eu'), 0::bigint,
  '[C2] F-2: zero organizations with non-eu data_region'
);

-- [D1] F-4 fixed: dismissal beats legal.
select is(
  public._infer_guidance_refusal('{"topic":"Do I have legal grounds to dismiss?"}'::jsonb)::text,
  'dismissal',
  '[D1] F-4: dismiss+legal text refuses as dismissal (the consequential action wins)'
);

-- [E1] P-2 fixed: Insights Discovery / 9-box / colours model refused.
select throws_ok(
  $$insert into public.assessment_instruments (key, name, validity_status) values ('insights_discovery_'||gen_random_uuid()::text, 'Insights Discovery', 'dev_stub')$$,
  '23514', NULL::text,
  '[E1] P-2: Insights Discovery refused by deny-list'
);
select throws_ok(
  $$insert into public.assessment_instruments (key, name, validity_status) values ('nine_box_auto_'||gen_random_uuid()::text, '9-box auto-rated potential', 'dev_stub')$$,
  '23514', NULL::text,
  '[E2] P-2: 9-box auto refused by deny-list'
);

-- [F1] P-3 fixed: every RLS-enabled table (except audit_log) is FORCE.
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relkind='r' and c.relrowsecurity=true and c.relforcerowsecurity=false
     and c.relname <> 'audit_log'),
  0::bigint, '[F1] P-3: all RLS-enabled tables (except audit_log) are FORCE RLS'
);

-- [G1] P-4/P-5 fixed: no policies with bare using(true) targeting public role.
select is(
  (select count(*) from pg_policies p
   where p.schemaname='public' and p.qual='true' and 'public' = any(p.roles)),
  0::bigint, '[G1] P-4/P-5: no using(true) policies addressing the public role'
);

-- [H1] A5: profiles append-only — UPDATE to a content field is rejected.
do $$
declare p_id uuid; cand uuid;
begin
  insert into public.people (full_name, primary_email) values ('Append Test','app_'||gen_random_uuid()||'@h.t') returning id into cand;
  insert into public.profiles (org_id, person_id, source, traits_json, valid_from, consent_id)
    values ('a1000000-0000-0000-0000-000000000002'::uuid, cand, 'assessment', '{"openness":0.5}'::jsonb, now(), null)
    returning id into p_id;
  perform set_config('t.prof', p_id::text, true);
end$$;
select throws_ok(
  $$update public.profiles set traits_json = '{"openness":0.9}'::jsonb where id = current_setting('t.prof')::uuid$$,
  'P0001', NULL::text,
  '[H1] A5: profiles is append-only — UPDATE of traits_json rejected'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
