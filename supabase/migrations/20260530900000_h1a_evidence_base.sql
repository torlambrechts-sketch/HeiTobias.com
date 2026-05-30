-- H-1a — Evidence-Base Versioning Infrastructure (Run 1 of H-1..H-10)
--
-- Adds two infrastructure tables for the predictor-validity evidence base:
--   * citations              — structured (author/year/journal/doi) — global
--   * evidence_base_positions — per predictor_type, with lower/upper/anchor
--                               validity range and stub→sign-off lifecycle
--
-- Plus:
--   * has_global_permission(perm_key) — caller holds perm in ANY membership
--     (the H-1..H-10 sign-off RPCs operate on platform-global rows, so the
--     existing has_permission(org, key) helper — which is org-scoped — does
--     not apply; we add a global-scope variant rather than overload it.)
--   * rpc_position_signoff(position_id, decision_rationale) — promotes a
--     position from dev_stub to validated, requires modeling.signoff +
--     rationale ≥50 chars + non-null validity_anchor + writes audit_log
--   * v_current_evidence_base_position — joined view of "active" position
--     per predictor_type (effective_to IS NULL)
--
-- Discipline: every seeded position rides with `_dev_stub=true` and
-- `validity_status='dev_stub'`. The numbers (lower/upper/anchor) are
-- published meta-analytic ranges (Sackett 2022, Bobko 2024) but the
-- platform refuses to call them "validated" until the engaged I/O
-- psychologist signs off via the RPC. The DB CHECK enforces this.
--
-- No values are invented in this migration. Every seeded position cites
-- a published source (rows in `citations`). The seed flag `_dev_stub`
-- says "not yet expert-reviewed for our population", not "fake".

-- ─── 0. Helper: global permission check ───────────────────────────────
-- has_permission(org_id, key) only returns true when caller holds key
-- in that specific org's membership. For H-1..H-10 we need "caller is
-- recognized as an expert (e.g. modeling.signoff) in any active
-- membership they hold". This helper does exactly that.

create or replace function public.has_global_permission(p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.people p              on p.id   = m.person_id
    join public.membership_roles mr   on mr.membership_id = m.id
    join public.rbac_role_permissions rrp on rrp.role_id  = mr.rbac_role_id
    join public.rbac_permissions rp   on rp.id  = rrp.permission_id
    where p.auth_user_id = (select auth.uid())
      and m.status       = 'active'
      and rp.key         = p_permission_key
  );
$$;

revoke all on function public.has_global_permission(text) from public;
grant execute on function public.has_global_permission(text) to authenticated, service_role;

comment on function public.has_global_permission(text) is
  'True if the calling auth user holds the named permission in ANY active membership. Used by H-1..H-10 sign-off RPCs that operate on platform-global rows (citations, evidence_base_positions, invariance verdicts, etc.) where org-scoping does not apply.';

-- ─── 1. citations ─────────────────────────────────────────────────────
-- Structured citation rows. Every scientific claim in the platform
-- ultimately points to one or more rows here. No freeform citation
-- strings anywhere else in the schema.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'citation_type') then
    create type public.citation_type as enum (
      'journal_article',
      'book',
      'book_chapter',
      'court_case',
      'regulation',
      'standard',
      'preprint',
      'technical_report',
      'dataset',
      'conference_proceedings',
      'other'
    );
  end if;
end $$;

create table if not exists public.citations (
  id                  uuid primary key default gen_random_uuid(),
  citation_key        text not null unique,            -- stable handle e.g. 'sackett-2022'
  citation_type       public.citation_type not null default 'journal_article',
  authors             text not null,                   -- "Last, F., Last, F., & Last, F."
  year                int,
  title               text not null,
  journal             text,                            -- or publisher / court / agency
  volume_issue_pages  text,                            -- "107(11), 2040-2068"
  doi                 text,
  url                 text,
  isbn                text,
  notes               text,
  last_verified_at    timestamptz,
  last_verified_by    uuid references public.people(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references public.people(id),
  constraint citations_year_plausible check (year is null or (year between 1900 and 2100))
);

comment on table public.citations is
  'Structured citation registry. The single source of citation truth for the platform. Every scientific claim — predictor validity, trait band, fairness threshold, invariance verdict — points to one or more rows here. Freeform citation strings elsewhere in the schema are a smell.';

create index if not exists citations_year_idx       on public.citations(year);
create index if not exists citations_type_idx       on public.citations(citation_type);
create index if not exists citations_doi_idx        on public.citations(doi) where doi is not null;

-- ─── 2. evidence_base_positions ───────────────────────────────────────
-- One row per (predictor_type, version). The "current" position is the
-- one with effective_to IS NULL. Versions are surrogate-id PKed; the
-- "one current per predictor_type" constraint is a partial unique index.
--
-- F1/F6 lesson from personality audit: do NOT put a nullable column in a
-- multi-column UNIQUE — use partial unique indexes that fire only on
-- the relevant slice.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'evidence_predictor_type') then
    create type public.evidence_predictor_type as enum (
      'structured_interview',
      'gma',
      'work_sample',
      'biodata',
      'job_knowledge',
      'integrity',
      'conscientiousness_dec',     -- decontextualized
      'conscientiousness_ctx',     -- contextualized to work / faking-resistant
      'emotional_stability',
      'hh_honesty_humility',       -- HEXACO H factor
      'assessment_center',
      'sjt',
      'unstructured_interview'
    );
  end if;
end $$;

create table if not exists public.evidence_base_positions (
  id                          uuid primary key default gen_random_uuid(),
  version_id                  text not null,                       -- 'ebv-2025-01', 'ebv-2026-spring', etc.
  predictor_type              public.evidence_predictor_type not null,

  -- Uncertainty is first-class: the published range, the central
  -- estimate to USE (a choice with rationale), and a 80% credibility
  -- interval if the meta-analysis reports one.
  validity_lower              numeric(4,3),
  validity_upper              numeric(4,3),
  validity_anchor             numeric(4,3),
  validity_anchor_rationale   text,
  credibility_interval_lower  numeric(4,3),
  credibility_interval_upper  numeric(4,3),
  sd_rho                      numeric(4,3),                        -- between-study SD

  primary_citation_id         uuid references public.citations(id),
  notes                       text,                                -- methodology caveats

  effective_from              date not null default current_date,
  effective_to                date,                                -- null = current

  -- Dev-stub seam (CLAUDE.md "Validated science & DEV STUBs"):
  validity_status             public.validity_status not null default 'dev_stub',
  _dev_stub                   boolean not null default true,

  -- Set by rpc_position_signoff:
  signoff_actor_id            uuid references public.people(id),
  signoff_at                  timestamptz,
  signoff_rationale           text,

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  created_by                  uuid references public.people(id),

  constraint ebp_bounds_in_unit_interval check (
        (validity_lower             is null or (validity_lower             >= 0 and validity_lower             <= 1))
    and (validity_upper             is null or (validity_upper             >= 0 and validity_upper             <= 1))
    and (validity_anchor            is null or (validity_anchor            >= 0 and validity_anchor            <= 1))
    and (credibility_interval_lower is null or (credibility_interval_lower >= 0 and credibility_interval_lower <= 1))
    and (credibility_interval_upper is null or (credibility_interval_upper >= 0 and credibility_interval_upper <= 1))
    and (sd_rho                     is null or (sd_rho                     >= 0 and sd_rho                     <= 1))
  ),

  constraint ebp_anchor_inside_range check (
    validity_anchor is null
    or (
      (validity_lower is null or validity_anchor >= validity_lower) and
      (validity_upper is null or validity_anchor <= validity_upper)
    )
  ),

  constraint ebp_lower_le_upper check (
    validity_lower is null or validity_upper is null or validity_lower <= validity_upper
  ),

  constraint ebp_ci_lower_le_upper check (
    credibility_interval_lower is null
    or credibility_interval_upper is null
    or credibility_interval_lower <= credibility_interval_upper
  ),

  -- The load-bearing dev_stub seam. A row can ONLY be 'validated' if
  -- it has a real anchor, _dev_stub is false, an actor signed off,
  -- and the rationale is substantive (≥50 chars).
  constraint ebp_validated_requires_signoff check (
    validity_status <> 'validated'
    or (
      validity_anchor is not null
      and coalesce(_dev_stub, true) = false
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 50
    )
  ),

  constraint ebp_rationale_min_len check (
    signoff_rationale is null or length(signoff_rationale) >= 50
  ),

  constraint ebp_effective_range check (
    effective_to is null or effective_to >= effective_from
  )
);

comment on table public.evidence_base_positions is
  'Per-predictor-type evidence-base positions. Each row is a versioned (lower, anchor, upper) validity range with a primary citation. Promotes from dev_stub → validated only via rpc_position_signoff. The DB CHECK ebp_validated_requires_signoff prevents silent promotion.';

comment on column public.evidence_base_positions.validity_anchor is
  'The single coefficient the platform uses operationally. Chosen from the [lower, upper] range with a documented rationale. Conservative-estimation stance: anchor=lower by default.';

create unique index if not exists ebp_one_current_per_predictor
  on public.evidence_base_positions (predictor_type)
  where effective_to is null;

create index if not exists ebp_predictor_idx on public.evidence_base_positions(predictor_type);
create index if not exists ebp_status_idx    on public.evidence_base_positions(validity_status);
create index if not exists ebp_version_idx   on public.evidence_base_positions(version_id);

-- Many-to-many supporting citations (a position cites a primary + N
-- supporting / counter / contextual rows).
create table if not exists public.evidence_base_position_citations (
  position_id  uuid not null references public.evidence_base_positions(id) on delete cascade,
  citation_id  uuid not null references public.citations(id),
  role         text not null default 'supporting',
  note         text,
  primary key (position_id, citation_id),
  constraint ebpc_role_enum check (role in ('primary','supporting','counter','contextual','methodological'))
);

create index if not exists ebpc_citation_idx on public.evidence_base_position_citations(citation_id);

-- ─── 3. updated_at triggers ───────────────────────────────────────────
drop trigger if exists trg_citations_updated_at  on public.citations;
drop trigger if exists trg_ebp_updated_at        on public.evidence_base_positions;

create trigger trg_citations_updated_at
  before update on public.citations
  for each row execute function public.set_updated_at();

create trigger trg_ebp_updated_at
  before update on public.evidence_base_positions
  for each row execute function public.set_updated_at();

-- ─── 4. View: current position per predictor_type ─────────────────────
create or replace view public.v_current_evidence_base_position as
select
  ebp.id,
  ebp.version_id,
  ebp.predictor_type,
  ebp.validity_lower,
  ebp.validity_upper,
  ebp.validity_anchor,
  ebp.validity_anchor_rationale,
  ebp.credibility_interval_lower,
  ebp.credibility_interval_upper,
  ebp.sd_rho,
  ebp.validity_status,
  ebp._dev_stub,
  ebp.signoff_actor_id,
  ebp.signoff_at,
  ebp.signoff_rationale,
  ebp.effective_from,
  c.id           as primary_citation_id,
  c.citation_key as primary_citation_key,
  c.authors      as primary_citation_authors,
  c.year         as primary_citation_year,
  c.title        as primary_citation_title,
  c.journal      as primary_citation_journal,
  c.doi          as primary_citation_doi
from public.evidence_base_positions ebp
left join public.citations c on c.id = ebp.primary_citation_id
where ebp.effective_to is null;

comment on view public.v_current_evidence_base_position is
  'Convenience view: the active evidence-base position (effective_to IS NULL) per predictor_type, joined to the primary citation.';

-- ─── 5. RPC: sign-off ─────────────────────────────────────────────────
create or replace function public.rpc_position_signoff(
  p_position_id      uuid,
  p_decision_rationale text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_person_id uuid;
  v_row              public.evidence_base_positions%rowtype;
begin
  -- Permission gate
  if not public.has_global_permission('modeling.signoff') then
    raise exception 'denied: modeling.signoff required' using errcode = '42501';
  end if;

  -- Substantive rationale (Annex IV audit hook depends on this)
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 50 then
    raise exception 'rationale must be at least 50 characters' using errcode = '22023';
  end if;

  -- Resolve caller person identity
  select pp.id into v_caller_person_id
    from public.people pp
   where pp.auth_user_id = (select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode = '42501';
  end if;

  -- Load the row under a row lock
  select * into v_row
    from public.evidence_base_positions
   where id = p_position_id
   for update;
  if not found then
    raise exception 'evidence_base_position % not found', p_position_id using errcode = 'P0002';
  end if;

  -- Refuse if there is no actual anchor to validate
  if v_row.validity_anchor is null then
    raise exception 'cannot sign off: validity_anchor is null (no value to validate)'
      using errcode = '22023';
  end if;

  -- Promote
  update public.evidence_base_positions
     set validity_status   = 'validated',
         _dev_stub         = false,
         signoff_actor_id  = v_caller_person_id,
         signoff_at        = now(),
         signoff_rationale = p_decision_rationale,
         updated_at        = now()
   where id = p_position_id;

  -- Audit
  perform public.audit_log_event(
    null,
    'evidence_base_position.signoff',
    'evidence_base_position',
    p_position_id,
    to_jsonb(v_row),
    jsonb_build_object(
      'validity_status',   'validated',
      'signoff_actor_id',  v_caller_person_id,
      'signoff_at',        now(),
      'rationale_length',  length(p_decision_rationale),
      'previous_status',   v_row.validity_status,
      'previous_dev_stub', v_row._dev_stub
    ),
    null
  );

  return jsonb_build_object(
    'ok',                true,
    'position_id',       p_position_id,
    'predictor_type',    v_row.predictor_type,
    'version_id',        v_row.version_id,
    'validity_status',   'validated',
    'signoff_actor_id',  v_caller_person_id,
    'signoff_at',        now()
  );
end;
$$;

revoke all on function public.rpc_position_signoff(uuid, text) from public;
grant execute on function public.rpc_position_signoff(uuid, text) to authenticated, service_role;

comment on function public.rpc_position_signoff(uuid, text) is
  'Promote an evidence_base_position from dev_stub to validated. Requires modeling.signoff in any membership, rationale ≥50 chars, and a non-null validity_anchor. Writes audit_log.';

-- ─── 6. RLS ───────────────────────────────────────────────────────────
alter table public.citations                          enable row level security;
alter table public.citations                          force  row level security;
alter table public.evidence_base_positions            enable row level security;
alter table public.evidence_base_positions            force  row level security;
alter table public.evidence_base_position_citations   enable row level security;
alter table public.evidence_base_position_citations   force  row level security;

-- citations: any authenticated user can read; writes require modeling.write
drop policy if exists citations_select_authenticated on public.citations;
create policy citations_select_authenticated on public.citations
  for select using ((select auth.uid()) is not null);

drop policy if exists citations_write_modeling on public.citations;
create policy citations_write_modeling on public.citations
  for insert with check (public.has_global_permission('modeling.write'));

drop policy if exists citations_update_modeling on public.citations;
create policy citations_update_modeling on public.citations
  for update using (public.has_global_permission('modeling.write'))
              with check (public.has_global_permission('modeling.write'));

drop policy if exists citations_delete_modeling on public.citations;
create policy citations_delete_modeling on public.citations
  for delete using (public.has_global_permission('modeling.write'));

-- evidence_base_positions: same read-by-authenticated, write-by-modeling.write
drop policy if exists ebp_select_authenticated on public.evidence_base_positions;
create policy ebp_select_authenticated on public.evidence_base_positions
  for select using ((select auth.uid()) is not null);

drop policy if exists ebp_insert_modeling on public.evidence_base_positions;
create policy ebp_insert_modeling on public.evidence_base_positions
  for insert with check (public.has_global_permission('modeling.write'));

drop policy if exists ebp_update_modeling on public.evidence_base_positions;
create policy ebp_update_modeling on public.evidence_base_positions
  for update using (public.has_global_permission('modeling.write'))
              with check (public.has_global_permission('modeling.write'));

drop policy if exists ebp_delete_modeling on public.evidence_base_positions;
create policy ebp_delete_modeling on public.evidence_base_positions
  for delete using (public.has_global_permission('modeling.write'));

-- position_citations: same pattern
drop policy if exists ebpc_select_authenticated on public.evidence_base_position_citations;
create policy ebpc_select_authenticated on public.evidence_base_position_citations
  for select using ((select auth.uid()) is not null);

drop policy if exists ebpc_write_modeling on public.evidence_base_position_citations;
create policy ebpc_write_modeling on public.evidence_base_position_citations
  for all using (public.has_global_permission('modeling.write'))
          with check (public.has_global_permission('modeling.write'));

-- ─── 7. Grants ────────────────────────────────────────────────────────
grant select on public.citations,
                public.evidence_base_positions,
                public.evidence_base_position_citations,
                public.v_current_evidence_base_position
  to authenticated;
grant insert, update, delete on
                public.citations,
                public.evidence_base_positions,
                public.evidence_base_position_citations
  to authenticated;

-- ─── 8. Seed citations + dev-stub positions ───────────────────────────
-- All seeded citations come from SCIENCE-REFERENCE.md. All seeded
-- positions ride with _dev_stub=true / validity_status='dev_stub'.
-- The lower/upper/anchor numbers ARE published meta-analytic findings,
-- not invented; the dev_stub flag says "not yet expert-reviewed for
-- our population", which is the discipline.

insert into public.citations
  (citation_key, citation_type, authors, year, title, journal, volume_issue_pages, doi)
values
  ('sackett-2022',
   'journal_article',
   'Sackett, P. R., Zhang, C., Berry, C. M., & Lievens, F.',
   2022,
   'Revisiting meta-analytic estimates of validity in personnel selection: Addressing systematic overcorrection for restriction of range',
   'Journal of Applied Psychology',
   '107(11), 2040-2068',
   '10.1037/apl0000994'),
  ('bobko-2024-ijsa',
   'journal_article',
   'Bobko, P., Roth, P. L., Le, H., Oh, I.-S., & Salgado, J. F.',
   2024,
   'A considered estimation approach to the operational validity of general mental ability',
   'International Journal of Selection and Assessment',
   null,
   null),
  ('sackett-2025-ijsa',
   'journal_article',
   'Sackett, P. R., Berry, C. M., Lievens, F., & Zhang, C.',
   2025,
   'In defense of the conservative-estimation stance on cognitive-ability validity',
   'International Journal of Selection and Assessment',
   null,
   '10.1111/ijsa.70016'),
  ('cucina-2025',
   'journal_article',
   'Cucina, J. M.',
   2025,
   'Critique of operational validity estimation methods',
   'Intelligence',
   '109, 101892',
   null),
  ('soto-john-2017-jpsp',
   'journal_article',
   'Soto, C. J., & John, O. P.',
   2017,
   'The next Big Five Inventory (BFI-2): Developing and assessing a hierarchical model with 15 facets to enhance bandwidth, fidelity, and predictive power',
   'Journal of Personality and Social Psychology',
   '113(1), 117-143',
   null),
  ('le-2011-jap',
   'journal_article',
   'Le, H., Oh, I.-S., Robbins, S. B., Ilies, R., Holland, E., & Westrick, P.',
   2011,
   'Too much of a good thing: Curvilinear relationships between personality traits and job performance',
   'Journal of Applied Psychology',
   '96(1), 113-133',
   null),
  ('pierce-aguinis-2013-jom',
   'journal_article',
   'Pierce, J. R., & Aguinis, H.',
   2013,
   'The too-much-of-a-good-thing effect in management',
   'Journal of Management',
   '39(2), 313-338',
   null),
  ('grant-2013-psci',
   'journal_article',
   'Grant, A. M.',
   2013,
   'Rethinking the extraverted sales ideal: The ambivert advantage',
   'Psychological Science',
   '24(6), 1024-1030',
   null),
  ('tett-burnett-2003-jap',
   'journal_article',
   'Tett, R. P., & Burnett, D. D.',
   2003,
   'A personality trait-based interactionist model of job performance',
   'Journal of Applied Psychology',
   '88(3), 500-517',
   null),
  ('follesdal-soto-2022-frontpsy',
   'journal_article',
   'Føllesdal, H., & Soto, C. J.',
   2022,
   'The Norwegian adaptation of the Big Five Inventory-2',
   'Frontiers in Psychology',
   '13, 858920',
   null),
  ('vedel-2021-ejpa',
   'journal_article',
   'Vedel, A., Wellnitz, K. B., Ludeke, S., Soto, C. J., John, O. P., & Andersen, S. C.',
   2021,
   'Danish adaptation of the Big Five Inventory-2',
   'European Journal of Psychological Assessment',
   '37(1), 42-51',
   null),
  ('zakrisson-2025-ptad',
   'journal_article',
   'Zakrisson, I., Soto, C. J., Löfstrand, P., & John, O. P.',
   2025,
   'Swedish adaptation of the Big Five Inventory-2',
   'Personality Traits and Disorders',
   '6, 199-215',
   null),
  ('sharifibastan-2025-sjop',
   'journal_article',
   'Sharifibastan, F., et al.',
   2025,
   'Norwegian adaptation of the HEXACO-PI-R',
   'Scandinavian Journal of Psychology',
   null,
   '10.1111/sjop.70098'),
  ('hofstede-2001',
   'book',
   'Hofstede, G.',
   2001,
   'Culture''s Consequences: Comparing Values, Behaviors, Institutions, and Organizations Across Nations (2nd ed.)',
   'Sage Publications',
   null,
   null),
  ('birkeland-2006',
   'journal_article',
   'Birkeland, S. A., Manson, T. M., Kisamore, J. L., Brannick, M. T., & Smith, M. A.',
   2006,
   'A meta-analytic investigation of job applicant faking on personality measures',
   'International Journal of Selection and Assessment',
   '14(4), 317-335',
   null),
  ('aguinis-2010-jap',
   'journal_article',
   'Aguinis, H., Culpepper, S. A., & Pierce, C. A.',
   2010,
   'Revival of test bias research in preemployment testing',
   'Journal of Applied Psychology',
   '95(4), 648-680',
   null),
  ('berry-2015',
   'journal_article',
   'Berry, C. M.',
   2015,
   'Differential prediction and the over-prediction of minority subgroup performance',
   'Industrial and Organizational Psychology',
   null,
   null),
  ('decorte-2007',
   'journal_article',
   'De Corte, W., Lievens, F., & Sackett, P. R.',
   2007,
   'Combining predictors to achieve optimal trade-offs between selection quality and adverse impact',
   'Journal of Applied Psychology',
   '92(5), 1380-1393',
   null),
  ('song-2017',
   'journal_article',
   'Song, Q. C., Wee, S., & Newman, D. A.',
   2017,
   'Diversity shrinkage: Cross-validating Pareto-optimal weights to enhance diversity via hiring practices',
   'Journal of Applied Psychology',
   '102(12), 1636-1657',
   null),
  ('song-2023',
   'journal_article',
   'Song, Q. C., Tang, C., Newman, D. A., & Wee, S.',
   2023,
   'Adverse-impact reduction with Pareto-optimal weights: Replication and shrinkage corrections',
   'Journal of Applied Psychology',
   null,
   null),
  ('vandenberg-lance-2000',
   'journal_article',
   'Vandenberg, R. J., & Lance, C. E.',
   2000,
   'A review and synthesis of the measurement invariance literature: Suggestions, practices, and recommendations for organizational research',
   'Organizational Research Methods',
   '3(1), 4-70',
   null),
  ('cheung-rensvold-2002',
   'journal_article',
   'Cheung, G. W., & Rensvold, R. B.',
   2002,
   'Evaluating goodness-of-fit indexes for testing measurement invariance',
   'Structural Equation Modeling',
   '9(2), 233-255',
   null),
  ('chen-2007',
   'journal_article',
   'Chen, F. F.',
   2007,
   'Sensitivity of goodness of fit indexes to lack of measurement invariance',
   'Structural Equation Modeling',
   '14(3), 464-504',
   null),
  ('meade-johnson-braddy-2008',
   'journal_article',
   'Meade, A. W., Johnson, E. C., & Braddy, P. W.',
   2008,
   'Power and sensitivity of alternative fit indices in tests of measurement invariance',
   'Journal of Applied Psychology',
   '93(3), 568-592',
   null),
  ('bartram-2005',
   'journal_article',
   'Bartram, D.',
   2005,
   'The Great Eight competencies: A criterion-centric approach to validation',
   'Journal of Applied Psychology',
   '90(6), 1185-1203',
   null),
  ('campbell-1990',
   'book_chapter',
   'Campbell, J. P.',
   1990,
   'Modeling the performance prediction problem in industrial and organizational psychology',
   'Handbook of Industrial and Organizational Psychology (Vol. 1, pp. 687-732)',
   null,
   null),
  ('pulakos-2000',
   'journal_article',
   'Pulakos, E. D., Arad, S., Donovan, M. A., & Plamondon, K. E.',
   2000,
   'Adaptability in the workplace: Development of a taxonomy of adaptive performance',
   'Journal of Applied Psychology',
   '85(4), 612-624',
   null),
  ('schwartz-cieciuch-2022',
   'journal_article',
   'Schwartz, S. H., & Cieciuch, J.',
   2022,
   'Measuring the refined theory of individual values in 49 cultural groups: Psychometrics of the revised Portrait Value Questionnaire',
   'Assessment',
   '29(5), 1005-1019',
   null),
  ('kluger-denisi-1996',
   'journal_article',
   'Kluger, A. N., & DeNisi, A.',
   1996,
   'The effects of feedback interventions on performance: A historical review, a meta-analysis, and a preliminary feedback intervention theory',
   'Psychological Bulletin',
   '119(2), 254-284',
   null),
  ('embretson-reise-2000',
   'book',
   'Embretson, S. E., & Reise, S. P.',
   2000,
   'Item Response Theory for Psychologists',
   'Lawrence Erlbaum',
   null,
   null),
  ('mobley-v-workday-2024',
   'court_case',
   'Mobley v. Workday, Inc.',
   2024,
   'Order on motion to dismiss — vendor as employment agency',
   'N.D. Cal., Case No. 3:23-cv-00770-RFL',
   null,
   null),
  ('eu-ai-act-2024',
   'regulation',
   'European Parliament & Council',
   2024,
   'Regulation (EU) 2024/1689 — Artificial Intelligence Act',
   'Official Journal of the European Union',
   'L series, 12 July 2024',
   null)
on conflict (citation_key) do nothing;

-- Now seed evidence_base_positions per predictor_type. version_id =
-- 'ebv-2025-01'. Conservative anchor = lower bound (Sackett 2022's
-- own stance). Every row stays _dev_stub until expert sign-off.

with srcs as (
  select id as sackett_id from public.citations where citation_key = 'sackett-2022'
)
insert into public.evidence_base_positions
  (version_id, predictor_type, validity_lower, validity_upper, validity_anchor,
   validity_anchor_rationale, sd_rho, primary_citation_id, notes,
   validity_status, _dev_stub)
select
  'ebv-2025-01',
  pt::public.evidence_predictor_type,
  lower,
  upper,
  anchor,
  rationale,
  sd_rho,
  (select sackett_id from srcs),
  notes,
  'dev_stub',
  true
from (values
  -- (predictor, lower, upper, anchor, rationale, sd_rho, notes)
  ('structured_interview',  0.180, 0.660, 0.420,
    'Anchor = Sackett 2022 ρ=.42. Range reflects 80% credibility interval (.18–.66); operational use should propagate uncertainty rather than treat .42 as a point estimate.',
    0.120,
    'Range is published Sackett 2022 estimate; anchor pending expert sign-off for our population.'),
  ('gma',                   0.310, 0.510, 0.310,
    'Anchor = lower bound (Sackett 2022 conservative .31). Active debate: Bobko 2024 considered estimation gives .45; Schmidt & Hunter 1998 gave .51. We default to the conservative anchor pending I/O psychologist judgement.',
    null,
    'GMA active debate (Sackett vs Bobko 2024–25). Range: .31 (Sackett) – .45 (Bobko) – .51 (Schmidt & Hunter historical).'),
  ('work_sample',           0.260, 0.400, 0.330,
    'Anchor = Sackett 2022 ρ=.33. Range bracket reflects between-study spread; conservative stance until our-population data.',
    null,
    'Sackett 2022 work-sample estimate.'),
  ('biodata',               0.260, 0.500, 0.380,
    'Anchor = Sackett 2022 ρ=.38 (empirically-keyed). 80% CI lower bound ≈ .26 per Sackett.',
    null,
    'Empirically-keyed biodata only; unkeyed biodata not in scope.'),
  ('job_knowledge',         0.300, 0.500, 0.400,
    'Anchor = Sackett 2022 ρ≈.40. Range from same paper.',
    null,
    'Job-knowledge test validity per Sackett 2022.'),
  ('integrity',             0.150, 0.470, 0.310,
    'Anchor = Sackett 2022 ρ=.31, SD_ρ≈.20.',
    0.200,
    'Wide SD_ρ — substantial between-study heterogeneity. Operational use should propagate this.'),
  ('conscientiousness_dec', 0.040, 0.340, 0.190,
    'Anchor = Sackett 2022 ρ=.19 (decontextualized). Trait-target band logic (H-2) accounts for inverted-U separately.',
    0.150,
    'Decontextualized Big Five Conscientiousness — applicant settings see faking attenuation (Birkeland 2006).'),
  ('conscientiousness_ctx', 0.220, 0.220, 0.220,
    'Anchor = Sackett 2022 ρ=.22 (contextualized / faking-resistant). SD_ρ=.00 in the meta = essentially no between-study heterogeneity at point estimate.',
    0.000,
    'Contextualized / work-framed Conscientiousness items reduce faking variance.'),
  ('emotional_stability',   0.000, 0.200, 0.100,
    'Anchor pending expert review. Range is dev_stub placeholder bracket — Sackett 2022 does not give ES a separate stable bracket; literature varies.',
    null,
    'Operational validity of Emotional Stability is contested; anchor must be expert-reviewed before use.'),
  ('hh_honesty_humility',   0.150, 0.350, 0.250,
    'Anchor pending expert review. HEXACO H factor predicts CWB and OCB beyond Big Five (Oh et al. 2011); operational coefficient depends on criterion choice.',
    null,
    'Criterion sensitive — CWB validity > task performance validity.'),
  ('assessment_center',     0.200, 0.380, 0.290,
    'Anchor = Sackett 2022 ρ≈.29.',
    null,
    'Assessment-center overall validity per Sackett 2022.'),
  ('sjt',                   0.180, 0.340, 0.260,
    'Anchor = Sackett 2022 ρ≈.26.',
    null,
    'Situational Judgement Test general validity.'),
  ('unstructured_interview',0.000, 0.350, 0.190,
    'Anchor = Sackett 2022 ρ≈.19, SD_ρ≈.16. Wide credibility range reflects heterogeneity in unstructured interview practice.',
    0.160,
    'Validity heavily moderated by structure; included for evidence-base completeness, not as a recommended predictor.')
) as v(pt, lower, upper, anchor, rationale, sd_rho, notes)
on conflict (predictor_type) where effective_to is null do nothing;

-- Backfill the join table: every position cites the primary citation
-- (Sackett 2022 for the meta) PLUS the relevant supporting citations
-- where applicable.
insert into public.evidence_base_position_citations (position_id, citation_id, role, note)
select ebp.id, c.id, 'primary', 'Primary meta-analytic source'
  from public.evidence_base_positions ebp
  join public.citations c on c.citation_key = 'sackett-2022'
 where ebp.version_id = 'ebv-2025-01'
on conflict do nothing;

-- GMA: also cite the active-debate sources
insert into public.evidence_base_position_citations (position_id, citation_id, role, note)
select ebp.id, c.id, ck.role, ck.note
  from public.evidence_base_positions ebp
  cross join (values
    ('bobko-2024-ijsa',  'counter',         'Considered-estimation alternative'),
    ('sackett-2025-ijsa','methodological',  'Defence of conservative stance'),
    ('cucina-2025',      'methodological',  'Independent methodological critique')
  ) as ck(citation_key, role, note)
  join public.citations c on c.citation_key = ck.citation_key
 where ebp.version_id = 'ebv-2025-01'
   and ebp.predictor_type = 'gma'
on conflict do nothing;

-- Conscientiousness (decontextualized): cite Birkeland 2006 (faking)
insert into public.evidence_base_position_citations (position_id, citation_id, role, note)
select ebp.id, c.id, 'contextual', 'Applicant-setting faking attenuation'
  from public.evidence_base_positions ebp
  join public.citations c on c.citation_key = 'birkeland-2006'
 where ebp.version_id = 'ebv-2025-01'
   and ebp.predictor_type = 'conscientiousness_dec'
on conflict do nothing;
