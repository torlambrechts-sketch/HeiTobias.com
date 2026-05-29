-- phase4_step2_model_functions — register / card / predict RPCs for
-- the Phase 4 interpretable-baseline scaffolding.

-- ============ model_register ============
-- Create a model_registry row + an empty model_cards row in one txn so
-- a card is structurally required before any training_run or prediction
-- can reference the model.
create or replace function public.model_register(
  p_org_id             uuid,
  p_key                text,
  p_family             text,
  p_feature_view_id    uuid,
  p_training_dataset_id uuid default null,
  p_description        text default null,
  p_owner_person_id    uuid default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_owner  uuid := coalesce(p_owner_person_id,
                            (select id from public.people where auth_user_id = v_caller limit 1));
  v_id     uuid;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'model_register: caller lacks modeling.write';
  end if;
  insert into public.model_registry (org_id, key, family, feature_view_id,
                                     training_dataset_id, owner_person_id, description)
    values (p_org_id, p_key, p_family, p_feature_view_id,
            p_training_dataset_id, v_owner, p_description)
    returning id into v_id;
  insert into public.model_cards (model_id) values (v_id);
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_owner, 'model.registered', 'model_registry', v_id,
            jsonb_build_object('family', p_family, 'feature_view_id', p_feature_view_id,
                               '_dev_stub', true));
  return v_id;
end;
$$;
revoke execute on function public.model_register(uuid, text, text, uuid, uuid, text, uuid) from public;
grant  execute on function public.model_register(uuid, text, text, uuid, uuid, text, uuid)
  to authenticated, service_role;

-- ============ model_card_update ============
-- Fill in the structured card fields. Stays validity_status='dev_stub'
-- — only the I/O psychologist with modeling.signoff can promote it.
create or replace function public.model_card_update(
  p_model_id              uuid,
  p_intended_use          text default null,
  p_limits_json           jsonb default null,
  p_data_lineage_json     jsonb default null,
  p_features_json         jsonb default null,
  p_weights_json          jsonb default null,
  p_fairness_metrics_json jsonb default null,
  p_ethical_considerations text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_org    uuid;
  v_card_id uuid;
begin
  select org_id into v_org from public.model_registry where id = p_model_id;
  if v_org is null then raise exception 'model_card_update: model not found'; end if;
  if v_caller is not null and not public.has_permission(v_org, 'modeling.write') then
    raise exception 'model_card_update: caller lacks modeling.write';
  end if;
  update public.model_cards set
    intended_use           = coalesce(p_intended_use,           intended_use),
    limits_json            = coalesce(p_limits_json,            limits_json),
    data_lineage_json      = coalesce(p_data_lineage_json,      data_lineage_json),
    features_json          = coalesce(p_features_json,          features_json),
    weights_json           = coalesce(p_weights_json,           weights_json),
    fairness_metrics_json  = coalesce(p_fairness_metrics_json,  fairness_metrics_json),
    ethical_considerations = coalesce(p_ethical_considerations, ethical_considerations),
    updated_at             = now()
  where model_id = p_model_id
  returning id into v_card_id;
  return v_card_id;
end;
$$;
revoke execute on function public.model_card_update(uuid, text, jsonb, jsonb, jsonb, jsonb, jsonb, text) from public;
grant  execute on function public.model_card_update(uuid, text, jsonb, jsonb, jsonb, jsonb, jsonb, text)
  to authenticated, service_role;

-- ============ model_card_signoff ============
-- The expert seam. Requires modeling.signoff (NOT granted to any seeded
-- role) and validates the card. Refuses if the card is missing the
-- required structured documentation (CHECK does the same; this gives a
-- friendlier error and writes the audit trail).
create or replace function public.model_card_signoff(p_model_id uuid)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller   uuid := (select auth.uid());
  v_actor    uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_org      uuid;
  v_card     public.model_cards%rowtype;
begin
  select org_id into v_org from public.model_registry where id = p_model_id;
  if v_org is null then raise exception 'model_card_signoff: model not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'modeling.signoff') then
    raise exception 'model_card_signoff: requires modeling.signoff (expert seam — see HANDOFF list)';
  end if;
  select * into v_card from public.model_cards where model_id = p_model_id;
  if v_card.intended_use is null or length(v_card.intended_use) <= 10
     or v_card.limits_json = '{}'::jsonb
     or v_card.data_lineage_json = '{}'::jsonb
     or jsonb_array_length(v_card.features_json) = 0 then
    raise exception 'model_card_signoff: card lacks structured documentation required by SCIENCE-SPEC §9';
  end if;
  update public.model_cards set
    signed_off_by   = v_actor,
    signed_off_at   = now(),
    validity_status = 'validated',
    _dev_stub       = false,
    updated_at      = now()
  where model_id = p_model_id;
  update public.model_registry set
    validity_status = 'validated',
    _dev_stub       = false,
    updated_at      = now()
  where id = p_model_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'model_card.signed_off', 'model_cards', v_card.id,
            jsonb_build_object('model_id', p_model_id, 'signed_off_by', v_actor));
  return v_card.id;
end;
$$;
revoke execute on function public.model_card_signoff(uuid) from public;
grant  execute on function public.model_card_signoff(uuid) to authenticated, service_role;
comment on function public.model_card_signoff(uuid) is
  'Expert seam (modeling.signoff). Promotes a model + card to validated only when the structured documentation is filled. NOT granted to any seeded role — see HANDOFF list.';

-- ============ training_run_record ============
create or replace function public.training_run_record(
  p_model_id        uuid,
  p_dataset_id      uuid,
  p_run_method      text,
  p_eval_metrics_json jsonb default '{}'::jsonb,
  p_notes           text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_org    uuid;
  v_id     uuid;
begin
  select org_id into v_org from public.model_registry where id = p_model_id;
  if v_org is null then raise exception 'training_run_record: model not found'; end if;
  if v_caller is not null and not public.has_permission(v_org, 'modeling.write') then
    raise exception 'training_run_record: caller lacks modeling.write';
  end if;
  insert into public.training_runs (model_id, dataset_id, run_method, eval_metrics_json, notes)
    values (p_model_id, p_dataset_id, p_run_method, coalesce(p_eval_metrics_json, '{}'::jsonb), p_notes)
    returning id into v_id;
  insert into public.audit_log (org_id, action, entity_type, entity_id, after_json)
    values (v_org, 'model.training_run', 'training_runs', v_id,
            jsonb_build_object('model_id', p_model_id, 'method', p_run_method, '_dev_stub', true));
  return v_id;
end;
$$;
revoke execute on function public.training_run_record(uuid, uuid, text, jsonb, text) from public;
grant  execute on function public.training_run_record(uuid, uuid, text, jsonb, text)
  to authenticated, service_role;

-- ============ prediction_compute_baseline_interpretable ============
-- Interpretable-first baseline (SCIENCE-SPEC §9 + GDPR Art. 22):
-- pulls the latest feature_row for the (person × model.feature_view),
-- computes a linear weighted-sum of the per-competency band_fit values,
-- and emits per-feature attribution (the SHAP-equivalent for an
-- additive model is the contribution itself: weight × value).
--
-- DEV STUB — equal weights, no calibration, no validity. Replace when
-- the I/O psychologist + their dataset land. The point is that the
-- ENGINE shape — weighted contributions + per-feature attribution —
-- is right.
create or replace function public.prediction_compute_baseline_interpretable(
  p_model_id  uuid,
  p_person_id uuid,
  p_role_id   uuid default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller    uuid := (select auth.uid());
  v_model     public.model_registry%rowtype;
  v_card      public.model_cards%rowtype;
  v_fr        public.feature_rows%rowtype;
  v_consent   uuid;
  v_comp      jsonb;
  v_n         int := 0;
  v_sum       numeric := 0;
  v_w         numeric;
  v_v         numeric;
  v_shap      jsonb := '[]'::jsonb;
  v_id        uuid;
begin
  select * into v_model from public.model_registry where id = p_model_id;
  if v_model.id is null then raise exception 'prediction_compute: model not found'; end if;
  if v_caller is not null and not public.has_permission(v_model.org_id, 'modeling.write') then
    raise exception 'prediction_compute: caller lacks modeling.write';
  end if;
  select * into v_card from public.model_cards where model_id = p_model_id;
  if v_card.id is null then
    raise exception 'prediction_compute: model_card missing — SCIENCE-SPEC §9 requires a card before predictions';
  end if;

  -- Latest feature_row for this (person, feature_view) — consent-gated.
  select * into v_fr from public.feature_rows
    where person_id = p_person_id and feature_view_id = v_model.feature_view_id
      and org_id = v_model.org_id
    order by valid_at desc limit 1;
  if v_fr.id is null then
    raise exception 'prediction_compute: no feature_row found for person — compute features first';
  end if;
  v_consent := v_fr.consent_id;

  -- Linear weighted-sum + per-feature attribution.
  -- DEV STUB: weights default to target_weight if present, else 1; the
  -- math is honest for an additive interpretable model.
  for v_comp in
    select value from jsonb_array_elements(coalesce(v_fr.value_json->'per_competency','[]'::jsonb))
  loop
    v_w := coalesce((v_comp->>'target_weight')::numeric, 1);
    v_v := coalesce((v_comp->>'band_fit')::numeric, 0);
    v_sum := v_sum + (v_w * v_v);
    v_n   := v_n + 1;
    v_shap := v_shap || jsonb_build_array(jsonb_build_object(
      'feature',      v_comp->>'competency_key',
      'value',        v_v,
      'weight',       v_w,
      'contribution', v_w * v_v,
      '_dev_stub',    true
    ));
  end loop;
  if v_n = 0 then
    -- predictions CHECK requires at least one explanation row — emit a
    -- single 'no_features' marker so the structural invariant holds
    -- without us silently inventing a value.
    v_shap := jsonb_build_array(jsonb_build_object(
      'feature','no_features','value',0,'weight',0,'contribution',0,'_dev_stub',true,
      '_note','no per_competency rows in feature_row — engine returns null score'
    ));
  end if;

  insert into public.predictions (
    org_id, model_id, person_id, role_id, consent_id,
    score_value, prediction_json, explanation_shap_json,
    feature_row_ids, predicted_at, _dev_stub
  ) values (
    v_model.org_id, p_model_id, p_person_id, p_role_id, v_consent,
    case when v_n = 0 then null else v_sum / v_n end,
    jsonb_build_object('method','interpretable_baseline_dev_stub_v0',
                       'feature_count', v_n,
                       '_dev_stub', true,
                       'informs_decision', true,
                       'is_decision', false),
    v_shap,
    array[v_fr.id], now(), true
  ) returning id into v_id;

  return v_id;
end;
$$;
revoke execute on function public.prediction_compute_baseline_interpretable(uuid, uuid, uuid) from public;
grant  execute on function public.prediction_compute_baseline_interpretable(uuid, uuid, uuid)
  to authenticated, service_role;
comment on function public.prediction_compute_baseline_interpretable(uuid, uuid, uuid) is
  'DEV STUB interpretable baseline. Linear weighted-sum of feature contributions with per-feature attribution. Real validated scoring lands when the I/O psychologist plugs in. Prediction INFORMS a human; never decides.';

-- ============ prediction_attach_to_decision ============
-- Wires a prediction to a hiring_decision or lifecycle_decision after
-- the human acted. Enforces the prediction-informs-human invariant:
-- the decision row must already exist and belong to the same org.
create or replace function public.prediction_attach_to_decision(
  p_prediction_id uuid,
  p_decision_id   uuid,
  p_decision_type text
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller   uuid := (select auth.uid());
  v_pred     public.predictions%rowtype;
  v_ok       boolean := false;
begin
  if p_decision_type not in ('hiring_decision','lifecycle_decision') then
    raise exception 'prediction_attach_to_decision: invalid decision_type';
  end if;
  select * into v_pred from public.predictions where id = p_prediction_id;
  if v_pred.id is null then raise exception 'prediction_attach_to_decision: not found'; end if;
  if v_caller is not null and not public.has_permission(v_pred.org_id, 'modeling.write') then
    raise exception 'prediction_attach_to_decision: caller lacks modeling.write';
  end if;
  if p_decision_type = 'hiring_decision' then
    select true into v_ok from public.hiring_decisions
      where id = p_decision_id and org_id = v_pred.org_id;
  else
    select true into v_ok from public.lifecycle_decisions
      where id = p_decision_id and org_id = v_pred.org_id;
  end if;
  if not coalesce(v_ok, false) then
    raise exception 'prediction_attach_to_decision: decision not found in same org';
  end if;
  update public.predictions set
    informs_decision_id = p_decision_id,
    informs_decision_type = p_decision_type
  where id = p_prediction_id;
  return p_prediction_id;
end;
$$;
revoke execute on function public.prediction_attach_to_decision(uuid, uuid, text) from public;
grant  execute on function public.prediction_attach_to_decision(uuid, uuid, text)
  to authenticated, service_role;
