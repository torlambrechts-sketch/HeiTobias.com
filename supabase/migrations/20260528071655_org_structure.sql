-- 20260528070400_org_structure
--
-- Phase 0 / Step 2.2 — how people belong to and are organized within an org.
--   memberships:  person ↔ org link with status. RBAC roles attach in Step 3 (membership_roles).
--   departments:  self-tree under an org.
--   teams:        attached to an optional department; the unit the team-composition
--                 engine operates on (Phase 1+).
--   team_members: person ↔ team within an org.
--
-- Cross-row sanity (a team's department lives in the team's org; a team_member is in the
-- same org as the team) is enforced by trigger functions so it survives RLS bypass.

create type public.membership_status as enum ('invited','active','suspended','removed');

-- ---------------------------------------------------------------------------
-- memberships
-- ---------------------------------------------------------------------------

create table public.memberships (
  id          uuid primary key default extensions.gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete restrict,
  person_id   uuid not null references public.people(id)        on delete restrict,
  status      public.membership_status not null default 'invited',
  joined_at   timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (org_id, person_id)
);
create index memberships_person_id_idx on public.memberships (person_id);
create index memberships_org_id_idx    on public.memberships (org_id);

create trigger trg_memberships_updated_at
  before update on public.memberships
  for each row execute function public.set_updated_at();

comment on table public.memberships is
  'Connects a person to an org. A person can hold memberships in multiple orgs (agency recruiter, later employer employee).';

-- ---------------------------------------------------------------------------
-- departments — self-tree
-- ---------------------------------------------------------------------------

create table public.departments (
  id                    uuid primary key default extensions.gen_random_uuid(),
  org_id                uuid not null references public.organizations(id) on delete restrict,
  name                  text not null,
  parent_department_id  uuid references public.departments(id) on delete restrict,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint chk_dept_no_self_parent check (parent_department_id is null or parent_department_id <> id)
);
create index departments_org_id_idx on public.departments (org_id);
create index departments_parent_idx on public.departments (parent_department_id);

create trigger trg_departments_updated_at
  before update on public.departments
  for each row execute function public.set_updated_at();

-- A department's parent must live in the same org.
create or replace function public._check_dept_parent_same_org()
returns trigger language plpgsql as $$
declare parent_org uuid;
begin
  if new.parent_department_id is null then return new; end if;
  select org_id into parent_org from public.departments where id = new.parent_department_id;
  if parent_org is null then
    raise exception 'departments.parent_department_id references missing row';
  end if;
  if parent_org <> new.org_id then
    raise exception 'departments.parent_department_id must be in the same org as departments.org_id';
  end if;
  return new;
end;
$$;
create trigger trg_departments_check_parent_org
  before insert or update on public.departments
  for each row execute function public._check_dept_parent_same_org();

-- ---------------------------------------------------------------------------
-- teams
-- ---------------------------------------------------------------------------

create table public.teams (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete restrict,
  department_id   uuid references public.departments(id) on delete restrict,
  name            text not null,
  lead_person_id  uuid references public.people(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index teams_org_id_idx on public.teams (org_id);
create index teams_department_id_idx on public.teams (department_id);

create trigger trg_teams_updated_at
  before update on public.teams
  for each row execute function public.set_updated_at();

create or replace function public._check_team_dept_same_org()
returns trigger language plpgsql as $$
declare dept_org uuid;
begin
  if new.department_id is null then return new; end if;
  select org_id into dept_org from public.departments where id = new.department_id;
  if dept_org is null then
    raise exception 'teams.department_id references missing row';
  end if;
  if dept_org <> new.org_id then
    raise exception 'teams.department_id must be in the same org as teams.org_id';
  end if;
  return new;
end;
$$;
create trigger trg_teams_check_dept_org
  before insert or update on public.teams
  for each row execute function public._check_team_dept_same_org();

-- ---------------------------------------------------------------------------
-- team_members
-- ---------------------------------------------------------------------------

create table public.team_members (
  id            uuid primary key default extensions.gen_random_uuid(),
  org_id        uuid not null references public.organizations(id) on delete restrict,
  team_id       uuid not null references public.teams(id)         on delete cascade,
  person_id     uuid not null references public.people(id)        on delete restrict,
  role_in_team  text,
  is_lead       boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (team_id, person_id)
);
create index team_members_person_id_idx on public.team_members (person_id);

create trigger trg_team_members_updated_at
  before update on public.team_members
  for each row execute function public.set_updated_at();

create or replace function public._check_team_member_same_org()
returns trigger language plpgsql as $$
declare team_org uuid;
begin
  select org_id into team_org from public.teams where id = new.team_id;
  if team_org is null then
    raise exception 'team_members.team_id references missing row';
  end if;
  if team_org <> new.org_id then
    raise exception 'team_members.team_id must be in the same org as team_members.org_id';
  end if;
  return new;
end;
$$;
create trigger trg_team_members_check_org
  before insert or update on public.team_members
  for each row execute function public._check_team_member_same_org();

-- ---------------------------------------------------------------------------
-- RLS default-deny
-- ---------------------------------------------------------------------------

alter table public.memberships  enable row level security;
alter table public.departments  enable row level security;
alter table public.teams        enable row level security;
alter table public.team_members enable row level security;
