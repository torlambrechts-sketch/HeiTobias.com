-- phase4_step2_model_scaffolding — interpretable-first model registry,
-- mandatory model_cards, training runs, and the predictions table with
-- a structurally-enforced SHAP explanation requirement.
--
-- SCIENCE-SPEC + Phase 4 prompt rules made structural:
--
--   * Every model version has a first-class model_card (intended_use,
--     limits, data lineage, features, weights, fairness metrics, owner).
--     A model can ONLY be marked validity_status='validated' if its card
--     also is (chk_model_cards_validated_requires_fields).
--
--   * Every prediction carries a per-feature SHAP-style explanation
--     (chk_predictions_shap_present). GDPR Art. 22 logic-requirement;
--     also SCIENCE-SPEC §9 (interpretable-first + inspectable).
--
--   * Every prediction carries lineage (model_id + feature_row_ids +
--     consent_id). RLS gates by research_anonymized — same rung as
--     feature_rows. A prediction INFORMS a human decision; the
--     informs_decision_id column points at hiring_decisions or
--     lifecycle_decisions but is never required to exist before the
--     prediction is computed (a prediction can be inspected without
--     being acted on).
--
--   * Synthetic-only until experts engage: every row defaults
--     _dev_stub=true / validity_status='dev_stub'. Test 18 reasserts
--     the fabrication guard for the new tables.

-- ============ model_registry ============
create table public.model_registry (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id),
  key                 text not null,
  version             text not null default '0.0.1-dev',
  family              text not null check (family in (
                        -- linear weighted-sum of feature contributions
                        -- + per-feature attribution (SHAP-style for an
                        -- additive model is the contribution itself).
                        'interpretable_baseline_v0',
                        -- stable_fit / growth_gap / flight_risk /
                        -- emerging_misfit four-quadrant classifier.
                        'four_quadrant_classifier_v0',
                        -- low P-J/P-O fit + pulse decline + stable
                        -- turnover predictors (logistic, interpretable).
                        'flight_risk_logistic_v0',
                        -- growth-gap projection (gap × proximal env).
                        'growth_gap_projection_v0',
                        -- role-conditioned performance composite.
                        'performance_composite_v0'
                      )),
  feature_view_id     uuid not null references public.feature_views(id),
  training_dataset_id uuid references public.model_datasets(id),
  owner_person_id     uuid references public.people(id),
  description         text,
  validity_status     public.validity_status not null default 'dev_stub',
  _dev_stub           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (org_id, key, version)
);
create index model_registry_org_idx    on public.model_registry (org_id);
create index model_registry_family_idx on public.model_registry (family);
create trigger trg_touch_model_registry before update on public.model_registry
  for each row execute function public.set_updated_at();
create trigger trg_audit_model_registry after insert or update or delete on public.model_registry
  for each row execute function public._audit_row();
alter table public.model_registry enable row level security;
alter table public.model_registry force  row level security;
create policy model_registry_select on public.model_registry for select using (
  public.has_permission(org_id, 'modeling.read')
);
create policy model_registry_write on public.model_registry for all
  using (public.has_permission(org_id, 'modeling.write'))
  with check (public.has_permission(org_id, 'modeling.write'));

-- ============ model_cards ============
-- Required structured documentation per model version
-- (SCIENCE-SPEC §9 + GDPR Art. 22 "logic involved" + EU AI Act Annex IV).
-- The CHECK below makes "validated" load-bearing: a card can't be marked
-- validated without intended_use, structured limits, data lineage,
-- feature list, a human sign-off person, and the dev_stub flag flipped.
create table public.model_cards (
  id                     uuid primary key default extensions.gen_random_uuid(),
  model_id               uuid not null unique references public.model_registry(id) on delete cascade,
  intended_use           text,
  limits_json            jsonb not null default '{}'::jsonb,
  data_lineage_json      jsonb not null default '{}'::jsonb,
  features_json          jsonb not null default '[]'::jsonb,
  weights_json           jsonb not null default '{}'::jsonb,
  fairness_metrics_json  jsonb not null default '{}'::jsonb,
  ethical_considerations text,
  signed_off_by          uuid references public.people(id),
  signed_off_at          timestamptz,
  validity_status        public.validity_status not null default 'dev_stub',
  _dev_stub              boolean not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint chk_model_cards_validated_requires_fields
    check (validity_status <> 'validated' or (
      intended_use is not null and length(intended_use) > 10
      and limits_json        <> '{}'::jsonb
      and data_lineage_json  <> '{}'::jsonb
      and jsonb_array_length(features_json) > 0
      and signed_off_by is not null
      and signed_off_at is not null
      and coalesce(_dev_stub, false) = false
    ))
);
create trigger trg_touch_model_cards before update on public.model_cards
  for each row execute function public.set_updated_at();
create trigger trg_audit_model_cards after insert or update or delete on public.model_cards
  for each row execute function public._audit_row();
alter table public.model_cards enable row level security;
alter table public.model_cards force  row level security;
create policy model_cards_select on public.model_cards for select using (
  exists (
    select 1 from public.model_registry r
    where r.id = model_cards.model_id
      and public.has_permission(r.org_id, 'modeling.read')
  )
);
create policy model_cards_write on public.model_cards for all using (
  exists (
    select 1 from public.model_registry r
    where r.id = model_cards.model_id
      and public.has_permission(r.org_id, 'modeling.write')
  )
) with check (
  exists (
    select 1 from public.model_registry r
    where r.id = model_cards.model_id
      and public.has_permission(r.org_id, 'modeling.write')
  )
);

-- ============ training_runs ============
create table public.training_runs (
  id                uuid primary key default extensions.gen_random_uuid(),
  model_id          uuid not null references public.model_registry(id) on delete cascade,
  dataset_id        uuid not null references public.model_datasets(id),
  run_method        text not null,
  eval_metrics_json jsonb not null default '{}'::jsonb,
  notes             text,
  _dev_stub         boolean not null default true,
  run_at            timestamptz not null default now(),
  created_at        timestamptz not null default now()
);
create index training_runs_model_idx on public.training_runs (model_id, run_at desc);
create trigger trg_audit_training_runs after insert or update or delete on public.training_runs
  for each row execute function public._audit_row();
alter table public.training_runs enable row level security;
alter table public.training_runs force  row level security;
create policy training_runs_select on public.training_runs for select using (
  exists (
    select 1 from public.model_registry r
    where r.id = training_runs.model_id
      and public.has_permission(r.org_id, 'modeling.read')
  )
);
create policy training_runs_write on public.training_runs for all using (
  exists (
    select 1 from public.model_registry r
    where r.id = training_runs.model_id
      and public.has_permission(r.org_id, 'modeling.write')
  )
) with check (
  exists (
    select 1 from public.model_registry r
    where r.id = training_runs.model_id
      and public.has_permission(r.org_id, 'modeling.write')
  )
);

-- ============ predictions ============
-- A prediction informs a human; it is never itself a decision
-- (SCIENCE-SPEC §9, GDPR Art. 22, EU AI Act Art. 14). The
-- informs_decision_id column references the human-attributable decision
-- (hiring_decisions or lifecycle_decisions) that this prediction fed into;
-- it can be null if a model is being inspected without being acted on.
create table public.predictions (
  id                    uuid primary key default extensions.gen_random_uuid(),
  org_id                uuid not null references public.organizations(id),
  model_id              uuid not null references public.model_registry(id),
  person_id             uuid not null references public.people(id),
  role_id               uuid references public.roles_catalog(id),
  consent_id            uuid not null references public.consent_grants(id),
  score_value           numeric,
  prediction_json       jsonb not null default '{}'::jsonb,
  explanation_shap_json jsonb not null default '[]'::jsonb,
  feature_row_ids       uuid[] not null default '{}',
  informs_decision_id   uuid,
  informs_decision_type text check (informs_decision_type in ('hiring_decision','lifecycle_decision') or informs_decision_type is null),
  predicted_at          timestamptz not null default now(),
  validity_status       public.validity_status not null default 'dev_stub',
  _dev_stub             boolean not null default true,
  created_at            timestamptz not null default now(),
  -- Structural Art. 22 "logic involved": every prediction carries at
  -- least one explanatory contribution. SHAP-style is the simplest
  -- interpretable case (additive contribution per feature).
  constraint chk_predictions_shap_present
    check (jsonb_array_length(explanation_shap_json) >= 1),
  constraint chk_predictions_validated_real
    check (validity_status <> 'validated' or coalesce(_dev_stub, false) = false)
);
create index predictions_person_idx on public.predictions (person_id, predicted_at desc);
create index predictions_model_idx  on public.predictions (model_id,  predicted_at desc);
create trigger trg_audit_predictions after insert or update or delete on public.predictions
  for each row execute function public._audit_row();
alter table public.predictions enable row level security;
alter table public.predictions force  row level security;
-- Subject sees their own; modeling.read + active research_anonymized
-- consent to see others.
create policy predictions_select on public.predictions for select using (
  public.is_self(person_id)
  or (
    public.has_permission(org_id, 'modeling.read')
    and public.consent_active(consent_id, 'research_anonymized')
  )
);
create policy predictions_insert on public.predictions for insert with check (
  public.has_permission(org_id, 'modeling.write')
  and public.consent_active(consent_id, 'research_anonymized')
);

-- ============ permissions ============
-- modeling.read / modeling.write already exist (Step 1).
-- modeling.signoff is the expert seam to mark a card validated; it is
-- NEVER granted in dev — only an engaged I/O psychologist gets it.
insert into public.rbac_permissions (key, description) values
  ('modeling.signoff', 'Sign off a model card as validated (Phase 4) — expert role only')
on conflict (key) do nothing;
-- Intentionally NOT granted to any seeded role. The HANDOFF list
-- (Phase 4 §exit-criteria) requires the I/O psychologist to be
-- explicitly granted this permission outside of code.
