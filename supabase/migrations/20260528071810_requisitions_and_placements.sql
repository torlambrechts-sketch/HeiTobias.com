-- 20260528070700_requisitions_and_placements
--
-- Phase 0 / Step 2.5 — the hiring transaction.
--
--   requisitions:           the hiring object (agency- or employer-initiated).
--   requisition_candidates: candidates being considered for a requisition.
--   placements:             the CLOSED event that triggers the consent-gated cross-org
--                           hand-off. The ONLY sanctioned cross-org data bridge.
--
-- placements is intentionally cross-org: it carries from_org_id (agency) and to_org_id
-- (employer). It has no single org_id column — Step 6 will give it a special RLS policy
-- that admits readers from either side.
--
-- placements.consent_id is declared without an FK here; Step 4 adds the FK
-- once consent_grants exists.

create type public.requisition_status            as enum ('open','shortlisting','placed','closed');
create type public.requisition_candidate_stage   as enum ('sourced','screening','interview','offer','rejected','withdrawn','placed');
create type public.requisition_candidate_decision as enum ('pending','advance','reject','hire','withdraw');
create type public.placement_status              as enum ('pending_consent','transferred','activated','revoked');

-- ---------------------------------------------------------------------------
-- requisitions
-- ---------------------------------------------------------------------------

create table public.requisitions (
  id                   uuid primary key default extensions.gen_random_uuid(),
  org_id               uuid not null references public.organizations(id) on delete restrict,
  role_id              uuid not null references public.roles_catalog(id) on delete restrict,
  team_id              uuid references public.teams(id) on delete set null,
  status               public.requisition_status not null default 'open',
  collaborating_org_id uuid references public.organizations(id) on delete set null,
  created_by           uuid references public.people(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint chk_collab_diff_org check (collaborating_org_id is null or collaborating_org_id <> org_id)
);
create index requisitions_org_idx          on public.requisitions (org_id);
create index requisitions_role_idx         on public.requisitions (role_id);
create index requisitions_collab_org_idx   on public.requisitions (collaborating_org_id);

create trigger trg_requisitions_updated_at
  before update on public.requisitions
  for each row execute function public.set_updated_at();

-- A requisition's role must be a non-template role in the same org.
create or replace function public._check_requisition_role_org()
returns trigger language plpgsql as $$
declare r record;
begin
  select org_id, is_template into r from public.roles_catalog where id = new.role_id;
  if not found then
    raise exception 'requisitions.role_id references missing row';
  end if;
  if r.is_template = true then
    raise exception 'requisitions.role_id must reference a non-template role';
  end if;
  if r.org_id is distinct from new.org_id then
    raise exception 'requisitions.role_id must reference a role in the same org';
  end if;
  return new;
end;
$$;
create trigger trg_requisitions_check_role_org
  before insert or update on public.requisitions
  for each row execute function public._check_requisition_role_org();

comment on table public.requisitions is
  'Hiring transaction object. collaborating_org_id enables the Model 2 shared (agency+employer) workspace.';

-- ---------------------------------------------------------------------------
-- requisition_candidates
-- ---------------------------------------------------------------------------

create table public.requisition_candidates (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete restrict,
  requisition_id  uuid not null references public.requisitions(id) on delete cascade,
  person_id       uuid not null references public.people(id) on delete restrict,
  stage           public.requisition_candidate_stage not null default 'sourced',
  fit_score_json  jsonb not null default '{}'::jsonb
                    check (jsonb_typeof(fit_score_json) = 'object'),
  decision        public.requisition_candidate_decision not null default 'pending',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (requisition_id, person_id)
);
create index req_candidates_person_idx on public.requisition_candidates (person_id);
create index req_candidates_org_idx    on public.requisition_candidates (org_id);

create trigger trg_requisition_candidates_updated_at
  before update on public.requisition_candidates
  for each row execute function public.set_updated_at();

-- A candidate row's org must match the requisition's org.
create or replace function public._check_req_candidate_same_org()
returns trigger language plpgsql as $$
declare req_org uuid;
begin
  select org_id into req_org from public.requisitions where id = new.requisition_id;
  if req_org is null then
    raise exception 'requisition_candidates.requisition_id references missing row';
  end if;
  if req_org <> new.org_id then
    raise exception 'requisition_candidates.org_id must match the requisition''s org';
  end if;
  return new;
end;
$$;
create trigger trg_req_candidates_check_org
  before insert or update on public.requisition_candidates
  for each row execute function public._check_req_candidate_same_org();

comment on table public.requisition_candidates is
  'fit_score_json is multi-dimensional. Per CLAUDE.md: a score informs a human decision; it never auto-decides.';

-- ---------------------------------------------------------------------------
-- placements — the consent-gated cross-org bridge
-- ---------------------------------------------------------------------------

create table public.placements (
  id              uuid primary key default extensions.gen_random_uuid(),
  requisition_id  uuid not null references public.requisitions(id) on delete restrict,
  person_id       uuid not null references public.people(id)        on delete restrict,
  from_org_id     uuid not null references public.organizations(id) on delete restrict,
  to_org_id       uuid not null references public.organizations(id) on delete restrict,
  status          public.placement_status not null default 'pending_consent',
  consent_id      uuid,  -- FK added in Step 4 (consent_grants migration)
  transferred_at  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint chk_placement_cross_org check (from_org_id <> to_org_id)
);
create index placements_from_org_idx     on public.placements (from_org_id);
create index placements_to_org_idx       on public.placements (to_org_id);
create index placements_person_idx       on public.placements (person_id);
create index placements_requisition_idx  on public.placements (requisition_id);
create index placements_consent_idx      on public.placements (consent_id);

create trigger trg_placements_updated_at
  before update on public.placements
  for each row execute function public.set_updated_at();

-- The placement's from_org must match the requisition's org (the originator).
-- (We don't constrain to_org against requisition because Model 2 collaborates upfront,
--  but the agency is always the from_org by definition of the hand-off direction.)
create or replace function public._check_placement_from_org_matches_requisition()
returns trigger language plpgsql as $$
declare req_org uuid;
begin
  select org_id into req_org from public.requisitions where id = new.requisition_id;
  if req_org is null then
    raise exception 'placements.requisition_id references missing row';
  end if;
  if req_org <> new.from_org_id then
    raise exception 'placements.from_org_id must equal the requisition''s org_id (the originating side)';
  end if;
  return new;
end;
$$;
create trigger trg_placements_check_from_org
  before insert or update on public.placements
  for each row execute function public._check_placement_from_org_matches_requisition();

comment on table public.placements is
  'CLOSED event that triggers the consent-gated cross-org hand-off (agency → employer). The ONLY sanctioned cross-org data bridge.';

-- ---------------------------------------------------------------------------
-- RLS default-deny
-- ---------------------------------------------------------------------------

alter table public.requisitions           enable row level security;
alter table public.requisition_candidates enable row level security;
alter table public.placements             enable row level security;
