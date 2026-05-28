-- phase4_step6_compliance_functions — assemble + signoff RPCs.

create or replace function public.compliance_artifact_assemble(
  p_org_id   uuid,
  p_kind     text,
  p_key      text,
  p_scope_json jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller   uuid := (select auth.uid());
  v_actor    uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_id       uuid;
  v_models   jsonb;
  v_audits   jsonb;
  v_consents jsonb;
  v_fairness jsonb;
  v_roles    jsonb;
  v_rules    jsonb;
  v_payload  jsonb;
  r          record;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'compliance_artifact_assemble: caller lacks modeling.write';
  end if;

  insert into public.compliance_artifacts (org_id, kind, key, scope_json, payload_json, sign_off_status, _dev_stub)
    values (p_org_id, p_kind, p_key, coalesce(p_scope_json,'{}'::jsonb),
            '{}'::jsonb, 'draft', true)
    returning id into v_id;

  select coalesce(jsonb_agg(jsonb_build_object('key', key, 'regulation', regulation, 'article_ref', article_ref, 'effective_from', effective_from)
                            order by effective_from), '[]'::jsonb)
    into v_rules from public.compliance_rules where active = true;

  select coalesce(jsonb_agg(jsonb_build_object('model_id', mr.id, 'key', mr.key, 'family', mr.family,
                                               'version', mr.version, 'validity_status', mr.validity_status,
                                               '_dev_stub', mr._dev_stub,
                                               'card_signed_off_at', mc.signed_off_at)
                            order by mr.created_at desc), '[]'::jsonb)
    into v_models
    from public.model_registry mr left join public.model_cards mc on mc.model_id = mr.id
    where mr.org_id = p_org_id;
  for r in select mr.id from public.model_registry mr where mr.org_id = p_org_id loop
    insert into public.compliance_artifact_sources (artifact_id, source_table, source_id, source_kind)
      values (v_id, 'model_registry', r.id, 'model');
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('action', action, 'at', at, 'entity_type', entity_type)
                            order by at desc), '[]'::jsonb)
    into v_audits
    from (select action, at, entity_type from public.audit_log
          where org_id = p_org_id
            and action in ('model.registered','model_card.signed_off','model.training_run',
                           'fairness_run.opened','fairness_metric.interpreted',
                           'pareto_curve.computed','pareto_weight.chosen',
                           'invariance_run.recorded','invariance_verdict.recorded',
                           'dif_run.recorded','consent.granted','consent.revoked',
                           'placement.activated','hiring_decision.recorded',
                           'lifecycle_decision.recorded')
          order by at desc limit 200) a;
  for r in select id from public.audit_log
    where org_id = p_org_id and action in ('model.registered','model_card.signed_off','fairness_run.opened')
    order by at desc limit 50 loop
    insert into public.compliance_artifact_sources (artifact_id, source_table, source_id, source_kind)
      values (v_id, 'audit_log', r.id, 'audit_event');
  end loop;

  select coalesce(jsonb_object_agg(purpose, jsonb_build_object('active_count', cnt)), '{}'::jsonb)
    into v_consents
    from (select purpose, count(*) as cnt from public.consent_grants
          where granted_to_org_id = p_org_id and status = 'active' and revoked_at is null
          group by purpose) c;

  select coalesce(jsonb_agg(jsonb_build_object('run_id', fr.id, 'model_id', fr.model_id, 'computed_at', fr.computed_at,
                                               'metric_count', (select count(*) from public.fairness_metrics fm where fm.run_id = fr.id),
                                               'triggered_count', (select count(*) from public.fairness_metrics fm where fm.run_id = fr.id and fm.four_fifths_inspection_triggered),
                                               'interpreted_count', (select count(*) from public.fairness_metrics fm where fm.run_id = fr.id and fm.interpretation_by_expert is not null))
                            order by fr.computed_at desc), '[]'::jsonb)
    into v_fairness from public.fairness_runs fr where fr.org_id = p_org_id;

  select coalesce(jsonb_agg(jsonb_build_object('role_id', id, 'title', title, 'version', version,
                                               'status', status, 'is_template', is_template)
                            order by created_at desc), '[]'::jsonb)
    into v_roles from public.roles_catalog where org_id = p_org_id;

  v_payload := jsonb_build_object(
    '_dev_stub', true,
    'kind', p_kind,
    'assembled_at', now(),
    'assembled_by_person_id', v_actor,
    'note','DEV STUB — assembled from real logged data; expert legal sign-off REQUIRED before live use',
    'compliance_rules_active', v_rules,
    'models', v_models,
    'audit_summary', v_audits,
    'consent_snapshot', v_consents,
    'fairness_snapshot', v_fairness,
    'roles_catalog', v_roles,
    'self_attestation', null
  );

  update public.compliance_artifacts set payload_json = v_payload, updated_at = now() where id = v_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'compliance_artifact.assembled', 'compliance_artifacts', v_id,
            jsonb_build_object('kind', p_kind, '_dev_stub', true));

  return v_id;
end;
$$;
revoke execute on function public.compliance_artifact_assemble(uuid, text, text, jsonb) from public;
grant  execute on function public.compliance_artifact_assemble(uuid, text, text, jsonb) to authenticated, service_role;

create or replace function public.compliance_artifact_signoff(
  p_artifact_id uuid, p_attestation text, p_status text default 'signed'
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_org uuid;
begin
  select org_id into v_org from public.compliance_artifacts where id = p_artifact_id;
  if v_org is null then raise exception 'compliance_artifact_signoff: artifact not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'modeling.signoff') then
    raise exception 'compliance_artifact_signoff: requires modeling.signoff (legal/AI-Act seam)';
  end if;
  if p_status not in ('signed','rejected') then
    raise exception 'compliance_artifact_signoff: status must be signed or rejected';
  end if;
  if p_attestation is null or length(p_attestation) < 20 then
    raise exception 'compliance_artifact_signoff: attestation >=20 chars';
  end if;
  update public.compliance_artifacts set
    sign_off_status = p_status,
    signed_off_by   = v_actor,
    signed_off_at   = now(),
    attestation_text = p_attestation,
    updated_at      = now()
  where id = p_artifact_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'compliance_artifact.signed', 'compliance_artifacts', p_artifact_id,
            jsonb_build_object('status', p_status, 'signed_off_by', v_actor));
  return p_artifact_id;
end;
$$;
revoke execute on function public.compliance_artifact_signoff(uuid, text, text) from public;
grant  execute on function public.compliance_artifact_signoff(uuid, text, text) to authenticated, service_role;
