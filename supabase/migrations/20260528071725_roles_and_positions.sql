-- 20260528070500_roles_and_positions
--
-- Phase 0 / Step 2.3 — Role Profile (Entity A) and the role instance a person fills.
--
--   roles_catalog: VERSIONED (supersedes_id chain) and TEMPLATE-or-INSTANCE
--                  (is_template + template_source_id). role ≠ position ≠ job title.
--   positions:     an instance of a role a specific person fills, carrying reporting
--                  lines (manager_position_id self-ref).
--
-- Strict-from-day-one JSONB shape on definition_json: top level must be an object
-- and any recognised keys must be the right type. additionalProperties is allowed
-- so the advisor framework can extend the body without a migration.

create type public.role_status     as enum ('draft','active','archived');
create type public.position_status as enum ('open','filled','closed');

-- ---------------------------------------------------------------------------
-- roles_catalog
-- ---------------------------------------------------------------------------
-- definition_json carries: weighted competencies, trait target RANGES (not point
-- targets), cognitive demand, context factors, success criteria, evolution vector.
-- See PHASE0-SPEC §2.7. Template vs. instance is enforced by chk_role_template_or_instance.

create table public.roles_catalog (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid references public.organizations(id) on delete restrict,
  title               text not null,
  family              text,
  is_template         boolean not null default false,
  template_source_id  uuid references public.roles_catalog(id) on delete restrict,
  version             int  not null default 1 check (version >= 1),
  status              public.role_status not null default 'draft',
  definition_json     jsonb not null default '{}'::jsonb,
  authored_by_json    jsonb not null default '[]'::jsonb,
  signed_off_by       uuid references public.people(id) on delete set null,
  signed_off_at       timestamptz,
  supersedes_id       uuid references public.roles_catalog(id) on delete restrict,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- A row is either a global template (org_id null + is_template true) OR an
  -- org-scoped instance (org_id not null + is_template false). Nothing else.
  constraint chk_role_template_or_instance check (
    (is_template = true  and org_id is null) or
    (is_template = false and org_id is not null)
  ),

  -- definition_json: object with optional, typed keys. Forward-compatible.
  constraint chk_role_definition_shape check (
    extensions.jsonb_matches_schema(
      schema   := '{
        "type": "object",
        "properties": {
          "competencies":     {"type": "array"},
          "trait_targets":    {"type": "object"},
          "cognitive_demand": {"type": ["object","null"]},
          "context_factors":  {"type": ["object","array","null"]},
          "success_criteria": {"type": ["array","object","null"]},
          "evolution_vector": {"type": ["object","null"]}
        },
        "additionalProperties": true
      }'::json,
      instance := definition_json
    )
  ),

  -- authored_by_json: array of attribution records.
  constraint chk_role_authored_by_shape check (
    extensions.jsonb_matches_schema(
      schema   := '{"type": "array"}'::json,
      instance := authored_by_json
    )
  ),

  -- Versioning uniqueness within an org. Templates handled by the partial unique
  -- index below because UNIQUE treats two NULL org_ids as distinct.
  unique (org_id, title, version)
);

create unique index roles_catalog_template_unique
  on public.roles_catalog (title, version)
  where is_template = true;

create index roles_catalog_org_idx on public.roles_catalog (org_id) where org_id is not null;
create index roles_catalog_supersedes_idx on public.roles_catalog (supersedes_id);
create index roles_catalog_template_source_idx on public.roles_catalog (template_source_id);

create trigger trg_roles_catalog_updated_at
  before update on public.roles_catalog
  for each row execute function public.set_updated_at();

-- supersedes_id sanity: must point to an earlier version of the same kind/org.
create or replace function public._check_role_supersedes()
returns trigger language plpgsql as $$
declare prev record;
begin
  if new.supersedes_id is null then return new; end if;
  if new.supersedes_id = new.id then
    raise exception 'roles_catalog.supersedes_id cannot reference self';
  end if;
  select id, org_id, is_template, version, title
    into prev from public.roles_catalog where id = new.supersedes_id;
  if not found then
    raise exception 'roles_catalog.supersedes_id references missing row';
  end if;
  if prev.is_template <> new.is_template then
    raise exception 'roles_catalog.supersedes_id must reference same kind (template vs. instance)';
  end if;
  if prev.is_template = false and prev.org_id is distinct from new.org_id then
    raise exception 'roles_catalog.supersedes_id must reference a role in the same org';
  end if;
  if new.version <= prev.version then
    raise exception 'roles_catalog.version (%) must be greater than superseded version (%)', new.version, prev.version;
  end if;
  return new;
end;
$$;
create trigger trg_roles_catalog_check_supersedes
  before insert or update on public.roles_catalog
  for each row execute function public._check_role_supersedes();

-- template_source_id sanity: instance rows may point at a template they were copied from.
create or replace function public._check_role_template_source()
returns trigger language plpgsql as $$
declare src record;
begin
  if new.template_source_id is null then return new; end if;
  select is_template into src from public.roles_catalog where id = new.template_source_id;
  if not found then
    raise exception 'roles_catalog.template_source_id references missing row';
  end if;
  if src.is_template is not true then
    raise exception 'roles_catalog.template_source_id must reference a template (is_template = true)';
  end if;
  if new.is_template = true then
    raise exception 'a template cannot itself have a template_source_id';
  end if;
  return new;
end;
$$;
create trigger trg_roles_catalog_check_template_source
  before insert or update on public.roles_catalog
  for each row execute function public._check_role_template_source();

comment on table public.roles_catalog is
  'Role Profile (Entity A). VERSIONED via supersedes_id. TEMPLATE-or-INSTANCE via is_template + template_source_id. role ≠ position ≠ job title.';

-- ---------------------------------------------------------------------------
-- positions
-- ---------------------------------------------------------------------------

create table public.positions (
  id                   uuid primary key default extensions.gen_random_uuid(),
  org_id               uuid not null references public.organizations(id) on delete restrict,
  role_id              uuid not null references public.roles_catalog(id) on delete restrict,
  person_id            uuid references public.people(id) on delete set null,  -- nullable until filled
  team_id              uuid references public.teams(id)  on delete restrict,
  manager_position_id  uuid references public.positions(id) on delete set null,
  status               public.position_status not null default 'open',
  start_date           date,
  end_date             date,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint chk_position_dates check (end_date is null or start_date is null or end_date >= start_date),
  constraint chk_position_no_self_manager check (manager_position_id is null or manager_position_id <> id)
);
create index positions_org_idx     on public.positions (org_id);
create index positions_person_idx  on public.positions (person_id);
create index positions_role_idx    on public.positions (role_id);
create index positions_manager_idx on public.positions (manager_position_id);
create index positions_team_idx    on public.positions (team_id);

create trigger trg_positions_updated_at
  before update on public.positions
  for each row execute function public.set_updated_at();

-- A position must reference an org-scoped (non-template) role in the same org.
create or replace function public._check_position_role_org()
returns trigger language plpgsql as $$
declare r record;
begin
  select org_id, is_template into r from public.roles_catalog where id = new.role_id;
  if not found then
    raise exception 'positions.role_id references missing row';
  end if;
  if r.is_template = true then
    raise exception 'positions.role_id must reference a non-template role; instantiate the template first';
  end if;
  if r.org_id is distinct from new.org_id then
    raise exception 'positions.role_id must reference a role in the same org as positions.org_id';
  end if;
  return new;
end;
$$;
create trigger trg_positions_check_role_org
  before insert or update on public.positions
  for each row execute function public._check_position_role_org();

-- A manager_position_id must be in the same org.
create or replace function public._check_position_manager_org()
returns trigger language plpgsql as $$
declare mgr_org uuid;
begin
  if new.manager_position_id is null then return new; end if;
  select org_id into mgr_org from public.positions where id = new.manager_position_id;
  if mgr_org is null then
    raise exception 'positions.manager_position_id references missing row';
  end if;
  if mgr_org <> new.org_id then
    raise exception 'positions.manager_position_id must be in the same org';
  end if;
  return new;
end;
$$;
create trigger trg_positions_check_manager_org
  before insert or update on public.positions
  for each row execute function public._check_position_manager_org();

-- A position's team must be in the same org.
create or replace function public._check_position_team_org()
returns trigger language plpgsql as $$
declare team_org uuid;
begin
  if new.team_id is null then return new; end if;
  select org_id into team_org from public.teams where id = new.team_id;
  if team_org is null then
    raise exception 'positions.team_id references missing row';
  end if;
  if team_org <> new.org_id then
    raise exception 'positions.team_id must be in the same org as positions.org_id';
  end if;
  return new;
end;
$$;
create trigger trg_positions_check_team_org
  before insert or update on public.positions
  for each row execute function public._check_position_team_org();

comment on table public.positions is
  'A specific instance of a role a person fills inside an org. Reporting lines via manager_position_id self-ref.';

-- ---------------------------------------------------------------------------
-- RLS default-deny
-- ---------------------------------------------------------------------------

alter table public.roles_catalog enable row level security;
alter table public.positions     enable row level security;
