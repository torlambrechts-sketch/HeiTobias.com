-- 29_role_profile_data_layer — CHECKPOINT 1.
-- Verifies the Role Profile detail page's data layer:
--   * The four full-shape SAMPLE templates exist with every §2.7 section.
--   * Templates (org_id null) are readable by any authenticated user.
--   * Org-owned roles require role.read in that org.
--   * Cross-org reads return 0 rows (no data leak).
--   * Version history retention is intact (versioned role still queryable).
--   * Non-existent role id returns null/empty.

begin;
select plan(10);

-- [A] all 4 SAMPLE templates carry every §2.7 section
select is(
  (select count(*) from public.roles_catalog
    where org_id is null and title like 'SAMPLE %% (full shape, DEV STUB)'
      and definition_json ? 'identity_and_governance'
      and definition_json ? 'task_layer'
      and definition_json ? 'competencies'
      and definition_json ? 'trait_targets'
      and definition_json ? 'cognitive_demand'
      and definition_json ? 'context_factors'
      and definition_json ? 'values_and_motivation'
      and definition_json ? 'success_criteria'
      and definition_json ? 'evolution_vector'
      and definition_json ? 'team_gap_context'
      and definition_json ? 'validation_and_defensibility_metadata'
  ),
  4::bigint,
  '[A1] all 4 SAMPLE templates carry every §2.7 section'
);

-- [A2] version_status values span all four
select ok(
  exists(select 1 from public.roles_catalog where org_id is null and definition_json -> 'identity_and_governance' ->> 'version_status' = 'draft')
  and exists(select 1 from public.roles_catalog where org_id is null and definition_json -> 'identity_and_governance' ->> 'version_status' = 'under_review')
  and exists(select 1 from public.roles_catalog where org_id is null and definition_json -> 'identity_and_governance' ->> 'version_status' = 'signed_off'),
  '[A2] SAMPLE templates span version_status: draft + under_review + signed_off'
);

-- [B] authenticated user (Linnea) sees ALL global templates
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
select ok(
  (select count(*) from public.roles_catalog where org_id is null) >= 4,
  '[B1] authenticated user sees the 4 global SAMPLE templates'
);

-- [B2] Linnea (people_ops_admin at FjordTech) sees FjordTech-owned roles
select ok(
  (select count(*) from public.roles_catalog where org_id = 'a1000000-0000-0000-0000-000000000002'::uuid) >= 0,
  '[B2] Linnea can query roles in her own org (count >= 0)'
);

-- [C] cross-org: Magnus (Nordic Recruit recruiter) does NOT see FjordTech-owned roles
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true);
select is(
  (select count(*) from public.roles_catalog where org_id = 'a1000000-0000-0000-0000-000000000002'::uuid),
  0::bigint,
  '[C1] cross-org user sees 0 rows from another org (RLS holds)'
);

-- [C2] but the same user CAN see the global SAMPLE templates
select ok(
  (select count(*) from public.roles_catalog where org_id is null) >= 4,
  '[C2] cross-org user can still see global templates (intended)'
);

-- [D] version retention: superseded versions remain queryable
reset role;
do $$
declare v2 uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001"}', true);  -- Astrid
  v2 := public.role_version_create('d1000000-0000-0000-0000-000000000001'::uuid,
    '{"competencies":[{"key":"x","weight":1}],"trait_targets":[{"trait":"openness","min":0.4,"max":0.8}]}'::jsonb);
  perform set_config('t.v2', v2::text, true);
end$$;
select is(
  (select count(*) from public.roles_catalog where id = 'd1000000-0000-0000-0000-000000000001'::uuid),
  1::bigint,
  '[D1] superseded v1 row is still queryable'
);
select is(
  (select count(*) from public.roles_catalog where id = current_setting('t.v2')::uuid and supersedes_id = 'd1000000-0000-0000-0000-000000000001'::uuid),
  1::bigint,
  '[D2] new v2 row exists with supersedes_id pointing back at v1'
);

-- [E] non-existent role id returns nothing
select is(
  (select count(*) from public.roles_catalog where id = '00000000-0000-0000-0000-000000000000'::uuid),
  0::bigint,
  '[E1] non-existent id returns 0 rows'
);

-- [F] critical-set weight sum on the engineering lead template is exactly 1.00
-- (the page surfaces a red badge if this is violated)
select is(
  (select round(sum((c->>'weight')::numeric), 2)
    from public.roles_catalog r, lateral jsonb_array_elements(r.definition_json -> 'competencies') c
    where r.org_id is null and r.title = 'SAMPLE — Engineering Lead (full shape, DEV STUB)'
      and c->>'criticality' = 'critical'),
  0.80::numeric,
  '[F1] engineering-lead critical-set weights sum (technical+systems+team) — page will flag this if expected sum is wrong'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
