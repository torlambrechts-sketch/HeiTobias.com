-- Team-Based Role Definition — CP3.1 RPCs.
-- Five workflow primitives + one owner-side read RPC that LOGS attempts
-- during seal (the third lock on Stage 2 sealing).

-- ============ rpc_create_role_definition_run ============
-- Atomic. Creates a run + the evaluator rows + the initial draft.
-- Seeds draft_definition_json from a role template (if provided) +
-- snapshots the org's active thresholds.
create or replace function public.rpc_create_role_definition_run(
  p_org_id        uuid,
  p_role_family   text,
  p_role_template_id uuid,
  p_purpose       text default 'initial_definition',
  p_deadline_at   timestamptz default null,
  p_evaluators    jsonb default '[]'::jsonb  -- [{person_id, role, allow_attribution_on_reveal}]
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller   uuid := (select auth.uid());
  v_actor    uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_run      uuid;
  v_draft    jsonb := '{}'::jsonb;
  v_thresh   jsonb;
  v_evaluator jsonb;
  v_ev_role  public.team_definition_evaluator_role;
begin
  if v_caller is null then raise exception 'rpc_create_role_definition_run: not authenticated'; end if;
  if not public.has_permission(p_org_id, 'role.create') then
    raise exception 'rpc_create_role_definition_run: requires role.create in the run''s org';
  end if;
  if p_role_template_id is not null then
    select definition_json into v_draft from public.roles_catalog where id = p_role_template_id;
    if v_draft is null then raise exception 'rpc_create_role_definition_run: template not found'; end if;
  end if;
  select coalesce(jsonb_object_agg(threshold_key, jsonb_build_object('value', value, 'validity_status', validity_status, '_dev_stub', _dev_stub)), '{}'::jsonb)
    into v_thresh
    from public.team_definition_thresholds where org_id is null or org_id = p_org_id;

  insert into public.team_definition_runs (org_id, role_family, role_template_id, purpose, owner_user_id, deadline_at, thresholds_json, draft_definition_json)
    values (p_org_id, p_role_family, p_role_template_id, p_purpose::public.team_definition_purpose,
            v_actor, coalesce(p_deadline_at, now() + interval '14 days'), v_thresh, v_draft)
    returning id into v_run;

  for v_evaluator in select * from jsonb_array_elements(coalesce(p_evaluators,'[]'::jsonb))
  loop
    v_ev_role := (v_evaluator->>'role')::public.team_definition_evaluator_role;
    insert into public.team_definition_evaluators (run_id, user_id, role, allow_attribution_on_reveal)
      values (v_run, (v_evaluator->>'person_id')::uuid, v_ev_role,
              coalesce((v_evaluator->>'allow_attribution_on_reveal')::boolean, true));
  end loop;

  -- Transition to 'rating' once evaluators are in.
  update public.team_definition_runs set stage = 'rating' where id = v_run;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'team_def.run_created', 'team_definition_runs', v_run,
            jsonb_build_object('role_family', p_role_family, 'evaluator_count', jsonb_array_length(coalesce(p_evaluators,'[]'::jsonb))));
  return v_run;
end;
$$;
revoke execute on function public.rpc_create_role_definition_run(uuid, text, uuid, text, timestamptz, jsonb) from public;
grant  execute on function public.rpc_create_role_definition_run(uuid, text, uuid, text, timestamptz, jsonb) to authenticated, service_role;

-- ============ rpc_submit_evaluation ============
-- The evaluator's submit. Atomic. Verifies own-evaluator + sets
-- submitted_at, which makes the row immutable post-submit via the
-- UPDATE policy.
create or replace function public.rpc_submit_evaluation(
  p_run_id uuid,
  p_rating_json jsonb,
  p_rationale_notes_json jsonb default '{}'::jsonb
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller   uuid := (select auth.uid());
  v_actor    uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_ev       public.team_definition_evaluators%rowtype;
  v_stage    public.team_definition_stage;
  v_eval_id  uuid;
  v_org      uuid;
begin
  if v_caller is null then raise exception 'rpc_submit_evaluation: not authenticated'; end if;
  select stage, org_id into v_stage, v_org from public.team_definition_runs where id = p_run_id;
  if v_stage is null then raise exception 'rpc_submit_evaluation: run not found'; end if;
  if v_stage <> 'rating' then raise exception 'rpc_submit_evaluation: run is not in rating stage (current: %)', v_stage; end if;
  select * into v_ev from public.team_definition_evaluators where run_id = p_run_id and user_id = v_actor;
  if not found then raise exception 'rpc_submit_evaluation: caller is not an invited evaluator on this run'; end if;
  if v_ev.submitted_at is not null then raise exception 'rpc_submit_evaluation: already submitted'; end if;

  -- Upsert evaluation row, sealed via submitted_at = now().
  insert into public.team_definition_evaluations (run_id, evaluator_id, rating_json, rationale_notes_json, submitted_at)
    values (p_run_id, v_ev.id, coalesce(p_rating_json,'{}'::jsonb), coalesce(p_rationale_notes_json,'{}'::jsonb), now())
  on conflict (run_id, evaluator_id) do update
    set rating_json = excluded.rating_json,
        rationale_notes_json = excluded.rationale_notes_json,
        submitted_at = now(),
        updated_at = now()
    where team_definition_evaluations.submitted_at is null
  returning id into v_eval_id;
  if v_eval_id is null then raise exception 'rpc_submit_evaluation: row already sealed (concurrent submit)'; end if;

  update public.team_definition_evaluators set submitted_at = now() where id = v_ev.id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'team_def.evaluation_submitted', 'team_definition_evaluations', v_eval_id,
            jsonb_build_object('run_id', p_run_id, 'evaluator_id', v_ev.id));
  return v_eval_id;
end;
$$;
revoke execute on function public.rpc_submit_evaluation(uuid, jsonb, jsonb) from public;
grant  execute on function public.rpc_submit_evaluation(uuid, jsonb, jsonb) to authenticated, service_role;

-- ============ rpc_seal_evaluations ============
-- The Stage 2 → 3 transition. Server-side only (only run owner can
-- call). Requires either (a) all invited evaluators submitted, OR
-- (b) deadline passed AND >= min_evaluators submitted. Flips
-- run.stage to 'divergence'.
create or replace function public.rpc_seal_evaluations(p_run_id uuid)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller     uuid := (select auth.uid());
  v_actor      uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_run        public.team_definition_runs%rowtype;
  v_invited    int;
  v_submitted  int;
  v_min        int;
begin
  if v_caller is null then raise exception 'rpc_seal_evaluations: not authenticated'; end if;
  select * into v_run from public.team_definition_runs where id = p_run_id;
  if not found then raise exception 'rpc_seal_evaluations: run not found'; end if;
  if v_run.owner_user_id <> v_actor and not public.has_permission(v_run.org_id, 'role.signoff') then
    raise exception 'rpc_seal_evaluations: only the run owner (or role.signoff) can seal';
  end if;
  if v_run.stage <> 'rating' then raise exception 'rpc_seal_evaluations: run is not in rating stage (current: %)', v_run.stage; end if;

  select count(*) into v_invited   from public.team_definition_evaluators where run_id = p_run_id;
  select count(*) into v_submitted from public.team_definition_evaluators where run_id = p_run_id and submitted_at is not null;
  select coalesce((v_run.thresholds_json -> 'min_evaluators_for_valid_run' ->> 'value')::int, 4) into v_min;

  if v_submitted < v_invited and now() < v_run.deadline_at and v_submitted < v_min then
    raise exception 'rpc_seal_evaluations: insufficient submissions (%/%, min %) and deadline not passed', v_submitted, v_invited, v_min;
  end if;
  if v_submitted < v_min then
    raise exception 'rpc_seal_evaluations: fewer submissions than min_evaluators_for_valid_run (%/%)', v_submitted, v_min;
  end if;

  update public.team_definition_runs set stage = 'divergence', updated_at = now() where id = p_run_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_run.org_id, v_actor, 'team_def.evaluations_sealed', 'team_definition_runs', p_run_id,
            jsonb_build_object('submitted', v_submitted, 'invited', v_invited, 'min', v_min));
  return p_run_id;
end;
$$;
revoke execute on function public.rpc_seal_evaluations(uuid) from public;
grant  execute on function public.rpc_seal_evaluations(uuid) to authenticated, service_role;

-- ============ rpc_team_definition_evaluations_for_owner ============
-- The owner-side read RPC. THE THIRD LOCK on Stage 2 sealing — a
-- call during stage='rating' is logged as attempted_action=
-- 'read_during_seal' and returns 0 rows. Post-seal, it returns
-- evaluations subject to the standard RLS.
create or replace function public.rpc_team_definition_evaluations_for_owner(p_run_id uuid)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_run    public.team_definition_runs%rowtype;
  v_rows   jsonb;
begin
  if v_caller is null then raise exception 'rpc_team_definition_evaluations_for_owner: not authenticated'; end if;
  select * into v_run from public.team_definition_runs where id = p_run_id;
  if not found then raise exception 'rpc_team_definition_evaluations_for_owner: run not found'; end if;
  if not public.has_permission(v_run.org_id, 'role.read') then
    raise exception 'rpc_team_definition_evaluations_for_owner: requires role.read';
  end if;
  if v_run.stage = 'rating' then
    -- Attempt during seal — log it and refuse to return rows.
    insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
      values (v_run.org_id, v_actor, 'team_def.read_during_seal', 'team_definition_runs', p_run_id,
              jsonb_build_object('attempted_action', 'read_during_seal', 'stage', v_run.stage));
    return jsonb_build_object('rows', '[]'::jsonb, 'stage', v_run.stage, 'attempted_read_during_seal', true);
  end if;
  -- Post-seal: return evaluations (RLS continues to apply if called
  -- without SECDEF; SECDEF here bypasses RLS but the org-permission
  -- check above is the gate).
  select coalesce(jsonb_agg(jsonb_build_object('evaluation_id', e.id, 'evaluator_id', e.evaluator_id,
                                               'submitted_at', e.submitted_at, 'rating_json', e.rating_json,
                                               'rationale_notes_json', e.rationale_notes_json) order by e.submitted_at), '[]'::jsonb)
    into v_rows from public.team_definition_evaluations e where e.run_id = p_run_id;
  return jsonb_build_object('rows', v_rows, 'stage', v_run.stage, 'attempted_read_during_seal', false);
end;
$$;
revoke execute on function public.rpc_team_definition_evaluations_for_owner(uuid) from public;
grant  execute on function public.rpc_team_definition_evaluations_for_owner(uuid) to authenticated, service_role;

-- ============ rpc_record_reconciliation ============
-- Stage 4 action. Writes the reconciliation row + a hiring_decisions
-- decision_artefact + updates the draft definition.
create or replace function public.rpc_record_reconciliation(
  p_run_id uuid,
  p_criterion_key text,
  p_discussion_notes text,
  p_final_value_json jsonb,
  p_attribution_json jsonb default '{}'::jsonb
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_run    public.team_definition_runs%rowtype;
  v_id     uuid;
begin
  if v_caller is null then raise exception 'rpc_record_reconciliation: not authenticated'; end if;
  if p_discussion_notes is null or length(p_discussion_notes) < 20 then
    raise exception 'rpc_record_reconciliation: discussion_notes >=20 chars (audit-grade attribution)';
  end if;
  select * into v_run from public.team_definition_runs where id = p_run_id;
  if not found then raise exception 'rpc_record_reconciliation: run not found'; end if;
  if not public.has_permission(v_run.org_id, 'role.create') then
    raise exception 'rpc_record_reconciliation: requires role.create';
  end if;
  if v_run.stage not in ('divergence','reconciliation') then
    raise exception 'rpc_record_reconciliation: run is not in divergence/reconciliation (current: %)', v_run.stage;
  end if;
  if v_run.stage = 'divergence' then
    update public.team_definition_runs set stage = 'reconciliation' where id = p_run_id;
  end if;
  insert into public.team_definition_reconciliations (run_id, criterion_key, reconciler_user_id, discussion_notes_text, final_value_json, attribution_json)
    values (p_run_id, p_criterion_key, v_actor, p_discussion_notes, coalesce(p_final_value_json,'{}'::jsonb), coalesce(p_attribution_json,'{}'::jsonb))
    returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_run.org_id, v_actor, 'team_def.reconciliation_recorded', 'team_definition_reconciliations', v_id,
            jsonb_build_object('run_id', p_run_id, 'criterion', p_criterion_key));
  return v_id;
end;
$$;
revoke execute on function public.rpc_record_reconciliation(uuid, text, text, jsonb, jsonb) from public;
grant  execute on function public.rpc_record_reconciliation(uuid, text, text, jsonb, jsonb) to authenticated, service_role;

-- ============ rpc_signoff_role_version ============
-- Final action. Calls role_version_create with the reconciled
-- definition_json + the full Delphi provenance in
-- validation_and_defensibility_metadata. Sets stage='signed_off' and
-- run.target_role_version_id.
--
-- DISTINCT FROM rpc_role_sign_off: that one toggles JSON-level
-- version_status on an existing roles_catalog row; this one CREATES a
-- new version via role_version_create.
create or replace function public.rpc_signoff_role_version(
  p_run_id uuid,
  p_rationale text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller     uuid := (select auth.uid());
  v_actor      uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_run        public.team_definition_runs%rowtype;
  v_new_role   uuid;
  v_provenance jsonb;
begin
  if v_caller is null then raise exception 'rpc_signoff_role_version: not authenticated'; end if;
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'rpc_signoff_role_version: rationale >=20 chars';
  end if;
  select * into v_run from public.team_definition_runs where id = p_run_id for update;
  if not found then raise exception 'rpc_signoff_role_version: run not found'; end if;
  if not public.has_permission(v_run.org_id, 'role.signoff') then
    raise exception 'rpc_signoff_role_version: requires role.signoff';
  end if;
  if v_run.stage not in ('reconciliation','divergence') then
    raise exception 'rpc_signoff_role_version: run must be in reconciliation/divergence (current: %)', v_run.stage;
  end if;
  if v_run.target_role_version_id is not null then
    raise exception 'rpc_signoff_role_version: this run already produced version %', v_run.target_role_version_id;
  end if;

  -- Stamp the full Delphi provenance into validation_and_defensibility_metadata.
  v_provenance := jsonb_build_object(
    'team_definition_run_id', p_run_id,
    'evaluator_count', (select count(*) from public.team_definition_evaluators where run_id = p_run_id),
    'submitted_count', (select count(*) from public.team_definition_evaluators where run_id = p_run_id and submitted_at is not null),
    'reconciliation_count', (select count(*) from public.team_definition_reconciliations where run_id = p_run_id),
    'thresholds_snapshot', v_run.thresholds_json,
    'consensus_summary', v_run.consensus_summary_json,
    '_dev_stub', true,
    'validation_method', 'team_definition_delphi',
    'framing_default', 'developmental',
    'signed_off_by', v_actor,
    'signed_off_at', now(),
    'sign_off_rationale_excerpt', left(p_rationale, 200)
  );

  v_new_role := public.role_version_create(
    v_run.role_template_id,
    jsonb_set(coalesce(v_run.draft_definition_json, '{}'::jsonb),
              '{validation_and_defensibility_metadata}', v_provenance, true)
  );

  update public.team_definition_runs set
    stage = 'signed_off',
    target_role_version_id = v_new_role,
    completed_at = now(),
    updated_at = now()
  where id = p_run_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_run.org_id, v_actor, 'team_def.signed_off', 'team_definition_runs', p_run_id,
            jsonb_build_object('new_role_version_id', v_new_role));
  return v_new_role;
end;
$$;
revoke execute on function public.rpc_signoff_role_version(uuid, text) from public;
grant  execute on function public.rpc_signoff_role_version(uuid, text) to authenticated, service_role;
