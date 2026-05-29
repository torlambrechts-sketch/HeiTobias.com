-- phase4_step3_pareto_curve — Pareto validity-diversity weighting curve
-- (De Corte 2007; Song 2017/2023). SCIENCE-SPEC §10.
--
-- A trade-off exposed as a CURVE the customer chooses a point on. The
-- default is the neutral midpoint (neither extreme); the chosen point
-- is logged with attribution + rationale so the customer's tuning is
-- defensible under EU AI Act Art. 12 (record-keeping) and the audit
-- demands of *Mobley v. Workday*.
--
-- DEV STUB: the curve is computed from a synthetic linear trade-off
-- between weight_validity (the customer dial) and the two outcomes
-- (predicted_validity, predicted_air). Real math lands when the I/O
-- psychologist plugs validated estimators. Engine shape — curve +
-- chosen point + attribution + audit — is what's load-bearing.

-- ============ pareto_curves ============
-- One row per computed curve. A curve is computed against a
-- (feature_view, optional model) and a chosen regularization lambda.
create table public.pareto_curves (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id),
  feature_view_id     uuid not null references public.feature_views(id),
  model_id            uuid references public.model_registry(id),
  key                 text not null,
  regularization_lambda numeric not null default 0.0
                        check (regularization_lambda >= 0 and regularization_lambda <= 1),
  default_weight_validity numeric not null default 0.5
                          check (default_weight_validity > 0 and default_weight_validity < 1),
  computed_at         timestamptz not null default now(),
  notes               text,
  validity_status     public.validity_status not null default 'dev_stub',
  _dev_stub           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  -- The DEFAULT prioritizes neither extreme — structurally.
  constraint chk_pareto_default_not_extreme
    check (default_weight_validity > 0.05 and default_weight_validity < 0.95),
  unique (org_id, key, computed_at)
);
create index pareto_curves_org_idx on public.pareto_curves (org_id);
create trigger trg_touch_pareto_curves before update on public.pareto_curves
  for each row execute function public.set_updated_at();
create trigger trg_audit_pareto_curves after insert or update or delete on public.pareto_curves
  for each row execute function public._audit_row();
alter table public.pareto_curves enable row level security;
alter table public.pareto_curves force  row level security;
create policy pareto_curves_select on public.pareto_curves for select using (
  public.has_permission(org_id, 'modeling.read')
);
create policy pareto_curves_write on public.pareto_curves for all
  using (public.has_permission(org_id, 'modeling.write'))
  with check (public.has_permission(org_id, 'modeling.write'));

-- ============ pareto_curve_points ============
-- Individual points along the curve. ordered_index lets the UI render
-- the line without sorting in app code.
create table public.pareto_curve_points (
  id                       uuid primary key default extensions.gen_random_uuid(),
  curve_id                 uuid not null references public.pareto_curves(id) on delete cascade,
  ordered_index            int not null,
  weight_validity          numeric not null check (weight_validity >= 0 and weight_validity <= 1),
  predicted_validity       numeric,                       -- a DEV-STUB number; nullable in case the synthetic emit can't compute
  predicted_air            numeric,                       -- adverse-impact ratio (selection_rate_protected / selection_rate_reference)
  predicted_selection_rate numeric,
  is_default_point         boolean not null default false,
  _dev_stub                boolean not null default true,
  unique (curve_id, ordered_index)
);
create index pareto_curve_points_curve_idx on public.pareto_curve_points (curve_id, ordered_index);
alter table public.pareto_curve_points enable row level security;
alter table public.pareto_curve_points force  row level security;
create policy pareto_curve_points_select on public.pareto_curve_points for select using (
  exists (
    select 1 from public.pareto_curves c
    where c.id = pareto_curve_points.curve_id
      and public.has_permission(c.org_id, 'modeling.read')
  )
);
create policy pareto_curve_points_write on public.pareto_curve_points for all using (
  exists (
    select 1 from public.pareto_curves c
    where c.id = pareto_curve_points.curve_id
      and public.has_permission(c.org_id, 'modeling.write')
  )
) with check (
  exists (
    select 1 from public.pareto_curves c
    where c.id = pareto_curve_points.curve_id
      and public.has_permission(c.org_id, 'modeling.write')
  )
);

-- ============ pareto_weight_choices ============
-- The customer's chosen point. Attribution + rationale are required at
-- INSERT time — pareto_weight_choose enforces it.
create table public.pareto_weight_choices (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id),
  curve_id            uuid not null references public.pareto_curves(id) on delete cascade,
  chosen_weight_validity numeric not null check (chosen_weight_validity >= 0 and chosen_weight_validity <= 1),
  chosen_by_person_id uuid not null references public.people(id),
  chosen_at           timestamptz not null default now(),
  rationale           text not null check (length(rationale) > 20),
  applies_to_model_id uuid references public.model_registry(id),
  _dev_stub           boolean not null default true,
  created_at          timestamptz not null default now()
);
create index pareto_weight_choices_curve_idx on public.pareto_weight_choices (curve_id, chosen_at desc);
create trigger trg_audit_pareto_weight_choices after insert or update or delete on public.pareto_weight_choices
  for each row execute function public._audit_row();
alter table public.pareto_weight_choices enable row level security;
alter table public.pareto_weight_choices force  row level security;
create policy pareto_weight_choices_select on public.pareto_weight_choices for select using (
  public.has_permission(org_id, 'modeling.read')
);
create policy pareto_weight_choices_write on public.pareto_weight_choices for all
  using (public.has_permission(org_id, 'modeling.write'))
  with check (public.has_permission(org_id, 'modeling.write'));
