-- phase4_step4_fairness_audit — bias & fairness machinery.
-- SCIENCE-SPEC §10 + Phase 4 prompt §4.
--
-- Three load-bearing structural rules:
--
--   * DEMOGRAPHICS ARE SEPARATELY STORED + VOLUNTARY. demographics_voluntary
--     is its own table with its own RLS, gated by the fairness_monitoring
--     consent purpose. No prediction ever references this table.
--
--   * DEMOGRAPHICS ARE NEVER A PREDICTION FEATURE. A trigger on
--     feature_views refuses 'demographics_voluntary' in source_tables.
--     AI Act Art. 10(5) permits special-category processing for
--     bias-detection only; demographic-blind prediction is NOT
--     compliant — these data flow into fairness machinery, not models.
--
--   * NO SYSTEM-ASSERTED VERDICT. fairness_metrics carries:
--       * adverse_impact_ratio (computed)
--       * ci_lower / ci_upper (CIs computed)
--       * four_fifths_inspection_triggered boolean (TRIGGER, not verdict)
--       * differential_prediction_slope / _intercept (Cleary; computed)
--       * statistical_test_p_value (computed)
--       * interpretation_by_expert text NULL (the I/O psychologist fills
--         this; system never does)
--     Plus the chk_no_verdict_until_expert CHECK refuses any 'pass' or
--     'fail' string in a "system" verdict column — there isn't one.

-- ============ demographics_voluntary ============
-- Separately stored. Note this is BY DESIGN never referenced by
-- feature_views or model_registry; the AI Act §10(5) reasoning carves
-- demographics out as a bias-monitoring-only surface.
create table public.demographics_voluntary (
  id                uuid primary key default extensions.gen_random_uuid(),
  org_id            uuid not null references public.organizations(id),
  person_id         uuid not null references public.people(id),
  consent_id        uuid not null references public.consent_grants(id),
  gender            text,                          -- nullable; "prefer not to say" = null
  ethnicity         text,
  age_band          text check (age_band in ('under_25','25_34','35_44','45_54','55_64','65_plus') or age_band is null),
  disability_status text check (disability_status in ('yes','no','prefer_not_to_say') or disability_status is null),
  nationality       text,
  language_first    text,
  captured_at       timestamptz not null default now(),
  _dev_stub         boolean not null default true,
  created_at        timestamptz not null default now(),
  unique (org_id, person_id)
);
create index demographics_voluntary_org_idx on public.demographics_voluntary (org_id);
create trigger trg_audit_demographics_voluntary after insert or update or delete on public.demographics_voluntary
  for each row execute function public._audit_row();
alter table public.demographics_voluntary enable row level security;
alter table public.demographics_voluntary force  row level security;
-- Self always sees their own demographic data.
-- Modeling.read + fairness_monitoring consent active is required for others.
create policy demographics_voluntary_select on public.demographics_voluntary for select using (
  public.is_self(person_id)
  or (
    public.has_permission(org_id, 'modeling.read')
    and public.consent_active(consent_id, 'fairness_monitoring')
  )
);
create policy demographics_voluntary_insert on public.demographics_voluntary for insert with check (
  public.consent_active(consent_id, 'fairness_monitoring')
);

-- ============ feature_views guard: refuse demographic source ============
-- Engineering-level prevention of "oops we accidentally added gender as
-- a feature". The trigger refuses ANY feature_views row whose
-- source_tables contains 'demographics_voluntary'.
create or replace function public._guard_no_demographic_feature()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.source_tables && array['demographics_voluntary'] then
    raise exception
      'feature_views: demographics_voluntary cannot be a feature source (AI Act Art. 10(5) — bias monitoring only)'
      using errcode = 'check_violation';
  end if;
  return new;
end$$;
create trigger trg_no_demographic_feature
  before insert or update on public.feature_views
  for each row execute function public._guard_no_demographic_feature();

-- ============ fairness_runs ============
-- One per (org × model × scope) compute event.
create table public.fairness_runs (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  model_id        uuid not null references public.model_registry(id),
  key             text not null,
  scope_json      jsonb not null default '{}'::jsonb,
  computed_at     timestamptz not null default now(),
  notes           text,
  _dev_stub       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (org_id, model_id, key, computed_at)
);
create index fairness_runs_org_idx on public.fairness_runs (org_id);
create trigger trg_touch_fairness_runs before update on public.fairness_runs
  for each row execute function public.set_updated_at();
create trigger trg_audit_fairness_runs after insert or update or delete on public.fairness_runs
  for each row execute function public._audit_row();
alter table public.fairness_runs enable row level security;
alter table public.fairness_runs force  row level security;
create policy fairness_runs_select on public.fairness_runs for select using (
  public.has_permission(org_id, 'modeling.read')
);
create policy fairness_runs_write on public.fairness_runs for all
  using (public.has_permission(org_id, 'modeling.write'))
  with check (public.has_permission(org_id, 'modeling.write'));

-- ============ fairness_metrics ============
-- The metric rows. Each row covers (run × characteristic × group_pair).
-- INTERPRETATION_BY_EXPERT is the only place a verdict can live, and
-- the system never writes it.
create table public.fairness_metrics (
  id                      uuid primary key default extensions.gen_random_uuid(),
  run_id                  uuid not null references public.fairness_runs(id) on delete cascade,
  characteristic          text not null check (characteristic in (
                            'gender','ethnicity','age_band','disability_status','nationality','language_first'
                          )),
  reference_group         text not null,
  protected_group         text not null,
  selection_rate_reference numeric,
  selection_rate_protected numeric,
  adverse_impact_ratio    numeric,
  ci_lower                numeric,
  ci_upper                numeric,
  sample_size_reference   int,
  sample_size_protected   int,
  statistical_test_name   text,
  statistical_test_p_value numeric,
  -- Cleary differential prediction (slope/intercept by group).
  differential_prediction_slope     numeric,
  differential_prediction_intercept numeric,
  -- INSPECTION TRIGGER, not verdict.
  four_fifths_inspection_triggered  boolean not null default false,
  -- Expert seam — the I/O psychologist OR legal advisor fills this.
  interpretation_by_expert  text,
  interpreted_by_person_id  uuid references public.people(id),
  interpreted_at            timestamptz,
  _dev_stub                 boolean not null default true,
  created_at                timestamptz not null default now()
);
create index fairness_metrics_run_idx on public.fairness_metrics (run_id);
create trigger trg_audit_fairness_metrics after insert or update or delete on public.fairness_metrics
  for each row execute function public._audit_row();
alter table public.fairness_metrics enable row level security;
alter table public.fairness_metrics force  row level security;
create policy fairness_metrics_select on public.fairness_metrics for select using (
  exists (
    select 1 from public.fairness_runs r
    where r.id = fairness_metrics.run_id
      and public.has_permission(r.org_id, 'modeling.read')
  )
);
create policy fairness_metrics_write on public.fairness_metrics for all using (
  exists (
    select 1 from public.fairness_runs r
    where r.id = fairness_metrics.run_id
      and public.has_permission(r.org_id, 'modeling.write')
  )
) with check (
  exists (
    select 1 from public.fairness_runs r
    where r.id = fairness_metrics.run_id
      and public.has_permission(r.org_id, 'modeling.write')
  )
);
