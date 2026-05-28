-- team_definition_engine — Phase 1 Step 3.
--
-- Adds the behavior on top of the Step 1 team-definition tables:
--   compute_role_definition_divergence — surfaces per-criterion spread
--                                        (never silently averages).
--   reconcile_role_definition          — produces a final weighted,
--                                        attributable, signed-off role version.
--
-- HARD RULE: this is rating of role *criteria*, not rating of people. The
-- reconcile RPC never reads or writes any peer-personality table — and per
-- CLAUDE.md, no such table exists. A guard test in supabase/tests checks
-- that no table with a peer-personality-shaped name has crept in.

-- ---- compute_role_definition_divergence --------------------------------
-- Read-only. SECURITY DEFINER so it bypasses RLS on role_definition_evaluations
-- (the caller may not have access to others' rows pre-reconciliation; the
-- function is the controlled aggregator).

create or replace function public.compute_role_definition_divergence(
  p_requisition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_by_criterion jsonb;
  v_eval_count   int;
begin
  -- Count distinct submitted evaluators.
  select count(distinct rde.evaluator_id)
    into v_eval_count
    from public.role_definition_evaluations rde
    where rde.requisition_id = p_requisition_id
      and rde.submitted_at is not null;

  -- Per-criterion stats from the flattened ratings.
  with flat as (
    select
      (r.value->>'criterion')                   as criterion,
      (r.value->>'importance')::numeric         as importance,
      rde.evaluator_id                          as evaluator_id
    from public.role_definition_evaluations rde
    cross join lateral jsonb_array_elements(rde.ratings_json) as r
    where rde.requisition_id = p_requisition_id
      and rde.submitted_at is not null
  ),
  per_crit as (
    select
      criterion,
      jsonb_build_object(
        'min',                       min(importance),
        'max',                       max(importance),
        'mean',                      round(avg(importance), 4),
        'stddev',                    round(coalesce(stddev_pop(importance), 0), 4),
        'n',                         count(*),
        'contributing_evaluator_ids', jsonb_agg(distinct evaluator_id)
      ) as stats
    from flat
    group by criterion
  )
  select coalesce(jsonb_object_agg(criterion, stats), '{}'::jsonb)
    into v_by_criterion
    from per_crit;

  return jsonb_build_object(
    'by_criterion',    coalesce(v_by_criterion, '{}'::jsonb),
    'evaluator_count', v_eval_count,
    'generated_at',    now()
  );
end;
$$;

revoke execute on function public.compute_role_definition_divergence(uuid) from public;
grant  execute on function public.compute_role_definition_divergence(uuid) to authenticated, service_role;
comment on function public.compute_role_definition_divergence(uuid) is
  'Per-criterion divergence (min/max/mean/stddev/n) across all SUBMITTED evaluations for a requisition. Surfaces spread; does not silently average.';

-- ---- reconcile_role_definition -----------------------------------------
-- Produces a final, weighted, attributable, signed-off role version.
-- The reconciler must hold team_definition.reconcile in the requisition's org.
-- The reconciled weights MUST sum to ~1.0 (±0.001).
-- The minimum evaluators threshold defaults to 2; org_modules.config_json.min_evaluators overrides.
-- This RPC inlines the role-version INSERT (rather than calling role_version_create)
-- so reconcilers without direct role.create can still produce versions via this
-- gated path. The new version is born status='active' and signed_off_by=reconciler.

create or replace function public.reconcile_role_definition(
  p_requisition_id      uuid,
  p_reconciled_weights  jsonb
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller          uuid := (select auth.uid());
  v_actor_id        uuid;
  v_req             public.requisitions%rowtype;
  v_role            public.roles_catalog%rowtype;
  v_min_evaluators  int := 2;
  v_submitted_count int;
  v_weight_sum      numeric;
  v_divergence      jsonb;
  v_new_role_id     uuid;
  v_recon_id        uuid;
  v_new_def         jsonb;
  v_module_config   jsonb;
begin
  -- Load requisition.
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then
    raise exception 'reconcile_role_definition: requisition not found (id=%)', p_requisition_id;
  end if;

  -- AuthZ.
  if v_caller is not null then
    if not public.has_permission(v_req.org_id, 'team_definition.reconcile') then
      raise exception 'reconcile_role_definition: caller lacks team_definition.reconcile in org';
    end if;
  end if;

  -- Validate weights shape.
  if jsonb_typeof(p_reconciled_weights) <> 'array' then
    raise exception 'reconcile_role_definition: p_reconciled_weights must be a JSON array';
  end if;

  -- Validate weight sum ≈ 1.0.
  select coalesce(sum((w->>'weight')::numeric), 0)
    into v_weight_sum
    from jsonb_array_elements(p_reconciled_weights) as w;
  if abs(v_weight_sum - 1.0) > 0.001 then
    raise exception 'reconcile_role_definition: weights must sum to 1.0 (±0.001); got %', v_weight_sum;
  end if;

  -- Read min_evaluators from org_modules config, default 2.
  select config_json into v_module_config
    from public.org_modules
    where org_id = v_req.org_id
      and module_key = 'team_definition'
      and enabled = true;
  if v_module_config is not null and (v_module_config ? 'min_evaluators') then
    v_min_evaluators := (v_module_config->>'min_evaluators')::int;
  end if;

  -- Check submitted-evaluator threshold.
  select count(distinct evaluator_id)
    into v_submitted_count
    from public.role_definition_evaluations
    where requisition_id = p_requisition_id
      and submitted_at is not null;
  if v_submitted_count < v_min_evaluators then
    raise exception 'reconcile_role_definition: need % submitted evaluators, got %',
      v_min_evaluators, v_submitted_count;
  end if;

  -- Compute divergence snapshot.
  v_divergence := public.compute_role_definition_divergence(p_requisition_id);

  -- Load the role currently on the requisition.
  select * into v_role from public.roles_catalog where id = v_req.role_id;
  if not found then
    raise exception 'reconcile_role_definition: requisition has no role attached';
  end if;

  -- Build the new definition_json: replace competencies with reconciled weights;
  -- keep trait_targets and other fields unchanged.
  v_new_def := jsonb_set(
    v_role.definition_json,
    '{competencies}',
    (
      select jsonb_agg(
        jsonb_build_object(
          'key',    w->>'criterion',
          'weight', (w->>'weight')::numeric
        )
      )
      from jsonb_array_elements(p_reconciled_weights) as w
    )
  );

  -- Resolve actor.
  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  -- Inline the version INSERT so a reconciler without direct role.create can produce
  -- a signed-off version through this gated path. authored_by_json carries full
  -- attribution (the reconciler + all submitted evaluators).
  insert into public.roles_catalog (
    org_id, title, family,
    is_template, template_source_id,
    version, status,
    definition_json, authored_by_json,
    signed_off_by, signed_off_at,
    supersedes_id
  ) values (
    v_role.org_id, v_role.title, v_role.family,
    false, v_role.template_source_id,
    v_role.version + 1, 'active',
    v_new_def,
    (
      select jsonb_build_object(
        'reconciled_by',  v_actor_id,
        'reconciled_at',  now(),
        'evaluators',     coalesce(jsonb_agg(distinct evaluator_id), '[]'::jsonb)
      )
      from public.role_definition_evaluations
      where requisition_id = p_requisition_id and submitted_at is not null
    ),
    v_actor_id, now(),
    v_role.id
  )
  returning id into v_new_role_id;

  -- Record the reconciliation event.
  insert into public.role_definition_reconciliations (
    org_id, requisition_id,
    divergence_json, reconciled_json,
    produced_role_id, reconciled_by, reconciled_at
  ) values (
    v_req.org_id, p_requisition_id,
    v_divergence, p_reconciled_weights,
    v_new_role_id, v_actor_id, now()
  )
  returning id into v_recon_id;

  return v_recon_id;
end;
$$;

revoke execute on function public.reconcile_role_definition(uuid, jsonb) from public;
grant  execute on function public.reconcile_role_definition(uuid, jsonb) to authenticated, service_role;
comment on function public.reconcile_role_definition(uuid, jsonb) is
  'Produces a signed-off role version from independent evaluator ratings. Records the divergence snapshot, the reconciled weights, and full attribution. Enforces min_evaluators threshold and weight-sum ≈ 1.0.';
