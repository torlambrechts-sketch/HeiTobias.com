-- phase4_step5_invariance_norms — Nordic norms + measurement-invariance
-- + DIF data model. SCIENCE-SPEC §11 + Phase 4 prompt §5.
--
-- Two load-bearing rules:
--
--   * SYNTHETIC ONLY until the I/O psychologist plugs real norm data.
--     Every row defaults _dev_stub=true. chk_norm_samples_validated_requires_real
--     refuses validity_status='validated' unless sample_n>=100 AND
--     _dev_stub=false.
--
--   * VERDICTS ARE EXPERT-OWNED. invariance_results carries the
--     computed statistics (CFI, RMSEA, SRMR, deltas) but
--     invariance_verdict_by_expert is NULL on insert. Only
--     invariance_verdict_record (modeling.signoff gated) can fill it.
--     Same shape for dif_items.expert_review_note.

-- Tables: norm_samples + norm_percentiles + invariance_runs +
-- invariance_results + dif_runs + dif_items. See applied migration.

create table public.norm_samples (
  id               uuid primary key default extensions.gen_random_uuid(),
  org_id           uuid references public.organizations(id),
  instrument_key   text not null,
  country_code     text not null check (length(country_code) = 2),
  language_code    text not null check (language_code in ('nb','nn','sv','da','en')),
  sample_n         int,
  sample_period_start date,
  sample_period_end   date,
  collection_source text,
  notes            text,
  validity_status  public.validity_status not null default 'dev_stub',
  _dev_stub        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (instrument_key, country_code, language_code, sample_period_start),
  constraint chk_norm_samples_validated_requires_real
    check (validity_status <> 'validated' or (sample_n is not null and sample_n >= 100 and coalesce(_dev_stub, false) = false))
);
create trigger trg_touch_norm_samples before update on public.norm_samples for each row execute function public.set_updated_at();
create trigger trg_audit_norm_samples after insert or update or delete on public.norm_samples for each row execute function public._audit_row();
alter table public.norm_samples enable row level security;
alter table public.norm_samples force row level security;
create policy norm_samples_select on public.norm_samples for select using (
  org_id is null or public.has_permission(org_id, 'modeling.read')
);
create policy norm_samples_write on public.norm_samples for all
  using (org_id is null or public.has_permission(org_id, 'modeling.write'))
  with check (org_id is null or public.has_permission(org_id, 'modeling.write'));

create table public.norm_percentiles (
  id            uuid primary key default extensions.gen_random_uuid(),
  sample_id     uuid not null references public.norm_samples(id) on delete cascade,
  trait_key     text not null,
  percentile_5  numeric,
  percentile_25 numeric,
  percentile_50 numeric,
  percentile_75 numeric,
  percentile_95 numeric,
  mean          numeric,
  sd            numeric,
  _dev_stub     boolean not null default true,
  unique (sample_id, trait_key)
);
create index norm_percentiles_sample_idx on public.norm_percentiles (sample_id);
alter table public.norm_percentiles enable row level security;
alter table public.norm_percentiles force row level security;
create policy norm_percentiles_select on public.norm_percentiles for select using (
  exists (select 1 from public.norm_samples s where s.id = norm_percentiles.sample_id
          and (s.org_id is null or public.has_permission(s.org_id, 'modeling.read')))
);
create policy norm_percentiles_write on public.norm_percentiles for all using (
  exists (select 1 from public.norm_samples s where s.id = norm_percentiles.sample_id
          and (s.org_id is null or public.has_permission(s.org_id, 'modeling.write')))
) with check (
  exists (select 1 from public.norm_samples s where s.id = norm_percentiles.sample_id
          and (s.org_id is null or public.has_permission(s.org_id, 'modeling.write')))
);

create table public.invariance_runs (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid references public.organizations(id),
  instrument_key  text not null,
  scope_json      jsonb not null default '{}'::jsonb,
  computed_at     timestamptz not null default now(),
  notes           text,
  _dev_stub       boolean not null default true,
  created_at      timestamptz not null default now()
);
create index invariance_runs_org_idx on public.invariance_runs (org_id);
create trigger trg_audit_invariance_runs after insert or update or delete on public.invariance_runs for each row execute function public._audit_row();
alter table public.invariance_runs enable row level security;
alter table public.invariance_runs force row level security;
create policy invariance_runs_select on public.invariance_runs for select using (
  org_id is null or public.has_permission(org_id, 'modeling.read')
);
create policy invariance_runs_write on public.invariance_runs for all
  using (org_id is null or public.has_permission(org_id, 'modeling.write'))
  with check (org_id is null or public.has_permission(org_id, 'modeling.write'));

create table public.invariance_results (
  id                       uuid primary key default extensions.gen_random_uuid(),
  run_id                   uuid not null references public.invariance_runs(id) on delete cascade,
  level                    text not null check (level in ('configural','metric','scalar')),
  comparison_groups_json   jsonb not null default '{}'::jsonb,
  cfi                      numeric,
  rmsea                    numeric,
  srmr                     numeric,
  delta_cfi_vs_prior_level numeric,
  delta_rmsea_vs_prior_level numeric,
  invariance_verdict_by_expert text,
  verdict_by_person_id     uuid references public.people(id),
  verdict_at               timestamptz,
  _dev_stub                boolean not null default true,
  created_at               timestamptz not null default now(),
  unique (run_id, level)
);
create index invariance_results_run_idx on public.invariance_results (run_id);
create trigger trg_audit_invariance_results after insert or update or delete on public.invariance_results for each row execute function public._audit_row();
alter table public.invariance_results enable row level security;
alter table public.invariance_results force row level security;
create policy invariance_results_select on public.invariance_results for select using (
  exists (select 1 from public.invariance_runs r where r.id = invariance_results.run_id
          and (r.org_id is null or public.has_permission(r.org_id, 'modeling.read')))
);
create policy invariance_results_write on public.invariance_results for all using (
  exists (select 1 from public.invariance_runs r where r.id = invariance_results.run_id
          and (r.org_id is null or public.has_permission(r.org_id, 'modeling.write')))
) with check (
  exists (select 1 from public.invariance_runs r where r.id = invariance_results.run_id
          and (r.org_id is null or public.has_permission(r.org_id, 'modeling.write')))
);

create table public.dif_runs (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid references public.organizations(id),
  instrument_key  text not null,
  reference_group text not null,
  focal_group     text not null,
  method          text not null check (method in ('mh','logistic','irt','lord_chi_square')),
  computed_at     timestamptz not null default now(),
  notes           text,
  _dev_stub       boolean not null default true,
  created_at      timestamptz not null default now()
);
create trigger trg_audit_dif_runs after insert or update or delete on public.dif_runs for each row execute function public._audit_row();
alter table public.dif_runs enable row level security;
alter table public.dif_runs force row level security;
create policy dif_runs_select on public.dif_runs for select using (
  org_id is null or public.has_permission(org_id, 'modeling.read')
);
create policy dif_runs_write on public.dif_runs for all
  using (org_id is null or public.has_permission(org_id, 'modeling.write'))
  with check (org_id is null or public.has_permission(org_id, 'modeling.write'));

create table public.dif_items (
  id                  uuid primary key default extensions.gen_random_uuid(),
  run_id              uuid not null references public.dif_runs(id) on delete cascade,
  item_key            text not null,
  effect_size         numeric,
  p_value             numeric,
  flagged_for_review  boolean not null default false,
  expert_review_note  text,
  reviewed_by_person_id uuid references public.people(id),
  reviewed_at         timestamptz,
  _dev_stub           boolean not null default true,
  unique (run_id, item_key)
);
create trigger trg_audit_dif_items after insert or update or delete on public.dif_items for each row execute function public._audit_row();
alter table public.dif_items enable row level security;
alter table public.dif_items force row level security;
create policy dif_items_select on public.dif_items for select using (
  exists (select 1 from public.dif_runs r where r.id = dif_items.run_id
          and (r.org_id is null or public.has_permission(r.org_id, 'modeling.read')))
);
create policy dif_items_write on public.dif_items for all using (
  exists (select 1 from public.dif_runs r where r.id = dif_items.run_id
          and (r.org_id is null or public.has_permission(r.org_id, 'modeling.write')))
) with check (
  exists (select 1 from public.dif_runs r where r.id = dif_items.run_id
          and (r.org_id is null or public.has_permission(r.org_id, 'modeling.write')))
);
