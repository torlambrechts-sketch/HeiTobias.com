-- 20260528070300_core_organizations_and_people
--
-- Phase 0 / Step 2.1 — the two foundational entities.
--   organizations: tenant root. Every other domain row carries org_id referencing this.
--   people:        global person identity. NOT org-scoped; per-org presence is expressed
--                  via memberships, positions, profiles. (Spec §2.2.)
--
-- RLS is enabled at the end with NO permissive policies, so default-deny holds from
-- the moment these tables exist. Policies arrive in Step 6.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.org_type    as enum ('agency', 'employer');
create type public.org_status  as enum ('active', 'suspended', 'archived');
-- Canonical region is 'eu' (PHASE0-SPEC §8). 'us'/'apac' present for dev override
-- and future regional expansion; production rows MUST be 'eu'.
create type public.data_region as enum ('eu', 'us', 'apac');

-- ---------------------------------------------------------------------------
-- updated_at helper — shared by every domain table
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
comment on function public.set_updated_at() is
  'Touches updated_at on UPDATE. Attached as a BEFORE UPDATE trigger to every domain table.';

-- ---------------------------------------------------------------------------
-- JSONB shape: organizations.settings_json
-- ---------------------------------------------------------------------------
-- Settings is an open dict (branding, locales, retention, module flags) — we
-- require it to be a JSON object so app code can safely path-read keys.

-- ---------------------------------------------------------------------------
-- organizations
-- ---------------------------------------------------------------------------

create table public.organizations (
  id              uuid primary key default extensions.gen_random_uuid(),
  name            text not null,
  type            public.org_type not null,
  country         text not null default 'NO'
                    check (char_length(country) = 2),  -- ISO 3166-1 alpha-2
  locale_default  text not null default 'nb-NO'
                    check (locale_default in ('nb-NO','sv-SE','da-DK','en')),
  data_region     public.data_region not null default 'eu',
  status          public.org_status not null default 'active',
  settings_json   jsonb not null default '{}'::jsonb
                    check (jsonb_typeof(settings_json) = 'object'),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create trigger trg_organizations_updated_at
  before update on public.organizations
  for each row execute function public.set_updated_at();

comment on table public.organizations is
  'Tenant root. type = agency | employer. Every other domain row carries org_id referencing this.';
comment on column public.organizations.data_region is
  'Canonical value is ''eu'' (PHASE0-SPEC §8). Non-eu values are DEV ONLY.';

-- ---------------------------------------------------------------------------
-- people
-- ---------------------------------------------------------------------------
-- Global identity. A single human (candidate / employee / manager / recruiter) is
-- one row here. Their per-org visibility comes from memberships + positions + profiles,
-- never by reading this table directly.
--
-- auth_user_id links to Supabase Auth ONLY when the person has a login (employees,
-- recruiters do; passive candidates may not yet).
--
-- primary_email uses citext so 'A@x' and 'a@x' collide on the unique index.

create table public.people (
  id                    uuid primary key default extensions.gen_random_uuid(),
  primary_email         extensions.citext not null,
  full_name             text not null,
  given_name            text,
  family_name           text,
  auth_user_id          uuid unique references auth.users(id) on delete set null,
  global_consent_state  text not null default 'unknown'
                          check (global_consent_state in ('unknown','granted','partial','revoked')),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz
);

create unique index people_primary_email_unique on public.people (primary_email);

create trigger trg_people_updated_at
  before update on public.people
  for each row execute function public.set_updated_at();

comment on table public.people is
  'Global person identity. candidate / employee / manager / recruiter are STATES, not separate tables.';
comment on column public.people.auth_user_id is
  'Nullable: not every person has a login (e.g. a sourced candidate). Links to auth.users when they do.';

-- ---------------------------------------------------------------------------
-- RLS default-deny
-- ---------------------------------------------------------------------------
-- Tables are unreadable to non-service callers until Step 6 attaches permissive
-- policies. This makes "tenant isolation by default" hold from row zero.

alter table public.organizations enable row level security;
alter table public.people        enable row level security;
