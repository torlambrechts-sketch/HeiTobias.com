-- phase4_step4_fairness_functions — RPCs for the bias-audit machinery.

-- ============ demographic_record ============
-- Anon/token-gated. Data subject voluntarily records demographics for
-- bias-monitoring (fairness_monitoring consent purpose). Token must
-- resolve to the subject AND a fairness_monitoring consent grant must
-- exist for the org.
create or replace function public.demographic_record(
  p_token        text,
  p_employer_org_id uuid,
  p_gender       text default null,
  p_ethnicity    text default null,
  p_age_band     text default null,
  p_disability_status text default null,
  p_nationality  text default null,
  p_language_first text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_person_id uuid;
  v_consent   uuid;
  v_id        uuid;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'demographic_record: token required';
  end if;
  select (r).person_id into v_person_id from public._consent_token_resolve(p_token) r;
  if v_person_id is null then
    raise exception 'demographic_record: invalid or expired token';
  end if;
  select id into v_consent from public.consent_grants
    where person_id = v_person_id and granted_to_org_id = p_employer_org_id
      and purpose = 'fairness_monitoring' and status = 'active'
      and revoked_at is null and (expires_at is null or expires_at > now())
    limit 1;
  if v_consent is null then
    raise exception 'demographic_record: no active fairness_monitoring consent — grant it first';
  end if;
  insert into public.demographics_voluntary (
    org_id, person_id, consent_id,
    gender, ethnicity, age_band, disability_status, nationality, language_first
  ) values (
    p_employer_org_id, v_person_id, v_consent,
    p_gender, p_ethnicity, p_age_band, p_disability_status, p_nationality, p_language_first
  )
  on conflict (org_id, person_id) do update set
    gender            = excluded.gender,
    ethnicity         = excluded.ethnicity,
    age_band          = excluded.age_band,
    disability_status = excluded.disability_status,
    nationality       = excluded.nationality,
    language_first    = excluded.language_first
  returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_employer_org_id, v_person_id, 'demographics.recorded',
            'demographics_voluntary', v_id,
            jsonb_build_object('purpose','fairness_monitoring','_dev_stub',true));
  return v_id;
end;
$$;
revoke execute on function public.demographic_record(text, uuid, text, text, text, text, text, text) from public;
grant  execute on function public.demographic_record(text, uuid, text, text, text, text, text, text)
  to anon, authenticated, service_role;

-- ============ fairness_consent_grant ============
-- Companion to research_consent_grant — opens the fairness_monitoring
-- rung. Same shape.
create or replace function public.fairness_consent_grant(
  p_token            text,
  p_employer_org_id  uuid,
  p_scope_json       jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_person_id uuid;
  v_existing  uuid;
  v_id        uuid;
begin
  select (r).person_id into v_person_id from public._consent_token_resolve(p_token) r;
  if v_person_id is null then
    raise exception 'fairness_consent_grant: invalid or expired token';
  end if;
  if not exists (select 1 from public.organizations where id = p_employer_org_id) then
    raise exception 'fairness_consent_grant: org not found';
  end if;
  select id into v_existing from public.consent_grants
    where person_id = v_person_id and granted_to_org_id = p_employer_org_id
      and purpose = 'fairness_monitoring' and status = 'active' and revoked_at is null
      and (expires_at is null or expires_at > now())
    limit 1;
  if v_existing is not null then return v_existing; end if;
  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis, scope_json)
    values (v_person_id, p_employer_org_id, 'fairness_monitoring', 'consent', coalesce(p_scope_json,'{}'::jsonb))
    returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_employer_org_id, v_person_id, 'consent.granted', 'consent_grants', v_id,
            jsonb_build_object('purpose','fairness_monitoring','source','candidate_dashboard'));
  return v_id;
end;
$$;
revoke execute on function public.fairness_consent_grant(text, uuid, jsonb) from public;
grant  execute on function public.fairness_consent_grant(text, uuid, jsonb)
  to anon, authenticated, service_role;

-- ============ fairness_run_open ============
-- Opens a fairness_run bucket. The actual metric rows are inserted by
-- fairness_metric_record — usually driven by the I/O psychologist's
-- external R/Python pipeline (Wilson CIs, bootstrap, Cleary, Fisher /
-- chi-square). We do NOT fabricate the math in SQL.
create or replace function public.fairness_run_open(
  p_org_id   uuid,
  p_model_id uuid,
  p_key      text default null,
  p_scope_json jsonb default '{}'::jsonb,
  p_notes    text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_run_id uuid;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'fairness_run_open: caller lacks modeling.write';
  end if;
  if not exists (select 1 from public.model_registry where id = p_model_id and org_id = p_org_id) then
    raise exception 'fairness_run_open: model not found in org';
  end if;

  insert into public.fairness_runs (org_id, model_id, key, scope_json, notes, _dev_stub)
    values (p_org_id, p_model_id,
            coalesce(p_key, 'fairness_'||to_char(now(),'YYYYMMDDHH24MISS')),
            coalesce(p_scope_json,'{}'::jsonb),
            coalesce(p_notes, 'DEV STUB fairness run — metrics ingested from external pipeline'),
            true)
    returning id into v_run_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'fairness_run.opened', 'fairness_runs', v_run_id,
      jsonb_build_object('model_id', p_model_id, '_dev_stub', true));

  return v_run_id;
end;
$$;
revoke execute on function public.fairness_run_open(uuid, uuid, text, jsonb, text) from public;
grant  execute on function public.fairness_run_open(uuid, uuid, text, jsonb, text)
  to authenticated, service_role;

-- ============ fairness_metric_record ============
-- A separate RPC to insert a single metric row. Used by the dev-stub
-- compute path AND by any caller that wants to ingest externally-computed
-- (R/Python notebook) metrics — that's the legitimate path for the I/O
-- psychologist's actual analyses.
create or replace function public.fairness_metric_record(
  p_run_id                 uuid,
  p_characteristic         text,
  p_reference_group        text,
  p_protected_group        text,
  p_selection_rate_reference numeric,
  p_selection_rate_protected numeric,
  p_sample_size_reference  int,
  p_sample_size_protected  int,
  p_statistical_test_name  text default null,
  p_statistical_test_p_value numeric default null,
  p_differential_prediction_slope numeric default null,
  p_differential_prediction_intercept numeric default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_org    uuid;
  v_air    numeric;
  v_ci_l   numeric;
  v_ci_u   numeric;
  v_trig   boolean;
  v_id     uuid;
begin
  select r.org_id into v_org from public.fairness_runs r where r.id = p_run_id;
  if v_org is null then raise exception 'fairness_metric_record: run not found'; end if;
  if v_caller is not null and not public.has_permission(v_org, 'modeling.write') then
    raise exception 'fairness_metric_record: caller lacks modeling.write';
  end if;

  -- adverse_impact_ratio = protected/reference; null if reference is 0.
  if p_selection_rate_reference is null or p_selection_rate_reference = 0 then
    v_air := null;
  else
    v_air := p_selection_rate_protected / p_selection_rate_reference;
  end if;
  -- DEV STUB CI: ±0.05 around the ratio. Replace with Wilson/bootstrap.
  v_ci_l := case when v_air is null then null else greatest(0, v_air - 0.05) end;
  v_ci_u := case when v_air is null then null else least(2, v_air + 0.05) end;
  -- INSPECTION TRIGGER — never a verdict. The classic four-fifths
  -- threshold is the trigger.
  v_trig := v_air is not null and v_air < 0.80;

  insert into public.fairness_metrics (
    run_id, characteristic, reference_group, protected_group,
    selection_rate_reference, selection_rate_protected,
    adverse_impact_ratio, ci_lower, ci_upper,
    sample_size_reference, sample_size_protected,
    statistical_test_name, statistical_test_p_value,
    differential_prediction_slope, differential_prediction_intercept,
    four_fifths_inspection_triggered, _dev_stub
  ) values (
    p_run_id, p_characteristic, p_reference_group, p_protected_group,
    p_selection_rate_reference, p_selection_rate_protected,
    v_air, v_ci_l, v_ci_u,
    p_sample_size_reference, p_sample_size_protected,
    p_statistical_test_name, p_statistical_test_p_value,
    p_differential_prediction_slope, p_differential_prediction_intercept,
    v_trig, true
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function public.fairness_metric_record(uuid, text, text, text, numeric, numeric, int, int, text, numeric, numeric, numeric) from public;
grant  execute on function public.fairness_metric_record(uuid, text, text, text, numeric, numeric, int, int, text, numeric, numeric, numeric)
  to authenticated, service_role;

-- ============ fairness_metric_interpret ============
-- Expert seam. modeling.signoff gated.
create or replace function public.fairness_metric_interpret(
  p_metric_id      uuid,
  p_interpretation text
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
begin
  select r.org_id into v_org from public.fairness_metrics m
    join public.fairness_runs r on r.id = m.run_id
    where m.id = p_metric_id;
  if v_org is null then raise exception 'fairness_metric_interpret: metric not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'modeling.signoff') then
    raise exception 'fairness_metric_interpret: requires modeling.signoff (expert seam)';
  end if;
  if p_interpretation is null or length(p_interpretation) < 20 then
    raise exception 'fairness_metric_interpret: interpretation must be >=20 chars';
  end if;
  update public.fairness_metrics set
    interpretation_by_expert = p_interpretation,
    interpreted_by_person_id = v_actor,
    interpreted_at = now()
  where id = p_metric_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'fairness_metric.interpreted', 'fairness_metrics', p_metric_id,
      jsonb_build_object('interpreted_by', v_actor));
  return p_metric_id;
end;
$$;
revoke execute on function public.fairness_metric_interpret(uuid, text) from public;
grant  execute on function public.fairness_metric_interpret(uuid, text)
  to authenticated, service_role;
