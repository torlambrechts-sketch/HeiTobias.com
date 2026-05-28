-- role_architecture_tables — Phase 1 capability: role architecture engine.
--
--   competency_frameworks      — global or org-scoped competency dictionaries.
--                                Versioned via supersedes_id.
--   roles_catalog.definition_json   tightened: trait targets are RANGES
--                                ([{trait, min, max}]), never single thresholds.
--   templates(kind='role').body_json  tightened to the same shape so role
--                                templates and their instances share one schema.
--
-- Phase 0 seed data is migrated in place before the constraint tightens.

-- ---- competency_frameworks --------------------------------------------------

create table public.competency_frameworks (
  id             uuid primary key default extensions.gen_random_uuid(),
  org_id         uuid references public.organizations(id) on delete cascade, -- null = global
  key            text not null,
  name           text not null,
  version        int  not null default 1 check (version >= 1),
  body_json      jsonb not null default '{"competencies":[]}'::jsonb,
  status         public.role_status not null default 'draft',
  supersedes_id  uuid references public.competency_frameworks(id) on delete restrict,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  unique (org_id, key, version),

  constraint chk_cf_body_shape check (
    extensions.jsonb_matches_schema(
      schema   := '{
        "type":"object",
        "required":["competencies"],
        "properties":{
          "competencies":{
            "type":"array",
            "items":{
              "type":"object",
              "required":["key","label"],
              "properties":{
                "key":   {"type":"string"},
                "label": {"type":"string"},
                "family":{"type":["string","null"]},
                "definition":{"type":["string","null"]}
              },
              "additionalProperties":true
            }
          }
        },
        "additionalProperties":true
      }'::json,
      instance := body_json
    )
  )
);

create unique index competency_frameworks_global_unique
  on public.competency_frameworks (key, version)
  where org_id is null;
create index competency_frameworks_org_idx
  on public.competency_frameworks (org_id) where org_id is not null;

create trigger trg_competency_frameworks_updated_at
  before update on public.competency_frameworks
  for each row execute function public.set_updated_at();
create trigger trg_audit_competency_frameworks
  after insert or update or delete on public.competency_frameworks
  for each row execute function public._audit_row();

alter table public.competency_frameworks enable row level security;

create policy competency_frameworks_select on public.competency_frameworks
  for select to authenticated
  using (org_id is null or public.has_permission(org_id, 'org.read'));
create policy competency_frameworks_insert on public.competency_frameworks
  for insert to authenticated
  with check (org_id is not null and public.has_permission(org_id, 'role.create'));
create policy competency_frameworks_update on public.competency_frameworks
  for update to authenticated
  using      (org_id is not null and public.has_permission(org_id, 'role.create'))
  with check (org_id is not null and public.has_permission(org_id, 'role.create'));

comment on table public.competency_frameworks is
  'Global or org-scoped competency dictionaries. Versioned via supersedes_id. Body shape validated by pg_jsonschema.';

-- ---- Tighten roles_catalog.definition_json shape ---------------------------
-- PHASE1-SPEC §2.1: trait targets are RANGES (min/max), never single thresholds.
-- Phase 0 seed used an older object shape ({"openness":[0.5,0.9]}); migrate it
-- in place before the new constraint goes on.

-- 1) Object-shaped trait_targets -> array of {trait, min, max}.
update public.roles_catalog
set definition_json = jsonb_set(
  definition_json,
  '{trait_targets}',
  coalesce(
    (select jsonb_agg(
       jsonb_build_object('trait', k, 'min', (v->>0)::numeric, 'max', (v->>1)::numeric))
     from jsonb_each(definition_json->'trait_targets') as kv(k, v)
     where jsonb_typeof(v) = 'array'),
    '[]'::jsonb
  ),
  true
)
where jsonb_typeof(definition_json) = 'object'
  and jsonb_typeof(definition_json->'trait_targets') = 'object';

-- 2) Ensure trait_targets is present (default to empty array) on any row missing it.
update public.roles_catalog
set definition_json = jsonb_set(definition_json, '{trait_targets}', '[]'::jsonb, true)
where jsonb_typeof(definition_json) = 'object'
  and not (definition_json ? 'trait_targets');

-- 3) Ensure competencies is present.
update public.roles_catalog
set definition_json = jsonb_set(definition_json, '{competencies}', '[]'::jsonb, true)
where jsonb_typeof(definition_json) = 'object'
  and not (definition_json ? 'competencies');

-- 4) Swap the constraint.
alter table public.roles_catalog drop constraint chk_role_definition_shape;

alter table public.roles_catalog add constraint chk_role_definition_shape check (
  extensions.jsonb_matches_schema(
    schema := '{
      "type":"object",
      "required":["competencies","trait_targets"],
      "properties":{
        "competencies":{
          "type":"array",
          "items":{
            "type":"object",
            "required":["key","weight"],
            "properties":{
              "key":   {"type":"string"},
              "weight":{"type":"number","minimum":0,"maximum":1}
            },
            "additionalProperties":true
          }
        },
        "trait_targets":{
          "type":"array",
          "items":{
            "type":"object",
            "required":["trait","min","max"],
            "properties":{
              "trait":{"type":"string"},
              "min":  {"type":"number"},
              "max":  {"type":"number"}
            },
            "additionalProperties":false
          }
        },
        "cognitive_demand":{"type":["object","null"]},
        "context_factors": {"type":["array","object","null"]},
        "success_criteria":{"type":["array","object","null"]},
        "evolution_vector":{"type":["object","null"]}
      },
      "additionalProperties":true
    }'::json,
    instance := definition_json
  )
);

-- ---- Tighten templates(kind='role').body_json --------------------------------
-- Replace the per-kind validator with one that enforces the new role shape;
-- other kinds (assessment / layout / notification / workflow) keep their
-- existing forward-compatible shapes.
create or replace function public._check_template_body_shape()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_schema json;
begin
  v_schema := case new.kind
    when 'role' then
      '{
        "type":"object",
        "required":["competencies","trait_targets"],
        "properties":{
          "competencies":{
            "type":"array",
            "items":{
              "type":"object",
              "required":["key","weight"],
              "properties":{
                "key":   {"type":"string"},
                "weight":{"type":"number","minimum":0,"maximum":1}
              },
              "additionalProperties":true
            }
          },
          "trait_targets":{
            "type":"array",
            "items":{
              "type":"object",
              "required":["trait","min","max"],
              "properties":{
                "trait":{"type":"string"},
                "min":  {"type":"number"},
                "max":  {"type":"number"}
              },
              "additionalProperties":false
            }
          },
          "cognitive_demand":{"type":["object","null"]},
          "context_factors": {"type":["array","object","null"]},
          "success_criteria":{"type":["array","object","null"]},
          "evolution_vector":{"type":["object","null"]}
        },
        "additionalProperties":true
      }'::json
    when 'assessment' then
      '{"type":"object","properties":{"instrument_key":{"type":"string"},"time_limit_minutes":{"type":["number","null"]},"sections":{"type":["array","null"]}},"additionalProperties":true}'::json
    when 'layout' then
      '{"type":"object","properties":{"slots":{"type":"array"}},"additionalProperties":true}'::json
    when 'notification' then
      '{"type":"object","properties":{"subject":{"type":"string"},"body":{"type":"string"},"channels":{"type":["array","null"]}},"additionalProperties":true}'::json
    when 'workflow' then
      '{"type":"object","properties":{"trigger":{"type":["string","object"]},"steps":{"type":"array"}},"additionalProperties":true}'::json
  end;

  if v_schema is null then return new; end if;
  if not extensions.jsonb_matches_schema(v_schema, new.body_json) then
    raise exception 'templates.body_json does not match the baseline shape for kind=%', new.kind;
  end if;
  return new;
end;
$$;
