-- phase4_step5_invariance_functions — RPCs that ingest invariance + DIF
-- statistics from external pipelines and gate verdicts behind the
-- modeling.signoff expert seam.
--
-- The SQL never computes invariance or DIF itself. lavaan / mirt /
-- difR run in Python or R; this layer is the audit-grade ledger. The
-- system NEVER writes invariance_verdict_by_expert or dif_items.
-- expert_review_note — only invariance_verdict_record and the
-- to-be-built dif_item_review (modeling.signoff gated) can fill them.

create or replace function public.norm_sample_register(
  p_instrument_key text, p_country_code text, p_language_code text,
  p_org_id uuid default null, p_sample_n int default null,
  p_period_start date default null, p_period_end date default null,
  p_collection_source text default null, p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare v_caller uuid := (select auth.uid()); v_id uuid;
begin
  if p_org_id is not null and v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'norm_sample_register: caller lacks modeling.write';
  end if;
  insert into public.norm_samples (org_id, instrument_key, country_code, language_code, sample_n, sample_period_start, sample_period_end, collection_source, notes, _dev_stub)
    values (p_org_id, p_instrument_key, p_country_code, p_language_code, p_sample_n, p_period_start, p_period_end, coalesce(p_collection_source,'DEV STUB — pending real norm collection'), p_notes, true)
    returning id into v_id;
  insert into public.audit_log (org_id, action, entity_type, entity_id, after_json)
    values (p_org_id, 'norm_sample.registered', 'norm_samples', v_id,
            jsonb_build_object('instrument', p_instrument_key, 'country', p_country_code, 'language', p_language_code, '_dev_stub', true));
  return v_id;
end;
$$;
revoke execute on function public.norm_sample_register(text, text, text, uuid, int, date, date, text, text) from public;
grant  execute on function public.norm_sample_register(text, text, text, uuid, int, date, date, text, text) to authenticated, service_role;

create or replace function public.invariance_run_record(
  p_org_id uuid, p_instrument_key text, p_scope_json jsonb default '{}'::jsonb, p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_id uuid;
begin
  if p_org_id is not null and v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'invariance_run_record: caller lacks modeling.write';
  end if;
  insert into public.invariance_runs (org_id, instrument_key, scope_json, notes, _dev_stub)
    values (p_org_id, p_instrument_key, coalesce(p_scope_json,'{}'::jsonb),
            coalesce(p_notes,'DEV STUB — statistics from external lavaan pipeline'), true)
    returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'invariance_run.recorded', 'invariance_runs', v_id,
            jsonb_build_object('instrument', p_instrument_key, '_dev_stub', true));
  return v_id;
end;
$$;
revoke execute on function public.invariance_run_record(uuid, text, jsonb, text) from public;
grant  execute on function public.invariance_run_record(uuid, text, jsonb, text) to authenticated, service_role;

create or replace function public.invariance_result_record(
  p_run_id uuid, p_level text, p_comparison_groups_json jsonb,
  p_cfi numeric, p_rmsea numeric, p_srmr numeric,
  p_delta_cfi numeric default null, p_delta_rmsea numeric default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare v_caller uuid := (select auth.uid()); v_org uuid; v_id uuid;
begin
  select org_id into v_org from public.invariance_runs where id = p_run_id;
  if not found then raise exception 'invariance_result_record: run not found'; end if;
  if v_org is not null and v_caller is not null and not public.has_permission(v_org, 'modeling.write') then
    raise exception 'invariance_result_record: caller lacks modeling.write';
  end if;
  if p_level not in ('configural','metric','scalar') then
    raise exception 'invariance_result_record: invalid level';
  end if;
  insert into public.invariance_results (run_id, level, comparison_groups_json, cfi, rmsea, srmr, delta_cfi_vs_prior_level, delta_rmsea_vs_prior_level, _dev_stub)
    values (p_run_id, p_level, coalesce(p_comparison_groups_json,'{}'::jsonb), p_cfi, p_rmsea, p_srmr, p_delta_cfi, p_delta_rmsea, true)
    returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function public.invariance_result_record(uuid, text, jsonb, numeric, numeric, numeric, numeric, numeric) from public;
grant  execute on function public.invariance_result_record(uuid, text, jsonb, numeric, numeric, numeric, numeric, numeric) to authenticated, service_role;

create or replace function public.invariance_verdict_record(
  p_result_id uuid, p_verdict text
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_org uuid;
begin
  select r.org_id into v_org from public.invariance_results res
    join public.invariance_runs r on r.id = res.run_id where res.id = p_result_id;
  if not found then raise exception 'invariance_verdict_record: result not found'; end if;
  if v_caller is null or (v_org is not null and not public.has_permission(v_org, 'modeling.signoff')) then
    raise exception 'invariance_verdict_record: requires modeling.signoff (expert seam)';
  end if;
  if p_verdict is null or length(p_verdict) < 20 then
    raise exception 'invariance_verdict_record: verdict >=20 chars';
  end if;
  update public.invariance_results set
    invariance_verdict_by_expert = p_verdict,
    verdict_by_person_id = v_actor,
    verdict_at = now()
  where id = p_result_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'invariance_verdict.recorded', 'invariance_results', p_result_id,
            jsonb_build_object('verdict_by', v_actor));
  return p_result_id;
end;
$$;
revoke execute on function public.invariance_verdict_record(uuid, text) from public;
grant  execute on function public.invariance_verdict_record(uuid, text) to authenticated, service_role;

create or replace function public.dif_run_record(
  p_org_id uuid, p_instrument_key text, p_reference_group text, p_focal_group text,
  p_method text, p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_id uuid;
begin
  if p_org_id is not null and v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'dif_run_record: caller lacks modeling.write';
  end if;
  insert into public.dif_runs (org_id, instrument_key, reference_group, focal_group, method, notes, _dev_stub)
    values (p_org_id, p_instrument_key, p_reference_group, p_focal_group, p_method, coalesce(p_notes,'DEV STUB — DIF statistics from external pipeline'), true)
    returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'dif_run.recorded', 'dif_runs', v_id,
            jsonb_build_object('instrument', p_instrument_key, 'method', p_method, '_dev_stub', true));
  return v_id;
end;
$$;
revoke execute on function public.dif_run_record(uuid, text, text, text, text, text) from public;
grant  execute on function public.dif_run_record(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function public.dif_item_record(
  p_run_id uuid, p_item_key text, p_effect_size numeric, p_p_value numeric,
  p_flag_threshold_effect_size numeric default 0.10
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare v_caller uuid := (select auth.uid()); v_org uuid; v_id uuid; v_flag boolean;
begin
  select org_id into v_org from public.dif_runs where id = p_run_id;
  if not found then raise exception 'dif_item_record: run not found'; end if;
  if v_org is not null and v_caller is not null and not public.has_permission(v_org, 'modeling.write') then
    raise exception 'dif_item_record: caller lacks modeling.write';
  end if;
  -- INSPECTION TRIGGER, not verdict. Mantel-Haenszel "C" threshold is
  -- the conventional starting point — the I/O psychologist tunes it.
  v_flag := p_effect_size is not null and abs(p_effect_size) >= p_flag_threshold_effect_size;
  insert into public.dif_items (run_id, item_key, effect_size, p_value, flagged_for_review, _dev_stub)
    values (p_run_id, p_item_key, p_effect_size, p_p_value, v_flag, true)
    returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function public.dif_item_record(uuid, text, numeric, numeric, numeric) from public;
grant  execute on function public.dif_item_record(uuid, text, numeric, numeric, numeric) to authenticated, service_role;
