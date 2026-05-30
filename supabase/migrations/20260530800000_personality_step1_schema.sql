-- Personality Module — Step 1: schema.
--
-- Adds the registry tables (traits, role templates, norms) and the
-- per-(session × role-template) match result table.
--
-- Item bank itself goes into the existing public.assessment_items table
-- under a new global instrument (Step 3 seed).
--
-- Provenance discipline (CLAUDE.md §5):
--   * assessment_instruments row for personality_v1 → validity_status =
--     'licensed' (IPIP / IPIP-HEXACO items are public-domain licensed).
--   * personality_role_templates seeded as dev_stub — bands are literature-
--     synthesised but require population-specific calibration (H-3 + H-7).
--   * personality_norms seeded as dev_stub synthetic normal distributions
--     per trait — H-2 (Nordic norm samples) gates real norms.
--   * personality_role_matches: validated requires real match_score AND
--     _dev_stub=false, mirroring the assessment_scores CHECK pattern.
--
-- Refusal seam (CLAUDE.md "fit informs, never decides"):
--   * Dark Triad traits and any other (review_flag=true, weight=0) trait
--     produce HUMAN-REVIEW flags only. The CHECK constraints below make
--     this enforced at the schema level, not by convention.

-- ─── 1. personality_traits ──────────────────────────────────────────
-- Registry of traits we model. Per-trait metadata: framework,
-- citations (validity_summary), reliability estimate, scored direction,
-- sensitive=true for Dark Triad (UI badges + extra audit).
create table if not exists public.personality_traits (
  trait_key         text primary key,
  name              text not null,
  domain            text not null,
  framework         text not null,
  source            text not null,
  license           text not null,
  alpha_estimate    numeric check (alpha_estimate is null or (alpha_estimate >= 0 and alpha_estimate <= 1)),
  scored_direction  text,
  definition        text,
  validity_summary  text,
  sensitive         boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create trigger trg_touch_personality_traits before update on public.personality_traits
  for each row execute function public.set_updated_at();

alter table public.personality_traits enable row level security;
alter table public.personality_traits force  row level security;
-- Read for any authenticated user (it's platform reference content).
drop policy if exists personality_traits_read on public.personality_traits;
create policy personality_traits_read on public.personality_traits
  for select to authenticated using (true);
-- Writes go through migrations (service_role); no INSERT/UPDATE/DELETE policy.

-- ─── 2. personality_norms ───────────────────────────────────────────
-- Per-trait normative reference distribution. Stored as 100
-- percentile-breakpoint values (the trait-mean value at p=1, 2, ..., 100),
-- so percentile lookup is bisect-left on a fixed-size array.
--
-- Until H-2 closes, the seeded rows are synthetic dev_stub samples and
-- every score derived from them inherits the stub flag.
create table if not exists public.personality_norms (
  trait_key         text not null references public.personality_traits(trait_key) on delete cascade,
  population_key    text not null default 'global_dev_stub',
  sample_n          int  not null check (sample_n > 0),
  breakpoints       jsonb not null
                      check (jsonb_typeof(breakpoints) = 'array'
                             and jsonb_array_length(breakpoints) = 100),
  validity_status   public.validity_status not null default 'dev_stub',
  _dev_stub         boolean not null default true,
  source_note       text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (trait_key, population_key),
  -- THE SEAM. A 'validated' norm row must NOT carry the per-value stub flag.
  constraint chk_norms_validated_real check (
    validity_status <> 'validated' or coalesce(_dev_stub, false) = false
  )
);
create trigger trg_touch_personality_norms before update on public.personality_norms
  for each row execute function public.set_updated_at();
alter table public.personality_norms enable row level security;
alter table public.personality_norms force  row level security;
drop policy if exists personality_norms_read on public.personality_norms;
create policy personality_norms_read on public.personality_norms
  for select to authenticated using (true);

-- ─── 3. personality_role_templates ──────────────────────────────────
-- Role benchmark templates (10 seeded). org_id NULL = global; an org
-- can later clone-and-customise into an org-scoped row.
create table if not exists public.personality_role_templates (
  role_key          text not null,
  org_id            uuid references public.organizations(id) on delete cascade,
  title             text not null,
  family            text not null,
  summary           text,
  key_citations     text[] not null default '{}',
  weight_cap        numeric not null default 0.35
                      check (weight_cap > 0 and weight_cap <= 1),
  match_tolerance_ref int not null default 40
                      check (match_tolerance_ref between 1 and 99),
  validity_status   public.validity_status not null default 'dev_stub',
  _dev_stub         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (role_key, org_id),
  constraint chk_role_templates_validated_real check (
    validity_status <> 'validated' or coalesce(_dev_stub, false) = false
  )
);
-- A second uniqueness for the common case (lookups by role_key when org
-- is global) is implicit in the PK (role_key, NULL).
create index if not exists personality_role_templates_org_idx
  on public.personality_role_templates (org_id);
create trigger trg_touch_personality_role_templates before update on public.personality_role_templates
  for each row execute function public.set_updated_at();
alter table public.personality_role_templates enable row level security;
alter table public.personality_role_templates force  row level security;
drop policy if exists personality_role_templates_read on public.personality_role_templates;
-- Read: global rows visible to all authenticated users; org-scoped rows
-- visible to anyone with role.read in that org.
create policy personality_role_templates_read on public.personality_role_templates
  for select to authenticated using (
    org_id is null or public.has_permission(org_id, 'role.read')
  );

-- ─── 4. personality_role_template_traits ────────────────────────────
-- Per-template trait config. Two shapes are enforced via CHECK:
--   * NUMERIC CONTRIBUTOR: weight > 0, review_flag=false, band [lo,hi]
--     present (both in 0..99, lo<=hi), direction ∈ {higher,lower,target}.
--   * HUMAN-REVIEW FLAG: weight = 0, review_flag = true, flag_threshold
--     present (1..99), band NULL or absent.
-- The two shapes are mutually exclusive — a trait is either a scoring
-- contributor or a flag, never both.
create type public.personality_trait_direction as enum
  ('higher_better', 'lower_better', 'target_band');

create table if not exists public.personality_role_template_traits (
  id                bigserial primary key,
  role_key          text not null,
  org_id            uuid,
  trait_key         text not null references public.personality_traits(trait_key) on delete restrict,
  band_low          int check (band_low is null or (band_low between 0 and 99)),
  band_high         int check (band_high is null or (band_high between 0 and 99)),
  direction         public.personality_trait_direction not null,
  weight            numeric not null default 0
                      check (weight >= 0 and weight <= 1),
  review_flag       boolean not null default false,
  flag_threshold    int check (flag_threshold is null or (flag_threshold between 1 and 99)),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (role_key, org_id, trait_key),
  foreign key (role_key, org_id) references public.personality_role_templates(role_key, org_id) on delete cascade,
  -- Shape gate (numeric OR flag, never both, never neither).
  constraint chk_template_trait_shape check (
    (review_flag = false and weight > 0 and band_low is not null and band_high is not null and band_low <= band_high)
    or
    (review_flag = true  and weight = 0 and flag_threshold is not null)
  )
);
create index if not exists personality_role_template_traits_role_idx
  on public.personality_role_template_traits (role_key, org_id);
create trigger trg_touch_personality_role_template_traits before update on public.personality_role_template_traits
  for each row execute function public.set_updated_at();
alter table public.personality_role_template_traits enable row level security;
alter table public.personality_role_template_traits force  row level security;
drop policy if exists personality_role_template_traits_read on public.personality_role_template_traits;
create policy personality_role_template_traits_read on public.personality_role_template_traits
  for select to authenticated using (
    org_id is null or public.has_permission(org_id, 'role.read')
  );

-- ─── 5. personality_role_matches ────────────────────────────────────
-- Per-(session × role_template) match output. Written by
-- personality_compute_scores(session_id) (Step 4).
--
-- contributions_json: sorted by penalty desc, each row carries
--   { trait_key, percentile, band:[lo,hi]|null, direction, weight,
--     severity, penalty }.
-- flags_json: HUMAN-REVIEW flag rows, never contributing to the match
--   number. Each: { trait_key, percentile, threshold }.
create table if not exists public.personality_role_matches (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id) on delete restrict,
  session_id          uuid not null references public.assessment_sessions(id) on delete cascade,
  person_id           uuid not null references public.people(id)        on delete restrict,
  role_key            text not null,
  role_template_org_id uuid,                                    -- which template row matched (global or org)
  match_score         int check (match_score is null or (match_score between 0 and 100)),
  contributions_json  jsonb not null default '[]'::jsonb
                        check (jsonb_typeof(contributions_json) = 'array'),
  flags_json          jsonb not null default '[]'::jsonb
                        check (jsonb_typeof(flags_json) = 'array'),
  validity_status     public.validity_status not null default 'dev_stub',
  _dev_stub           boolean not null default true,
  computed_at         timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (session_id, role_key),
  -- THE SEAM. Validated match must have a real number AND not carry the stub flag.
  constraint chk_role_matches_validated_real check (
    validity_status <> 'validated'
    or (match_score is not null and coalesce(_dev_stub, false) = false)
  )
);
create index if not exists personality_role_matches_person_idx
  on public.personality_role_matches (person_id, computed_at desc);
create index if not exists personality_role_matches_session_idx
  on public.personality_role_matches (session_id);
create trigger trg_touch_personality_role_matches before update on public.personality_role_matches
  for each row execute function public.set_updated_at();
create trigger trg_audit_personality_role_matches
  after insert or update or delete on public.personality_role_matches
  for each row execute function public._audit_row();

alter table public.personality_role_matches enable row level security;
alter table public.personality_role_matches force  row level security;

-- Reads: the data subject sees their own; org users with fit.read on the
-- session's org see the org's; platform_admin sees all.
drop policy if exists personality_role_matches_select on public.personality_role_matches;
create policy personality_role_matches_select on public.personality_role_matches
  for select to authenticated using (
    public.is_self(person_id)
    or public.has_permission(org_id, 'fit.read')
    or public.is_platform_admin()
  );
-- Writes go through the SECDEF RPC (Step 4); no direct insert/update/delete policy.

comment on table public.personality_traits is
  'Trait registry for the personality module. Metadata + citations. Read by all authenticated users; writes via migration only.';
comment on table public.personality_norms is
  'Per-trait normative percentile breakpoints. dev_stub seeded by Step 3; H-2 closes by replacing rows with population_key=''nordic_v1'' + validity_status=''validated''.';
comment on table public.personality_role_templates is
  'Role benchmark templates. Global if org_id IS NULL. Validity_status=dev_stub until H-3 + H-7 sign-off + population calibration.';
comment on table public.personality_role_template_traits is
  'Per-template trait config. Numeric contributor (weight>0, band present) OR human-review flag (weight=0, threshold present) — never both. Enforced by chk_template_trait_shape.';
comment on table public.personality_role_matches is
  'Per-(session × role-template) match output. Match number INFORMS a human decision; dark-triad flags are HUMAN-REVIEW only and never contribute to the number.';
