-- consent_grants — the consent ledger.
--
-- The data subject (`person_id`) owns their data. A grant authorizes a specific
-- org (`granted_to_org_id`) to use the person's profile data for a specific
-- `purpose`, with optional time bound (`expires_at`) and any structured scope
-- limits in `scope_json`. Revoking a grant flips RLS predicates via
-- consent_active(), so dependent rows disappear from non-admin view.

create type public.consent_purpose as enum (
  'hiring_decision',
  'profile_portability',
  'ongoing_management',
  'research_anonymized'
);
create type public.consent_legal_basis as enum ('consent','legitimate_interest','contract');
create type public.consent_status      as enum ('active','revoked','expired');

create table public.consent_grants (
  id                uuid primary key default extensions.gen_random_uuid(),
  person_id         uuid not null references public.people(id) on delete restrict,
  granted_to_org_id uuid not null references public.organizations(id) on delete restrict,
  purpose           public.consent_purpose not null,
  scope_json        jsonb not null default '{}'::jsonb
                      check (jsonb_typeof(scope_json) = 'object'),
  legal_basis       public.consent_legal_basis not null default 'consent',
  status            public.consent_status not null default 'active',
  granted_at        timestamptz not null default now(),
  revoked_at        timestamptz,
  expires_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- Status and revoked_at must agree.
  constraint chk_consent_revoked_dates check (
    (status = 'revoked' and revoked_at is not null) or
    (status <> 'revoked' and revoked_at is null)
  )
);

create index consent_grants_person_idx     on public.consent_grants (person_id);
create index consent_grants_granted_to_idx on public.consent_grants (granted_to_org_id);
create index consent_grants_active_partial on public.consent_grants (person_id, granted_to_org_id, purpose)
  where status = 'active';

create trigger trg_consent_grants_updated_at
  before update on public.consent_grants
  for each row execute function public.set_updated_at();

alter table public.consent_grants enable row level security;

comment on table public.consent_grants is
  'Consent ledger. The data subject (person_id) owns the data. Revoking flips RLS predicates via consent_active() so dependent rows disappear from view.';

-- ---- Forward FKs deferred from Step 2 -----------------------------------
alter table public.profiles
  add constraint profiles_consent_id_fkey
  foreign key (consent_id) references public.consent_grants(id) on delete restrict;

alter table public.placements
  add constraint placements_consent_id_fkey
  foreign key (consent_id) references public.consent_grants(id) on delete restrict;

-- ---- Replace consent_active() with the real body ------------------------
create or replace function public.consent_active(consent_grant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.consent_grants cg
    where cg.id          = consent_active.consent_grant_id
      and cg.status      = 'active'
      and cg.revoked_at is null
      and (cg.expires_at is null or cg.expires_at > now())
  );
$$;
comment on function public.consent_active(uuid) is
  'RLS helper: true iff the consent_grant is currently active (status active, not revoked, not expired).';
