-- H-3 — Pareto Adverse-Impact + Shrinkage Corrections (Run 5 of H-1..H-10)
--
-- De Corte 2007 introduced the Pareto frontier between selection
-- quality (predicted validity) and adverse impact (AIR / 4-5ths rule).
-- Song 2017 showed that the optimal weights chosen from a sample do
-- NOT generalize — there is a substantial "diversity shrinkage" when
-- those weights are applied out-of-sample. Song 2023 replicated this
-- and introduced shrinkage-correction methods. Aguinis 2010
-- separately critiqued the power assumptions behind much of this
-- literature: small samples cannot detect the small effects we care
-- about, so an uncross-validated Pareto frontier is a hypothesis,
-- not a finding.
--
-- This run extends the existing pareto_* tables with:
--   * cross-validation metadata on pareto_curves (is_cross_validated,
--     cv_fold_count, cv_method, sample_size, power_estimate,
--     power_caveat, shrinkage_estimate)
--   * uncertainty intervals on pareto_curve_points (cv_predicted_*
--     lower/upper)
--   * the sign-off seam on pareto_weight_choices (validity_status,
--     signoff_actor_id, signoff_at, signoff_rationale)
--   * CHECK constraints that make "validated" load-bearing:
--     a curve can only be promoted to validated if it was
--     cross-validated AND has a power estimate AND has the standard
--     signoff metadata
--   * RPCs rpc_pareto_curve_signoff + rpc_pareto_weight_choice_signoff
--
-- INFRASTRUCTURE ONLY: no real Pareto curves computed. No values for
-- power_estimate / shrinkage_estimate seeded. The schema accepts and
-- audits these fields; producing them is a future per-org compute job
-- (and an expert-validated one — Aguinis 2010 says we should not
-- trust frontiers from samples below the power threshold).

-- ─── 1. Extend pareto_curves ────────────────────────────────────────
alter table public.pareto_curves
  add column if not exists is_cross_validated boolean      not null default false,
  add column if not exists cv_fold_count      smallint,
  add column if not exists cv_method          text,
  add column if not exists sample_size        int,
  add column if not exists power_estimate     numeric(4,3),
  add column if not exists power_caveat       text,
  add column if not exists shrinkage_estimate numeric(5,4),
  add column if not exists signoff_actor_id   uuid references public.people(id),
  add column if not exists signoff_at         timestamptz,
  add column if not exists signoff_rationale  text;

alter table public.pareto_curves
  drop constraint if exists pc_cv_method_enum,
  drop constraint if exists pc_cv_fold_range,
  drop constraint if exists pc_power_in_unit,
  drop constraint if exists pc_shrinkage_in_unit,
  drop constraint if exists pc_signoff_rationale_len,
  drop constraint if exists pc_validated_requires_cv_and_signoff;

alter table public.pareto_curves
  add constraint pc_cv_method_enum check (
    cv_method is null or cv_method in ('k_fold','bootstrap','holdout','loo','none')
  ),
  add constraint pc_cv_fold_range check (
    cv_fold_count is null or cv_fold_count between 2 and 100
  ),
  add constraint pc_power_in_unit check (
    power_estimate is null or (power_estimate >= 0 and power_estimate <= 1)
  ),
  add constraint pc_shrinkage_in_unit check (
    shrinkage_estimate is null or (shrinkage_estimate >= 0 and shrinkage_estimate <= 1)
  ),
  add constraint pc_signoff_rationale_len check (
    signoff_rationale is null or length(signoff_rationale) >= 100
  ),
  add constraint pc_validated_requires_cv_and_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and is_cross_validated = true
      and power_estimate is not null
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    )
  );

comment on column public.pareto_curves.is_cross_validated is
  'True iff the curve was computed with hold-out / k-fold / bootstrap CV. Per Song 2017/2023, uncross-validated Pareto frontiers cannot be relied on for adverse-impact predictions — they overstate the achievable diversity gains.';
comment on column public.pareto_curves.power_estimate is
  'Statistical power estimate for detecting the curvature in the validity-vs-AIR trade-off (Aguinis 2010). Validated curves must report this; low-power curves should be labelled as such.';
comment on column public.pareto_curves.shrinkage_estimate is
  'Song 2017 diversity-shrinkage estimate: the fraction by which observed Pareto improvements are expected to attenuate when applied to a new sample. Validated curves report this OR explain its omission in the signoff_rationale.';

-- ─── 2. Extend pareto_curve_points with CV intervals ────────────────
alter table public.pareto_curve_points
  add column if not exists cv_predicted_validity_lower numeric,
  add column if not exists cv_predicted_validity_upper numeric,
  add column if not exists cv_predicted_air_lower      numeric,
  add column if not exists cv_predicted_air_upper      numeric;

alter table public.pareto_curve_points
  drop constraint if exists pcp_validity_ci_order,
  drop constraint if exists pcp_air_ci_order;
alter table public.pareto_curve_points
  add constraint pcp_validity_ci_order check (
    cv_predicted_validity_lower is null or cv_predicted_validity_upper is null
    or cv_predicted_validity_lower <= cv_predicted_validity_upper
  ),
  add constraint pcp_air_ci_order check (
    cv_predicted_air_lower is null or cv_predicted_air_upper is null
    or cv_predicted_air_lower <= cv_predicted_air_upper
  );

-- ─── 3. Extend pareto_weight_choices with signoff seam ──────────────
alter table public.pareto_weight_choices
  add column if not exists validity_status   public.validity_status not null default 'dev_stub',
  add column if not exists signoff_actor_id  uuid references public.people(id),
  add column if not exists signoff_at        timestamptz,
  add column if not exists signoff_rationale text;

alter table public.pareto_weight_choices
  drop constraint if exists pwc_signoff_rationale_len,
  drop constraint if exists pwc_validated_requires_signoff;

alter table public.pareto_weight_choices
  add constraint pwc_signoff_rationale_len check (
    signoff_rationale is null or length(signoff_rationale) >= 100
  ),
  add constraint pwc_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    )
  );

create index if not exists pwc_status_idx on public.pareto_weight_choices(validity_status);

-- ─── 4. Sign-off RPCs ────────────────────────────────────────────────
create or replace function public.rpc_pareto_curve_signoff(
  p_curve_id           uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_caller_person_id uuid;
  v_row              public.pareto_curves%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.pareto_curves where id = p_curve_id for update;
  if not found then
    raise exception 'pareto_curve % not found', p_curve_id using errcode='P0002';
  end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;
  if v_row.is_cross_validated is not true then
    raise exception 'cannot sign off uncross-validated curve (Song 2017 shrinkage); set is_cross_validated=true after running CV'
      using errcode='22023';
  end if;
  if v_row.power_estimate is null then
    raise exception 'cannot sign off curve without power_estimate (Aguinis 2010)' using errcode='22023';
  end if;

  update public.pareto_curves
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_curve_id;

  perform public.audit_log_event(
    v_row.org_id, 'pareto_curve.signoff', 'pareto_curve', p_curve_id,
    to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'cv_method', v_row.cv_method, 'cv_fold_count', v_row.cv_fold_count,
      'sample_size', v_row.sample_size, 'power_estimate', v_row.power_estimate,
      'shrinkage_estimate', v_row.shrinkage_estimate), null);

  return jsonb_build_object('ok', true, 'curve_id', p_curve_id,
    'validity_status', 'validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_pareto_curve_signoff(uuid, text) from public;
grant execute on function public.rpc_pareto_curve_signoff(uuid, text) to authenticated, service_role;

create or replace function public.rpc_pareto_weight_choice_signoff(
  p_choice_id          uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_caller_person_id uuid;
  v_row              public.pareto_weight_choices%rowtype;
  v_curve            public.pareto_curves%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.pareto_weight_choices where id = p_choice_id for update;
  if not found then
    raise exception 'pareto_weight_choice % not found', p_choice_id using errcode='P0002';
  end if;
  select * into v_curve from public.pareto_curves where id = v_row.curve_id;
  if v_curve.validity_status <> 'validated' then
    raise exception 'cannot sign off weight choice when underlying curve is not validated (curve status=%)',
      v_curve.validity_status using errcode='22023';
  end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;

  update public.pareto_weight_choices
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale
   where id = p_choice_id;

  perform public.audit_log_event(
    v_row.org_id, 'pareto_weight_choice.signoff', 'pareto_weight_choice', p_choice_id,
    to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'chosen_weight_validity', v_row.chosen_weight_validity,
      'underlying_curve_id', v_row.curve_id), null);

  return jsonb_build_object('ok', true, 'choice_id', p_choice_id,
    'validity_status', 'validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_pareto_weight_choice_signoff(uuid, text) from public;
grant execute on function public.rpc_pareto_weight_choice_signoff(uuid, text) to authenticated, service_role;
