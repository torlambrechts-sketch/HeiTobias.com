-- 20260528070600_profiles_and_assessments
--
-- Phase 0 / Step 2.4 — Person Profile (Entity B) and the assessment instances that produce it.
--
--   profiles:    person profile, time-versioned (valid_from / valid_to) for the re-fit
--                time series, consent-scoped (consent_id, FK added in Step 4).
--   assessments: assessment instances that yield a profile.
--
-- Note: profiles.consent_id is declared here without a FK; Step 4 adds the FK once
--       consent_grants exists. This keeps the migrations forward-only and small.

create type public.profile_source    as enum ('assessment','refit','import');
create type public.assessment_type   as enum ('cognitive','personality','values','composite');
create type public.assessment_status as enum ('invited','in_progress','completed','expired');

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
-- Each row is a snapshot valid in [valid_from, valid_to). A null valid_to means
-- "currently valid" — there should be at most one such row per (person_id, org_id, source);
-- not enforced as a constraint here because re-fit superseding is a Phase 1 workflow.

create table public.profiles (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete restrict,
  person_id       uuid not null references public.people(id)        on delete restrict,
  source          public.profile_source not null,
  traits_json     jsonb not null default '{}'::jsonb,
  cognitive_json  jsonb not null default '{}'::jsonb,
  values_json     jsonb not null default '{}'::jsonb,
  derived_json    jsonb not null default '{}'::jsonb,
  consent_id      uuid,  -- FK added in Step 4 (consent_grants migration)
  valid_from      timestamptz not null default now(),
  valid_to        timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,

  constraint chk_profile_valid_window check (valid_to is null or valid_to > valid_from),

  -- All JSONB columns must be objects so app code can safely path-read.
  constraint chk_profile_traits_object    check (jsonb_typeof(traits_json)    = 'object'),
  constraint chk_profile_cognitive_object check (jsonb_typeof(cognitive_json) = 'object'),
  constraint chk_profile_values_object    check (jsonb_typeof(values_json)    = 'object'),
  constraint chk_profile_derived_object   check (jsonb_typeof(derived_json)   = 'object')
);
create index profiles_person_idx        on public.profiles (person_id);
create index profiles_org_idx           on public.profiles (org_id);
create index profiles_person_valid_idx  on public.profiles (person_id, valid_from desc);
create index profiles_consent_idx       on public.profiles (consent_id);

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

comment on table public.profiles is
  'Person Profile (Entity B). Time-versioned via valid_from/valid_to (re-fit time series). Consent-scoped via consent_id.';
comment on column public.profiles.consent_id is
  'FK to consent_grants added in migration 20260528070800. RLS in Step 6 requires consent_active(consent_id).';

-- ---------------------------------------------------------------------------
-- assessments
-- ---------------------------------------------------------------------------

create table public.assessments (
  id                    uuid primary key default extensions.gen_random_uuid(),
  org_id                uuid not null references public.organizations(id) on delete restrict,
  person_id             uuid not null references public.people(id)        on delete restrict,
  type                  public.assessment_type not null,
  instrument_key        text not null,
  status                public.assessment_status not null default 'invited',
  validity_flags_json   jsonb not null default '{}'::jsonb
                          check (jsonb_typeof(validity_flags_json) = 'object'),
  result_profile_id     uuid references public.profiles(id) on delete set null,
  completed_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index assessments_person_idx on public.assessments (person_id);
create index assessments_org_idx    on public.assessments (org_id);

create trigger trg_assessments_updated_at
  before update on public.assessments
  for each row execute function public.set_updated_at();

-- If a profile is attached, it must belong to the same person and org.
create or replace function public._check_assessment_result_profile()
returns trigger language plpgsql as $$
declare p record;
begin
  if new.result_profile_id is null then return new; end if;
  select person_id, org_id into p from public.profiles where id = new.result_profile_id;
  if p is null then
    raise exception 'assessments.result_profile_id references missing row';
  end if;
  if p.person_id <> new.person_id or p.org_id <> new.org_id then
    raise exception 'assessments.result_profile_id must point at a profile of the same person + org';
  end if;
  return new;
end;
$$;
create trigger trg_assessments_check_result
  before insert or update on public.assessments
  for each row execute function public._check_assessment_result_profile();

-- ---------------------------------------------------------------------------
-- RLS default-deny
-- ---------------------------------------------------------------------------

alter table public.profiles    enable row level security;
alter table public.assessments enable row level security;
