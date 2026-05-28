-- The previous reconcile_role_definition wrote authored_by_json as a single
-- JSON object. roles_catalog.chk_role_authored_by_shape (Phase 0) requires
-- authored_by_json to be a JSON ARRAY. Wrap the attribution in an array:
-- one record for the reconciliation event itself, plus one per submitted
-- evaluator.

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
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then
    raise exception 'reconcile_role_definition: requisition not found (id=%)', p_requisition_id;
  end if;

  if v_caller is not null then
    if not public.has_permission(v_req.org_id, 'team_definition.reconcile') then
      raise exception 'reconcile_role_definition: caller lacks team_definition.reconcile in org';
    end if;
  end if;

  if jsonb_typeof(p_reconciled_weights) <> 'array' then
    raise exception 'reconcile_role_definition: p_reconciled_weights must be a JSON array';
  end if;

  select coalesce(sum((w->>'weight')::numeric), 0) into v_weight_sum
    from jsonb_array_elements(p_reconciled_weights) as w;
  if abs(v_weight_sum - 1.0) > 0.001 then
    raise exception 'reconcile_role_definition: weights must sum to 1.0 (±0.001); got %', v_weight_sum;
  end if;

  select config_json into v_module_config
    from public.org_modules
    where org_id = v_req.org_id and module_key = 'team_definition' and enabled = true;
  if v_module_config is not null and (v_module_config ? 'min_evaluators') then
    v_min_evaluators := (v_module_config->>'min_evaluators')::int;
  end if;

  select count(distinct evaluator_id) into v_submitted_count
    from public.role_definition_evaluations
    where requisition_id = p_requisition_id and submitted_at is not null;
  if v_submitted_count < v_min_evaluators then
    raise exception 'reconcile_role_definition: need % submitted evaluators, got %',
      v_min_evaluators, v_submitted_count;
  end if;

  v_divergence := public.compute_role_definition_divergence(p_requisition_id);

  select * into v_role from public.roles_catalog where id = v_req.role_id;
  if not found then
    raise exception 'reconcile_role_definition: requisition has no role attached';
  end if;

  v_new_def := jsonb_set(
    v_role.definition_json,
    '{competencies}',
    (
      select jsonb_agg(jsonb_build_object('key', w->>'criterion', 'weight', (w->>'weight')::numeric))
      from jsonb_array_elements(p_reconciled_weights) as w
    )
  );

  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

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
    -- authored_by_json: ARRAY (chk_role_authored_by_shape requires array).
    jsonb_build_array(
      jsonb_build_object('kind','reconciliation','reconciled_by',v_actor_id,'reconciled_at',now())
    )
    || coalesce(
      (
        select jsonb_agg(jsonb_build_object('kind','evaluator','evaluator_id',evaluator_id))
        from public.role_definition_evaluations
        where requisition_id = p_requisition_id and submitted_at is not null
      ),
      '[]'::jsonb
    ),
    v_actor_id, now(),
    v_role.id
  )
  returning id into v_new_role_id;

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
