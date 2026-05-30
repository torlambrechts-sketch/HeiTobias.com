-- H-5 — DIF Harness (Run 7 of H-1..H-10)
--
-- Differential Item Functioning: a single item behaves differently
-- for two demographic groups even when overall trait level is held
-- constant. Standard methods:
--   * Mantel-Haenszel (MH) χ²+ effect-size classification A/B/C
--   * Logistic Regression (uniform + non-uniform DIF p-values)
--   * IRT-based (Lord's χ², Raju area measures)
--
-- The existing dif_runs / dif_items schema captures method + effect_size
-- + p_value + flagged_for_review at item granularity. This run extends
-- them with the per-method specifics + validity_status seam so a DIF
-- analysis can be promoted to validated only after the expert reviews
-- every flagged item.
--
-- INFRASTRUCTURE ONLY: no DIF analyses computed. The R/Python service
-- producing the statistics is operator-side. Schema accepts results.

-- ─── 1. Extend dif_runs ──────────────────────────────────────────────
alter table public.dif_runs
  add column if not exists validity_status   public.validity_status not null default 'dev_stub',
  add column if not exists engine            text,
  add column if not exists engine_version    text,
  add column if not exists reference_group_n int,
  add column if not exists focal_group_n     int,
  add column if not exists alpha_threshold   numeric(4,3),
  add column if not exists multiple_comparison_adjustment text,
  add column if not exists signoff_actor_id  uuid references public.people(id),
  add column if not exists signoff_at        timestamptz,
  add column if not exists signoff_rationale text;

alter table public.dif_runs
  drop constraint if exists dr_method_enum,
  drop constraint if exists dr_engine_enum,
  drop constraint if exists dr_alpha_in_unit,
  drop constraint if exists dr_mc_adj_enum,
  drop constraint if exists dr_signoff_rationale_len,
  drop constraint if exists dr_validated_requires_signoff,
  drop constraint if exists dr_group_n_positive;

-- Pre-existing dif_runs_method_check used short aliases (mh / logistic /
-- irt / lord_chi_square); we widen to accept BOTH so we don't break
-- back-compat for any consumers using the short forms.
alter table public.dif_runs drop constraint if exists dif_runs_method_check;
alter table public.dif_runs
  add constraint dr_method_enum check (
    method is null or method in (
      'mantel_haenszel','logistic_regression','irt_lord','irt_raju','simultaneous',
      'mh','logistic','irt','lord_chi_square')),
  add constraint dr_engine_enum check (
    engine is null or engine in ('difr-r','mirt-r','lordif-r','psychometric-py','custom')),
  add constraint dr_alpha_in_unit check (
    alpha_threshold is null or (alpha_threshold > 0 and alpha_threshold < 1)),
  add constraint dr_mc_adj_enum check (
    multiple_comparison_adjustment is null or multiple_comparison_adjustment in (
      'none','bonferroni','holm','bh_fdr','by_fdr')),
  add constraint dr_group_n_positive check (
    (reference_group_n is null or reference_group_n > 0)
    and (focal_group_n is null or focal_group_n > 0)),
  add constraint dr_signoff_rationale_len check (
    signoff_rationale is null or length(signoff_rationale) >= 100),
  add constraint dr_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and engine is not null
      and method is not null
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    ));

create index if not exists dr_status_idx on public.dif_runs(validity_status);

-- ─── 2. Extend dif_items ─────────────────────────────────────────────
alter table public.dif_items
  add column if not exists validity_status   public.validity_status not null default 'dev_stub',
  add column if not exists mh_dif_classification text,    -- 'A' (negligible) | 'B' (moderate) | 'C' (large)
  add column if not exists lr_uniform_dif_p   numeric,
  add column if not exists lr_nonuniform_dif_p numeric,
  add column if not exists irt_dif_chi_square numeric,
  add column if not exists irt_dif_p          numeric,
  add column if not exists p_value_adjusted   numeric,    -- after multiple-comparison correction
  add column if not exists bias_review_required boolean   not null default false;

alter table public.dif_items
  drop constraint if exists di_class_enum,
  drop constraint if exists di_p_in_unit,
  drop constraint if exists di_lru_in_unit,
  drop constraint if exists di_lrn_in_unit,
  drop constraint if exists di_irtp_in_unit;

alter table public.dif_items
  add constraint di_class_enum check (
    mh_dif_classification is null or mh_dif_classification in ('A','B','C')),
  add constraint di_p_in_unit check (
    p_value is null or (p_value >= 0 and p_value <= 1)),
  add constraint di_lru_in_unit check (
    lr_uniform_dif_p is null or (lr_uniform_dif_p >= 0 and lr_uniform_dif_p <= 1)),
  add constraint di_lrn_in_unit check (
    lr_nonuniform_dif_p is null or (lr_nonuniform_dif_p >= 0 and lr_nonuniform_dif_p <= 1)),
  add constraint di_irtp_in_unit check (
    irt_dif_p is null or (irt_dif_p >= 0 and irt_dif_p <= 1));

create index if not exists di_class_idx on public.dif_items(mh_dif_classification);
create index if not exists di_review_idx on public.dif_items(bias_review_required) where bias_review_required = true;

-- ─── 3. Helper: classify an item by MH chi-square + effect size ──────
-- The "ETS" rule: |delta_mh| < 1.0 → A, < 1.5 → B (with significant chi²),
-- ≥ 1.5 → C. We expose this as a pure function so ingestion can pre-
-- compute the classification.
create or replace function public.dif_classify_mh(
  p_effect_size numeric,         -- delta-MH (log-odds * -2.35)
  p_p_value     numeric           -- chi-square p
) returns text language plpgsql immutable set search_path = '' as $$
begin
  if p_effect_size is null then return null; end if;
  if abs(p_effect_size) < 1.0 then return 'A'; end if;
  if abs(p_effect_size) < 1.5 then
    if p_p_value is null or p_p_value < 0.05 then return 'B'; else return 'A'; end if;
  end if;
  return 'C';
end;
$$;

revoke all on function public.dif_classify_mh(numeric, numeric) from public;
grant execute on function public.dif_classify_mh(numeric, numeric) to authenticated, service_role;

comment on function public.dif_classify_mh(numeric, numeric) is
  'ETS delta-MH classification: A (negligible) / B (moderate, significant chi²) / C (large). Pure, immutable. Ingestion pipeline should pre-populate dif_items.mh_dif_classification with this output.';

-- ─── 4. Trigger: bias_review_required derives from classification ────
-- A=negligible → false. B or C → true. Expert may override.
create or replace function public._dif_set_bias_review_required()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Only auto-derive on insert or when classification changes; preserve
  -- explicit FALSE if reviewer cleared it.
  if (TG_OP = 'INSERT')
     or (new.mh_dif_classification is distinct from old.mh_dif_classification) then
    new.bias_review_required := (new.mh_dif_classification in ('B','C'));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_dif_set_review on public.dif_items;
create trigger trg_dif_set_review
  before insert or update of mh_dif_classification on public.dif_items
  for each row execute function public._dif_set_bias_review_required();

-- ─── 5. RPC: sign off a DIF run ─────────────────────────────────────
create or replace function public.rpc_dif_run_signoff(
  p_run_id             uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_caller_person_id uuid;
  v_row              public.dif_runs%rowtype;
  v_n_items          int;
  v_n_unreviewed     int;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;

  select * into v_row from public.dif_runs where id = p_run_id for update;
  if not found then
    raise exception 'dif_run % not found', p_run_id using errcode='P0002';
  end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;
  if v_row.engine is null or v_row.method is null then
    raise exception 'cannot sign off run without engine + method metadata' using errcode='22023';
  end if;

  -- Every item flagged for review must have a reviewer note before sign-off
  select count(*) filter (where bias_review_required = true),
         count(*) filter (where bias_review_required = true and reviewed_by_person_id is null)
    into v_n_items, v_n_unreviewed
    from public.dif_items where run_id = p_run_id;
  if v_n_unreviewed > 0 then
    raise exception 'cannot sign off run: % of % flagged items lack expert review',
      v_n_unreviewed, v_n_items using errcode='22023';
  end if;

  update public.dif_runs
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale
   where id = p_run_id;

  update public.dif_items
     set validity_status='validated', _dev_stub=false
   where run_id = p_run_id;

  perform public.audit_log_event(
    v_row.org_id, 'dif_run.signoff', 'dif_run', p_run_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'engine', v_row.engine, 'method', v_row.method,
      'n_flagged_items', v_n_items), null);

  return jsonb_build_object('ok', true, 'run_id', p_run_id,
    'validity_status', 'validated', 'n_flagged_items', v_n_items,
    'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_dif_run_signoff(uuid, text) from public;
grant execute on function public.rpc_dif_run_signoff(uuid, text) to authenticated, service_role;
