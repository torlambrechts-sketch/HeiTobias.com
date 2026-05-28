-- rbac_tables — the RBAC backbone.
--
--   rbac_permissions:       global definitions, no org_id.
--   rbac_roles:             org-scoped or system (org_id null) RBAC roles.
--   rbac_role_permissions:  many-to-many between roles and permissions.
--   membership_roles:       a membership holds one or more RBAC roles.
--
-- A BEFORE trigger on membership_roles enforces: if the role is org-scoped, its
-- org must match the membership's org. System roles (org_id null) attach to any org.

-- rbac_permissions ----------------------------------------------------------
create table public.rbac_permissions (
  id          uuid primary key default extensions.gen_random_uuid(),
  key         text not null unique,
  description text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_rbac_permissions_updated_at
  before update on public.rbac_permissions
  for each row execute function public.set_updated_at();
comment on table public.rbac_permissions is
  'Global permission definitions. key is the stable identifier RLS policies reference (e.g. profile.read).';

-- rbac_roles ----------------------------------------------------------------
create table public.rbac_roles (
  id         uuid primary key default extensions.gen_random_uuid(),
  org_id     uuid references public.organizations(id) on delete cascade,
  key        text not null,
  name       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, key)
);
-- UNIQUE treats multiple NULLs as distinct, so guard system role uniqueness with a partial index.
create unique index rbac_roles_system_unique
  on public.rbac_roles (key) where org_id is null;
create trigger trg_rbac_roles_updated_at
  before update on public.rbac_roles
  for each row execute function public.set_updated_at();
comment on table public.rbac_roles is
  'RBAC role. org_id null = system role (recruiter, manager, ...). Per-org roles can be defined on top.';

-- rbac_role_permissions -----------------------------------------------------
create table public.rbac_role_permissions (
  role_id       uuid not null references public.rbac_roles(id)       on delete cascade,
  permission_id uuid not null references public.rbac_permissions(id) on delete restrict,
  primary key (role_id, permission_id)
);
comment on table public.rbac_role_permissions is
  'Which permissions does each role hold.';

-- membership_roles ---------------------------------------------------------
create table public.membership_roles (
  membership_id uuid not null references public.memberships(id) on delete cascade,
  rbac_role_id  uuid not null references public.rbac_roles(id)  on delete restrict,
  created_at    timestamptz not null default now(),
  primary key (membership_id, rbac_role_id)
);

create or replace function public._check_membership_role_org_compatible()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  mem_org  uuid;
  role_org uuid;
begin
  select org_id into mem_org  from public.memberships where id = new.membership_id;
  select org_id into role_org from public.rbac_roles  where id = new.rbac_role_id;
  if mem_org is null then
    raise exception 'membership_roles.membership_id references missing row';
  end if;
  if role_org is not null and role_org <> mem_org then
    raise exception 'membership_roles.rbac_role_id must be a system role or match the membership''s org';
  end if;
  return new;
end;
$$;
create trigger trg_membership_roles_check_org
  before insert or update on public.membership_roles
  for each row execute function public._check_membership_role_org_compatible();

alter table public.rbac_permissions       enable row level security;
alter table public.rbac_roles             enable row level security;
alter table public.rbac_role_permissions  enable row level security;
alter table public.membership_roles       enable row level security;
