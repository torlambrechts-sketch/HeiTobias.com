-- modularity_backbone — the four registries that let capabilities be enabled
-- per org WITHOUT core schema changes.
--
--   modules            — global catalog of capabilities.
--   org_modules        — per-org enable + config; config validated against
--                        the module's config_schema_json (cross-row check).
--   templates          — global or org-scoped data templates for the five kinds:
--                        role, assessment, layout, notification, workflow.
--                        body_json is shape-checked per kind (pg_jsonschema).
--   component_registry — global UI component registry; layouts (a template kind)
--                        reference component keys.
--
-- All four tables get RLS default-deny, _audit_row, and updated_at triggers.

create type public.module_status   as enum ('alpha','beta','stable','deprecated');
create type public.template_kind   as enum ('role','assessment','layout','notification','workflow');
create type public.template_status as enum ('draft','active','archived');
create type public.component_kind  as enum ('atom','molecule','organism','layout','section');

-- ---- modules -------------------------------------------------------------
create table public.modules (
  id                 uuid primary key default extensions.gen_random_uuid(),
  key                text not null unique,
  name               text not null,
  version            text not null default '0.1.0',
  status             public.module_status not null default 'beta',
  config_schema_json jsonb not null default '{}'::jsonb
                       check (jsonb_typeof(config_schema_json) = 'object'),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create trigger trg_modules_updated_at
  before update on public.modules
  for each row execute function public.set_updated_at();
comment on table public.modules is
  'Global catalog of capabilities. Adding a row here makes a capability available; flipping it on per org happens in org_modules.';

-- ---- org_modules --------------------------------------------------------
create table public.org_modules (
  id          uuid primary key default extensions.gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  module_key  text not null references public.modules(key) on update cascade on delete restrict,
  enabled     boolean not null default true,
  config_json jsonb   not null default '{}'::jsonb
                check (jsonb_typeof(config_json) = 'object'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (org_id, module_key)
);
create index org_modules_org_idx on public.org_modules (org_id);
create trigger trg_org_modules_updated_at
  before update on public.org_modules
  for each row execute function public.set_updated_at();

-- Cross-row validation: org_modules.config_json must validate against the linked
-- module's config_schema_json. Empty schema ('{}') skips validation.
create or replace function public._check_org_module_config_shape()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_schema jsonb;
begin
  select config_schema_json into v_schema
    from public.modules
    where key = new.module_key;

  if v_schema is null then
    raise exception 'org_modules.module_key references missing module: %', new.module_key;
  end if;
  -- '{}' means "no schema constraint".
  if v_schema = '{}'::jsonb then
    return new;
  end if;
  if not extensions.jsonb_matches_schema(v_schema::text::json, new.config_json) then
    raise exception 'org_modules.config_json does not match modules.config_schema_json for module key=%', new.module_key;
  end if;
  return new;
end;
$$;
create trigger trg_org_modules_check_config
  before insert or update on public.org_modules
  for each row execute function public._check_org_module_config_shape();

comment on table public.org_modules is
  'Per-org enable/config for a module. config_json is validated against modules.config_schema_json.';

-- ---- templates ----------------------------------------------------------
create table public.templates (
  id                 uuid primary key default extensions.gen_random_uuid(),
  org_id             uuid references public.organizations(id) on delete cascade,
  kind               public.template_kind not null,
  key                text not null,
  version            int  not null default 1 check (version >= 1),
  body_json          jsonb not null default '{}'::jsonb
                       check (jsonb_typeof(body_json) = 'object'),
  status             public.template_status not null default 'draft',
  template_source_id uuid references public.templates(id) on delete restrict,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (org_id, kind, key, version)
);
-- Globals: org_id IS NULL. Partial unique index guards uniqueness across globals.
create unique index templates_global_unique
  on public.templates (kind, key, version)
  where org_id is null;
create index templates_kind_idx   on public.templates (kind);
create index templates_org_idx    on public.templates (org_id) where org_id is not null;
create index templates_source_idx on public.templates (template_source_id);

create trigger trg_templates_updated_at
  before update on public.templates
  for each row execute function public.set_updated_at();

-- Per-kind body_json shape validation (pg_jsonschema). Baseline shapes are
-- forward-compatible (additionalProperties: true); Phase 1+ can tighten.
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
      '{"type":"object",
        "properties":{
          "competencies":     {"type":"array"},
          "trait_targets":    {"type":"object"},
          "cognitive_demand": {"type":["object","null"]},
          "context_factors":  {"type":["object","array","null"]},
          "success_criteria": {"type":["array","object","null"]},
          "evolution_vector": {"type":["object","null"]}
        },
        "additionalProperties":true}'::json
    when 'assessment' then
      '{"type":"object",
        "properties":{
          "instrument_key":      {"type":"string"},
          "time_limit_minutes":  {"type":["number","null"]},
          "sections":            {"type":["array","null"]}
        },
        "additionalProperties":true}'::json
    when 'layout' then
      '{"type":"object",
        "properties":{
          "slots": {"type":"array"}
        },
        "additionalProperties":true}'::json
    when 'notification' then
      '{"type":"object",
        "properties":{
          "subject":  {"type":"string"},
          "body":     {"type":"string"},
          "channels": {"type":["array","null"]}
        },
        "additionalProperties":true}'::json
    when 'workflow' then
      '{"type":"object",
        "properties":{
          "trigger": {"type":["string","object"]},
          "steps":   {"type":"array"}
        },
        "additionalProperties":true}'::json
  end;

  if v_schema is null then return new; end if;
  if not extensions.jsonb_matches_schema(v_schema, new.body_json) then
    raise exception 'templates.body_json does not match the baseline shape for kind=%', new.kind;
  end if;
  return new;
end;
$$;
create trigger trg_templates_check_body
  before insert or update on public.templates
  for each row execute function public._check_template_body_shape();

-- A template instance's source must be a global template (org_id IS NULL).
create or replace function public._check_template_source()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  src record;
begin
  if new.template_source_id is null then return new; end if;
  if new.template_source_id = new.id then
    raise exception 'templates.template_source_id cannot reference self';
  end if;
  select id, org_id, kind into src from public.templates where id = new.template_source_id;
  if not found then
    raise exception 'templates.template_source_id references missing row';
  end if;
  if src.org_id is not null then
    raise exception 'templates.template_source_id must point to a global template (org_id IS NULL)';
  end if;
  if src.kind <> new.kind then
    raise exception 'templates.template_source_id must point to a template of the same kind';
  end if;
  return new;
end;
$$;
create trigger trg_templates_check_source
  before insert or update on public.templates
  for each row execute function public._check_template_source();

comment on table public.templates is
  'Global (org_id IS NULL) or org-scoped data templates. body_json shape is validated per kind via pg_jsonschema.';

-- ---- component_registry --------------------------------------------------
create table public.component_registry (
  id          uuid primary key default extensions.gen_random_uuid(),
  key         text not null unique,
  kind        public.component_kind not null,
  schema_json jsonb not null default '{}'::jsonb
                check (jsonb_typeof(schema_json) = 'object'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index component_registry_kind_idx on public.component_registry (kind);
create trigger trg_component_registry_updated_at
  before update on public.component_registry
  for each row execute function public.set_updated_at();

comment on table public.component_registry is
  'Global UI/layout component registry. Layout templates (templates.kind = layout) reference components by key.';

-- ---- RLS default-deny ---------------------------------------------------
alter table public.modules            enable row level security;
alter table public.org_modules        enable row level security;
alter table public.templates          enable row level security;
alter table public.component_registry enable row level security;

-- ---- Audit triggers on the 4 new tables ---------------------------------
create trigger trg_audit_modules            after insert or update or delete on public.modules            for each row execute function public._audit_row();
create trigger trg_audit_org_modules        after insert or update or delete on public.org_modules        for each row execute function public._audit_row();
create trigger trg_audit_templates          after insert or update or delete on public.templates          for each row execute function public._audit_row();
create trigger trg_audit_component_registry after insert or update or delete on public.component_registry for each row execute function public._audit_row();
