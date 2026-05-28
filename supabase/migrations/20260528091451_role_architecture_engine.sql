-- role_architecture_engine — Phase 1 Step 2.
--
-- Brings the Role Architecture Engine to life:
--   1) Seed 1 global competency framework (sample_engineering_v0) + 4 sample
--      role templates (sample_senior_backend_engineer, sample_engineering_lead,
--      sample_product_designer, sample_customer_success_manager). All keys
--      prefixed `sample_` so they're never mistaken for advisor-validated content.
--   2) RPC role_instantiate_from_template(template_id, org_id) — copies a
--      global role template's body into a new org-scoped roles_catalog row.
--
-- DEV STUB: every competency definition + template body is clearly labeled
-- "DEV STUB" in either the definition text or the body's note field. Real
-- frameworks and templates require I/O-validated content from the advisor.
-- See CLAUDE.md *Validated science & DEV STUBs* and PHASE1-SPEC §4.

-- ---- Global competency framework (sample) -------------------------------

insert into public.competency_frameworks (
  id, org_id, key, name, version, status, body_json
) values (
  'c2000000-0000-0000-0000-000000000001',
  null,
  'sample_engineering_v0',
  'Sample Engineering Competencies v0 (DEV STUB)',
  1,
  'active',
  '{
    "_dev_stub": true,
    "note": "DEV STUB — replace with advisor-validated competency framework.",
    "competencies": [
      {"key":"sample_systems_thinking",        "label":"Systems Thinking",        "family":"engineering", "definition":"DEV STUB — ability to reason about distributed systems and emergent behavior."},
      {"key":"sample_code_craft",              "label":"Code Craft",              "family":"engineering", "definition":"DEV STUB — clarity, correctness, and maintainability of code."},
      {"key":"sample_collaboration",           "label":"Collaboration",           "family":"soft_skills","definition":"DEV STUB — works effectively across functions."},
      {"key":"sample_pragmatism",              "label":"Pragmatism",              "family":"soft_skills","definition":"DEV STUB — picks the right trade-offs under constraint."},
      {"key":"sample_mentoring",               "label":"Mentoring",               "family":"soft_skills","definition":"DEV STUB — develops others."},
      {"key":"sample_strategic_communication", "label":"Strategic Communication", "family":"soft_skills","definition":"DEV STUB — articulates direction across audiences."},
      {"key":"sample_decision_making",         "label":"Decision Making",         "family":"soft_skills","definition":"DEV STUB — frames and resolves complex decisions."},
      {"key":"sample_user_empathy",            "label":"User Empathy",            "family":"product",    "definition":"DEV STUB — understands and prioritizes user needs."},
      {"key":"sample_craft",                   "label":"Craft",                   "family":"product",    "definition":"DEV STUB — produces high-quality design output."},
      {"key":"sample_storytelling",            "label":"Storytelling",            "family":"product",    "definition":"DEV STUB — narrates ideas effectively."}
    ]
  }'::jsonb
)
on conflict (id) do nothing;

-- ---- Sample role templates (kind='role') --------------------------------
-- Title + family carried in body_json (templates table has no first-class
-- name/family columns; the RPC reads them from body).

insert into public.templates (id, org_id, kind, key, version, status, body_json) values
  -- 1. Senior Backend Engineer
  ('c2100000-0000-0000-0000-000000000001', null, 'role', 'sample_senior_backend_engineer', 1, 'active',
   '{
      "_dev_stub": true,
      "note": "DEV STUB — replace with advisor-validated role profile.",
      "title": "Senior Backend Engineer",
      "family": "engineering",
      "competencies": [
        {"key":"sample_systems_thinking", "weight":0.30},
        {"key":"sample_code_craft",       "weight":0.25},
        {"key":"sample_collaboration",    "weight":0.20},
        {"key":"sample_pragmatism",       "weight":0.15},
        {"key":"sample_mentoring",        "weight":0.10}
      ],
      "trait_targets": [
        {"trait":"conscientiousness", "min":0.55, "max":0.90},
        {"trait":"openness",          "min":0.50, "max":0.85}
      ],
      "cognitive_demand": {"_dev_stub": true, "level": "high"},
      "context_factors":  null,
      "success_criteria": null,
      "evolution_vector": null
    }'::jsonb),

  -- 2. Engineering Lead
  ('c2100000-0000-0000-0000-000000000002', null, 'role', 'sample_engineering_lead', 1, 'active',
   '{
      "_dev_stub": true,
      "note": "DEV STUB — replace with advisor-validated role profile.",
      "title": "Engineering Lead",
      "family": "engineering",
      "competencies": [
        {"key":"sample_systems_thinking",        "weight":0.20},
        {"key":"sample_collaboration",           "weight":0.25},
        {"key":"sample_strategic_communication", "weight":0.20},
        {"key":"sample_mentoring",               "weight":0.20},
        {"key":"sample_decision_making",         "weight":0.15}
      ],
      "trait_targets": [
        {"trait":"extraversion",      "min":0.45, "max":0.85},
        {"trait":"conscientiousness", "min":0.60, "max":0.95}
      ],
      "cognitive_demand": {"_dev_stub": true, "level": "high"},
      "context_factors":  null,
      "success_criteria": null,
      "evolution_vector": null
    }'::jsonb),

  -- 3. Product Designer
  ('c2100000-0000-0000-0000-000000000003', null, 'role', 'sample_product_designer', 1, 'active',
   '{
      "_dev_stub": true,
      "note": "DEV STUB — replace with advisor-validated role profile.",
      "title": "Product Designer",
      "family": "product",
      "competencies": [
        {"key":"sample_user_empathy",     "weight":0.30},
        {"key":"sample_craft",            "weight":0.25},
        {"key":"sample_collaboration",    "weight":0.20},
        {"key":"sample_systems_thinking", "weight":0.15},
        {"key":"sample_storytelling",     "weight":0.10}
      ],
      "trait_targets": [
        {"trait":"openness",      "min":0.65, "max":0.95},
        {"trait":"agreeableness", "min":0.50, "max":0.85}
      ],
      "cognitive_demand": {"_dev_stub": true, "level": "medium"},
      "context_factors":  null,
      "success_criteria": null,
      "evolution_vector": null
    }'::jsonb),

  -- 4. Customer Success Manager
  ('c2100000-0000-0000-0000-000000000004', null, 'role', 'sample_customer_success_manager', 1, 'active',
   '{
      "_dev_stub": true,
      "note": "DEV STUB — replace with advisor-validated role profile.",
      "title": "Customer Success Manager",
      "family": "go_to_market",
      "competencies": [
        {"key":"sample_user_empathy",            "weight":0.25},
        {"key":"sample_strategic_communication", "weight":0.25},
        {"key":"sample_collaboration",           "weight":0.20},
        {"key":"sample_decision_making",         "weight":0.15},
        {"key":"sample_pragmatism",              "weight":0.15}
      ],
      "trait_targets": [
        {"trait":"extraversion",      "min":0.55, "max":0.90},
        {"trait":"agreeableness",     "min":0.60, "max":0.95},
        {"trait":"conscientiousness", "min":0.55, "max":0.90}
      ],
      "cognitive_demand": {"_dev_stub": true, "level": "medium"},
      "context_factors":  null,
      "success_criteria": null,
      "evolution_vector": null
    }'::jsonb)
on conflict (id) do nothing;

-- ---- role_instantiate_from_template RPC --------------------------------
-- Copies a GLOBAL role template into a new org-scoped roles_catalog row.
-- Tuning happens by direct UPDATE on the resulting row (RLS-gated by role.create);
-- signoff is a column write (status='active' + signed_off_by + signed_off_at);
-- new versions go through the existing role_version_create RPC.

create or replace function public.role_instantiate_from_template(
  p_template_id uuid,
  p_org_id      uuid
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller  uuid := (select auth.uid());
  v_tmpl    public.templates%rowtype;
  v_title   text;
  v_family  text;
  v_new_id  uuid;
begin
  -- Load template.
  select * into v_tmpl from public.templates where id = p_template_id;
  if not found then
    raise exception 'role_instantiate_from_template: template not found (id=%)', p_template_id;
  end if;
  if v_tmpl.kind <> 'role' then
    raise exception 'role_instantiate_from_template: template kind must be ''role'' (got %)', v_tmpl.kind;
  end if;
  if v_tmpl.org_id is not null then
    raise exception 'role_instantiate_from_template: template must be global (org_id IS NULL)';
  end if;

  -- AuthZ — only check when invoked from a user JWT. Service role bypasses.
  if v_caller is not null then
    if not public.has_permission(p_org_id, 'role.create') then
      raise exception 'role_instantiate_from_template: caller lacks role.create in target org';
    end if;
  end if;

  -- Extract title/family from body_json. Fall back to the template key.
  v_title  := coalesce(v_tmpl.body_json->>'title',  v_tmpl.key);
  v_family := v_tmpl.body_json->>'family';

  insert into public.roles_catalog (
    org_id, title, family,
    is_template, template_source_id,
    version, status,
    definition_json
  ) values (
    p_org_id, v_title, v_family,
    false, null,                       -- template_source_id refs roles_catalog templates; we sourced from public.templates instead
    1, 'draft',
    v_tmpl.body_json
  )
  returning id into v_new_id;

  return v_new_id;
end;
$$;

revoke execute on function public.role_instantiate_from_template(uuid, uuid) from public;
grant  execute on function public.role_instantiate_from_template(uuid, uuid) to authenticated, service_role;
comment on function public.role_instantiate_from_template(uuid, uuid) is
  'Instantiates a global public.templates(kind=role) row into a new org-scoped roles_catalog row as draft v1. Subsequent tuning via UPDATE; new versions via role_version_create.';
