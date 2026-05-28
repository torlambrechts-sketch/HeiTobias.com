-- phase4_step3_pareto_functions — compute + choose RPCs for the
-- Pareto validity-diversity curve.

-- ============ pareto_curve_compute ============
-- DEV STUB: emit a curve from w=0..1 in 0.05 steps. The shape is a
-- synthetic linear interaction reflecting the documented validity vs.
-- adverse-impact trade-off. Real estimators land when the I/O
-- psychologist plugs in (Cleary slope-intercept + Bayesian posterior
-- over weight choices; De Corte 2007).
--
-- The DEFAULT point is the neutral midpoint (w=0.5). The CHECK on the
-- table refuses any default outside (0.05, 0.95) — neither extreme can
-- be the default.
create or replace function public.pareto_curve_compute(
  p_org_id           uuid,
  p_feature_view_id  uuid,
  p_model_id         uuid default null,
  p_curve_key        text default null,
  p_regularization_lambda numeric default 0.0
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller   uuid := (select auth.uid());
  v_curve_id uuid;
  v_w        numeric;
  v_idx      int := 0;
  v_val      numeric;
  v_air      numeric;
  v_sel      numeric;
  v_default  numeric := 0.5;
  v_actor    uuid := (select id from public.people where auth_user_id = v_caller limit 1);
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'pareto_curve_compute: caller lacks modeling.write';
  end if;

  insert into public.pareto_curves (
    org_id, feature_view_id, model_id, key,
    regularization_lambda, default_weight_validity, notes, _dev_stub
  ) values (
    p_org_id, p_feature_view_id, p_model_id,
    coalesce(p_curve_key, 'pareto_'||to_char(now(),'YYYYMMDDHH24MISS')),
    coalesce(p_regularization_lambda, 0.0), v_default,
    'DEV STUB Pareto curve — synthetic linear trade-off pending I/O-validated estimators',
    true
  ) returning id into v_curve_id;

  -- Emit 21 points (w = 0.00, 0.05, ..., 1.00). Synthetic linear:
  --   predicted_validity = 0.30 + 0.30*w  (range 0.30..0.60)
  --   predicted_air      = 0.95 - 0.40*w  (range 0.95..0.55)
  --   predicted_sel_rate = 0.20 + 0.05*w  (range 0.20..0.25)
  -- Regularization lambda shrinks the spread toward the default
  -- (synthetic only — real shrinkage is a Bayesian posterior).
  v_w := 0.0;
  while v_w <= 1.00001 loop
    v_val := 0.30 + 0.30 * v_w;
    v_air := 0.95 - 0.40 * v_w;
    v_sel := 0.20 + 0.05 * v_w;
    -- shrink toward default by lambda
    v_val := v_val * (1 - coalesce(p_regularization_lambda,0))
             + (0.30 + 0.30 * v_default) * coalesce(p_regularization_lambda,0);
    v_air := v_air * (1 - coalesce(p_regularization_lambda,0))
             + (0.95 - 0.40 * v_default) * coalesce(p_regularization_lambda,0);
    insert into public.pareto_curve_points (
      curve_id, ordered_index, weight_validity,
      predicted_validity, predicted_air, predicted_selection_rate,
      is_default_point, _dev_stub
    ) values (
      v_curve_id, v_idx, round(v_w::numeric, 2),
      round(v_val::numeric, 4), round(v_air::numeric, 4), round(v_sel::numeric, 4),
      abs(v_w - v_default) < 0.001, true
    );
    v_idx := v_idx + 1;
    v_w := v_w + 0.05;
  end loop;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'pareto_curve.computed', 'pareto_curves', v_curve_id,
      jsonb_build_object('feature_view_id', p_feature_view_id, 'model_id', p_model_id,
                         'regularization_lambda', p_regularization_lambda,
                         'default_weight_validity', v_default, '_dev_stub', true));

  return v_curve_id;
end;
$$;
revoke execute on function public.pareto_curve_compute(uuid, uuid, uuid, text, numeric) from public;
grant  execute on function public.pareto_curve_compute(uuid, uuid, uuid, text, numeric)
  to authenticated, service_role;

-- ============ pareto_weight_choose ============
-- The customer picks a point. Rationale + chooser identity are
-- required (CHECK on the table for rationale length; function uses
-- auth.uid()). The choice is audited.
create or replace function public.pareto_weight_choose(
  p_curve_id      uuid,
  p_weight_validity numeric,
  p_rationale     text,
  p_applies_to_model_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_org    uuid;
  v_id     uuid;
begin
  if v_caller is null then
    raise exception 'pareto_weight_choose: requires an authenticated person (attributable choice)';
  end if;
  if v_actor is null then
    raise exception 'pareto_weight_choose: no person row for caller — attribution impossible';
  end if;
  select org_id into v_org from public.pareto_curves where id = p_curve_id;
  if v_org is null then raise exception 'pareto_weight_choose: curve not found'; end if;
  if not public.has_permission(v_org, 'modeling.write') then
    raise exception 'pareto_weight_choose: caller lacks modeling.write';
  end if;
  if p_weight_validity is null or p_weight_validity < 0 or p_weight_validity > 1 then
    raise exception 'pareto_weight_choose: weight_validity must be in [0,1]';
  end if;
  if p_rationale is null or length(p_rationale) <= 20 then
    raise exception 'pareto_weight_choose: rationale must be >20 chars (attribution requirement)';
  end if;

  insert into public.pareto_weight_choices (
    org_id, curve_id, chosen_weight_validity, chosen_by_person_id,
    rationale, applies_to_model_id, _dev_stub
  ) values (
    v_org, p_curve_id, p_weight_validity, v_actor, p_rationale,
    p_applies_to_model_id, true
  ) returning id into v_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'pareto_weight.chosen', 'pareto_weight_choices', v_id,
      jsonb_build_object('curve_id', p_curve_id, 'weight_validity', p_weight_validity,
                         'applies_to_model_id', p_applies_to_model_id, '_dev_stub', true));

  return v_id;
end;
$$;
revoke execute on function public.pareto_weight_choose(uuid, numeric, text, uuid) from public;
grant  execute on function public.pareto_weight_choose(uuid, numeric, text, uuid)
  to authenticated, service_role;
comment on function public.pareto_weight_choose(uuid, numeric, text, uuid) is
  'Customer-attributable Pareto point choice. Rationale >20 chars is required for the EU AI Act Art. 12 record-keeping requirement and the Mobley v. Workday-style audit trail.';
