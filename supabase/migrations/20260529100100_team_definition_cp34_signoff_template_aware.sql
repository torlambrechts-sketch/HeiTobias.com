-- CP3.4 fix-up to CP3.1's rpc_signoff_role_version.
--
-- The CP3.1 implementation forwarded role_template_id straight into
-- role_version_create. But role_version_create refuses templates
-- (is_template=true), which is the common case for initial_definition
-- runs that seed from the catalog's sample templates.
--
-- This replacement branches by source role kind:
--   * template (is_template=true) OR null source → INSERT a new
--     instance row directly (version=1, is_template=false), seeded
--     with the run's reconciled draft_definition_json + provenance.
--   * existing instance (is_template=false) → keep role_version_create
--     as before, which sets version = old.version + 1.
--
-- The provenance JSON shape stays identical so the test in
-- 34_team_definition_cp34_reconciliation_signoff.sql (T29b) and any
-- downstream readers don't have to change.

create or replace function public.rpc_signoff_role_version(
  p_run_id uuid,
  p_rationale text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller     uuid := (select auth.uid());
  v_actor      uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_run        public.team_definition_runs%rowtype;
  v_src        public.roles_catalog%rowtype;
  v_new_role   uuid;
  v_provenance jsonb;
  v_definition jsonb;
  v_title      text;
  v_family     text;
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

  v_definition := jsonb_set(coalesce(v_run.draft_definition_json, '{}'::jsonb),
                            '{validation_and_defensibility_metadata}', v_provenance, true);

  -- Branch on the source role kind.
  if v_run.role_template_id is not null then
    select * into v_src from public.roles_catalog where id = v_run.role_template_id;
    if not found then
      raise exception 'rpc_signoff_role_version: role_template_id % no longer in roles_catalog', v_run.role_template_id;
    end if;
  end if;

  if v_run.role_template_id is null or v_src.is_template then
    -- Template or no source: create a fresh instance for the org.
    v_title  := coalesce(v_src.title, v_run.role_family);
    v_family := coalesce(v_src.family, v_run.role_family);
    insert into public.roles_catalog (
      org_id, title, family,
      is_template, template_source_id,
      version, status,
      definition_json, authored_by_json,
      supersedes_id
    ) values (
      v_run.org_id, v_title, v_family,
      false, v_run.role_template_id,
      1, 'draft',
      v_definition, '[]'::jsonb,
      null
    )
    returning id into v_new_role;
  else
    -- Existing instance: bump version via the standard helper.
    v_new_role := public.role_version_create(v_run.role_template_id, v_definition);
  end if;

  update public.team_definition_runs set
    stage = 'signed_off',
    target_role_version_id = v_new_role,
    completed_at = now(),
    updated_at = now()
  where id = p_run_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_run.org_id, v_actor, 'team_def.signed_off', 'team_definition_runs', p_run_id,
            jsonb_build_object('new_role_version_id', v_new_role, 'from_template', v_run.role_template_id is not null and v_src.is_template));
  return v_new_role;
end;
$$;
revoke execute on function public.rpc_signoff_role_version(uuid, text) from public;
grant  execute on function public.rpc_signoff_role_version(uuid, text) to authenticated, service_role;
