-- H-6 — Differential Prediction + Power (Run 8 of H-1..H-10)
--
-- Berry 2015 (Industrial-Organizational Psychology): the original
-- "differential prediction" framework focused on whether a regression
-- equation fit on one group OVER-predicts performance of the other
-- group when applied unchanged. The empirical finding is that
-- cognitive-ability tests systematically OVER-predict performance of
-- minority subgroups, not under-predict — the OPPOSITE direction of
-- bias most lay-audiences expect. This is critical for hiring fairness
-- argumentation.
--
-- Aguinis, Culpepper & Pierce 2010 critiqued the power of decades of
-- differential-prediction studies: the standard test for differential
-- intercepts requires substantially larger samples than commonly
-- reported. A "null result" with low power is uninformative.
--
-- The existing fairness_* tables already capture AIR, selection rates,
-- and slope/intercept of differential prediction. This run adds:
--   * validity_status on both tables (was only _dev_stub)
--   * engine + engine_version on fairness_runs
--   * power_estimate + power_caveat on fairness_runs
--   * slope_test_p_value, intercept_test_p_value on fairness_metrics
--   * over_prediction_flag (Berry 2015 direction)
--   * sample_size_total (sanity check vs reference+protected)
--   * RPC rpc_fairness_run_signoff (modeling.signoff in run.org)

alter table public.fairness_runs
  add column if not exists validity_status   public.validity_status not null default 'dev_stub',
  add column if not exists engine            text,
  add column if not exists engine_version    text,
  add column if not exists power_estimate    numeric(4,3),
  add column if not exists power_caveat      text,
  add column if not exists signoff_actor_id  uuid references public.people(id),
  add column if not exists signoff_at        timestamptz,
  add column if not exists signoff_rationale text;

alter table public.fairness_runs
  drop constraint if exists fr_engine_enum,
  drop constraint if exists fr_power_in_unit,
  drop constraint if exists fr_signoff_rationale_len,
  drop constraint if exists fr_validated_requires_signoff;

alter table public.fairness_runs
  add constraint fr_engine_enum check (
    engine is null or engine in ('fairlearn-py','aif360-py','custom','none')),
  add constraint fr_power_in_unit check (
    power_estimate is null or (power_estimate >= 0 and power_estimate <= 1)),
  add constraint fr_signoff_rationale_len check (
    signoff_rationale is null or length(signoff_rationale) >= 100),
  add constraint fr_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and power_estimate is not null
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    ));

create index if not exists fr_status_idx on public.fairness_runs(validity_status);

alter table public.fairness_metrics
  add column if not exists validity_status         public.validity_status not null default 'dev_stub',
  add column if not exists slope_test_p_value      numeric,
  add column if not exists intercept_test_p_value  numeric,
  add column if not exists over_prediction_flag    boolean,
  add column if not exists under_prediction_flag   boolean,
  add column if not exists sample_size_total       int,
  add column if not exists effect_size_cohen_d     numeric,
  add column if not exists notes                   text;

alter table public.fairness_metrics
  drop constraint if exists fm_air_in_unit,
  drop constraint if exists fm_sample_size_positive,
  drop constraint if exists fm_slope_p_in_unit,
  drop constraint if exists fm_intercept_p_in_unit,
  drop constraint if exists fm_interp_enum;

alter table public.fairness_metrics
  add constraint fm_air_in_unit check (
    adverse_impact_ratio is null or (adverse_impact_ratio >= 0 and adverse_impact_ratio <= 5)),
  add constraint fm_sample_size_positive check (
    (sample_size_reference is null or sample_size_reference > 0)
    and (sample_size_protected is null or sample_size_protected > 0)
    and (sample_size_total is null or sample_size_total > 0)),
  add constraint fm_slope_p_in_unit check (
    slope_test_p_value is null or (slope_test_p_value >= 0 and slope_test_p_value <= 1)),
  add constraint fm_intercept_p_in_unit check (
    intercept_test_p_value is null or (intercept_test_p_value >= 0 and intercept_test_p_value <= 1)),
  add constraint fm_interp_enum check (
    interpretation_by_expert is null or interpretation_by_expert in (
      'no_concern','monitor','remediate','do_not_use','inconclusive'));

create index if not exists fm_status_idx on public.fairness_metrics(validity_status);
create index if not exists fm_overpredict_idx on public.fairness_metrics(over_prediction_flag) where over_prediction_flag = true;

-- Helper: AIR pass/fail per 4/5ths rule + significance + power flag
create or replace function public.fairness_summarize_air(
  p_air            numeric,
  p_p_value        numeric,
  p_power_estimate numeric
) returns jsonb language plpgsql immutable set search_path = '' as $$
declare v jsonb := '{}'::jsonb;
begin
  if p_air is null then return v; end if;
  v := jsonb_build_object(
    'air',                       p_air,
    'passes_four_fifths',        p_air >= 0.80,
    'statistically_significant', (p_p_value is not null and p_p_value < 0.05),
    'low_power_caveat',          (p_power_estimate is not null and p_power_estimate < 0.80)
  );
  return v;
end;
$$;

revoke all on function public.fairness_summarize_air(numeric, numeric, numeric) from public;
grant execute on function public.fairness_summarize_air(numeric, numeric, numeric) to authenticated, service_role;

comment on function public.fairness_summarize_air(numeric, numeric, numeric) is
  'Returns jsonb summarizing AIR vs 4/5ths rule + sig + power caveat. Aguinis 2010: a non-significant result with power < 0.80 is uninformative.';

create or replace function public.rpc_fairness_run_signoff(
  p_run_id             uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_caller_person_id uuid;
  v_row              public.fairness_runs%rowtype;
  v_n_metrics        int;
  v_n_unreviewed     int;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.fairness_runs where id = p_run_id for update;
  if not found then
    raise exception 'fairness_run % not found', p_run_id using errcode='P0002';
  end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;
  if v_row.power_estimate is null then
    raise exception 'cannot sign off run without power_estimate (Aguinis 2010 — low-power results uninformative)'
      using errcode='22023';
  end if;

  -- Every metric must have an expert interpretation before sign-off
  select count(*), count(*) filter (where interpretation_by_expert is null)
    into v_n_metrics, v_n_unreviewed
    from public.fairness_metrics where run_id = p_run_id;
  if v_n_metrics = 0 then
    raise exception 'cannot sign off run with 0 metric rows' using errcode='22023';
  end if;
  if v_n_unreviewed > 0 then
    raise exception 'cannot sign off run: % of % metrics lack expert interpretation',
      v_n_unreviewed, v_n_metrics using errcode='22023';
  end if;

  update public.fairness_runs
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_run_id;
  update public.fairness_metrics
     set validity_status='validated', _dev_stub=false
   where run_id = p_run_id;

  perform public.audit_log_event(
    v_row.org_id, 'fairness_run.signoff', 'fairness_run', p_run_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'engine', v_row.engine, 'power_estimate', v_row.power_estimate,
      'n_metrics', v_n_metrics), null);

  return jsonb_build_object('ok', true, 'run_id', p_run_id,
    'validity_status', 'validated', 'n_metrics_validated', v_n_metrics,
    'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_fairness_run_signoff(uuid, text) from public;
grant execute on function public.rpc_fairness_run_signoff(uuid, text) to authenticated, service_role;
