-- Team-Based Role Definition — CP3.3 divergence compute.
--
-- One SECDEF RPC, rpc_compute_divergence, that walks all submitted
-- evaluations' rating_json for a run, groups numeric values by
-- (category.criterion) path, and computes spread (SD) + consensus
-- category per criterion. Writes one row per criterion into
-- team_definition_divergence_runs and stamps a summary onto the run.
--
-- Per the methodology (SCIENCE-SPEC §7), divergence is SURFACED, never
-- averaged away. The RPC returns per-evaluator values alongside the
-- spread so the UI can render the individual positions — the mean
-- exists in the payload only as a descriptive statistic, not as the
-- thing the UI displays first.
--
-- Threshold tuning is dev_stub: SD >= low_consensus_sd_cutoff → low.
-- 0.5 × cutoff <= SD < cutoff → moderate. Below half-cutoff → high.
-- Per-criterion-scale normalisation (0–1 weights vs 0–5 criticality)
-- is an I/O-psych tuning item, not an engineering one — see HANDOFF.

create or replace function public.rpc_compute_divergence(p_run_id uuid)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_caller     uuid := (select auth.uid());
  v_actor      uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_run        public.team_definition_runs%rowtype;
  v_cutoff     numeric;
  v_min_evals  int;
  v_high       int := 0;
  v_mod        int := 0;
  v_low        int := 0;
  v_criteria   jsonb := '[]'::jsonb;
  rec          record;
  v_mean       numeric;
  v_sd         numeric;
  v_min        numeric;
  v_max        numeric;
  v_cat        public.team_definition_consensus_category;
begin
  if v_caller is null then raise exception 'rpc_compute_divergence: not authenticated'; end if;
  select * into v_run from public.team_definition_runs where id = p_run_id;
  if not found then raise exception 'rpc_compute_divergence: run not found'; end if;
  if not public.has_permission(v_run.org_id, 'role.read') then
    raise exception 'rpc_compute_divergence: requires role.read';
  end if;
  if v_run.stage not in ('divergence','reconciliation','signed_off') then
    raise exception 'rpc_compute_divergence: run must be sealed (current stage: %)', v_run.stage;
  end if;

  v_cutoff    := coalesce((v_run.thresholds_json -> 'low_consensus_sd_cutoff'     ->> 'value')::numeric, 1.4);
  v_min_evals := coalesce((v_run.thresholds_json -> 'min_evaluators_for_valid_run' ->> 'value')::int,     4);

  -- Idempotent recompute: clear prior rows.
  delete from public.team_definition_divergence_runs where run_id = p_run_id;

  for rec in
    with eval_values as (
      select
        e.id            as evaluation_id,
        e.evaluator_id  as evaluator_id,
        cat.cat_key,
        sub.sub_key,
        case
          when jsonb_typeof(sub.sub_val) = 'number'
            then (sub.sub_val #>> '{}')::numeric
          else null
        end as numval
      from public.team_definition_evaluations e
      cross join lateral jsonb_each(e.rating_json) as cat(cat_key, cat_val)
      cross join lateral jsonb_each(case when jsonb_typeof(cat.cat_val) = 'object' then cat.cat_val else '{}'::jsonb end) as sub(sub_key, sub_val)
      where e.run_id = p_run_id and e.submitted_at is not null
    )
    select
      cat_key || '.' || sub_key as criterion,
      array_agg(numval order by numval) as numvals,
      jsonb_agg(jsonb_build_object('evaluator_id', evaluator_id, 'value', numval) order by numval) as values_arr
    from eval_values
    where numval is not null
    group by cat_key, sub_key
  loop
    select avg(x), coalesce(stddev_samp(x),0), min(x), max(x)
      into v_mean, v_sd, v_min, v_max
      from unnest(rec.numvals) x;

    v_cat := case
      when v_sd >= v_cutoff then 'low'::public.team_definition_consensus_category
      when v_sd >= v_cutoff / 2 then 'moderate'::public.team_definition_consensus_category
      else 'high'::public.team_definition_consensus_category
    end;
    if v_cat = 'low' then v_low := v_low + 1;
    elsif v_cat = 'moderate' then v_mod := v_mod + 1;
    else v_high := v_high + 1; end if;

    insert into public.team_definition_divergence_runs
      (run_id, criterion_key, spread_metric_type, spread_value, consensus_category, flagged_for_reconciliation, ranges_json)
    values
      (p_run_id, rec.criterion, 'sd', v_sd, v_cat, v_cat = 'low',
       jsonb_build_object('mean', v_mean, 'min', v_min, 'max', v_max, 'range', v_max - v_min, 'values', rec.values_arr));

    v_criteria := v_criteria || jsonb_build_object(
      'criterion_key', rec.criterion,
      'spread_metric_type', 'sd',
      'spread_value', v_sd,
      'consensus_category', v_cat,
      'flagged_for_reconciliation', v_cat = 'low',
      'mean', v_mean, 'min', v_min, 'max', v_max,
      'values', rec.values_arr
    );
  end loop;

  update public.team_definition_runs set
    consensus_summary_json = jsonb_build_object(
      'high', v_high, 'moderate', v_mod, 'low', v_low,
      'total_criteria', v_high + v_mod + v_low,
      'cutoff', v_cutoff,
      'min_evaluators_for_valid_run', v_min_evals,
      'computed_at', now()
    ),
    updated_at = now()
  where id = p_run_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_run.org_id, v_actor, 'team_def.divergence_computed', 'team_definition_runs', p_run_id,
            jsonb_build_object('criteria_count', v_high + v_mod + v_low, 'high', v_high, 'moderate', v_mod, 'low', v_low));

  return jsonb_build_object(
    'criteria', v_criteria,
    'summary', jsonb_build_object(
      'high', v_high, 'moderate', v_mod, 'low', v_low,
      'total_criteria', v_high + v_mod + v_low,
      'cutoff', v_cutoff,
      'min_evaluators_for_valid_run', v_min_evals
    )
  );
end;
$$;
revoke execute on function public.rpc_compute_divergence(uuid) from public;
grant  execute on function public.rpc_compute_divergence(uuid) to authenticated, service_role;
