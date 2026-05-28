-- phase4_step7_monitoring_functions — record / open / acknowledge /
-- resolve RPCs. None of these auto-remediate a people decision; they
-- inform humans and require human-attributable closure.

create or replace function public.monitoring_run_record(
  p_org_id uuid, p_model_id uuid, p_kind text,
  p_payload jsonb default '{}'::jsonb,
  p_triggered_alert boolean default false,
  p_retrain_triggered boolean default false
)
returns uuid language plpgsql set search_path = '' security definer
as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_id uuid;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'monitoring_run_record: caller lacks modeling.write';
  end if;
  insert into public.monitoring_runs (org_id, model_id, kind, payload_json, triggered_alert, retrain_triggered, _dev_stub)
    values (p_org_id, p_model_id, p_kind, coalesce(p_payload,'{}'::jsonb), p_triggered_alert, p_retrain_triggered, true)
    returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'monitoring.run', 'monitoring_runs', v_id,
            jsonb_build_object('kind', p_kind, 'triggered_alert', p_triggered_alert, 'retrain_triggered', p_retrain_triggered, '_dev_stub', true));
  return v_id;
end;
$$;
revoke execute on function public.monitoring_run_record(uuid, uuid, text, jsonb, boolean, boolean) from public;
grant  execute on function public.monitoring_run_record(uuid, uuid, text, jsonb, boolean, boolean) to authenticated, service_role;

create or replace function public.monitoring_alert_open(
  p_org_id uuid, p_severity text, p_message text,
  p_run_id uuid default null, p_payload jsonb default '{}'::jsonb
)
returns uuid language plpgsql set search_path = '' security definer
as $$
declare v_caller uuid := (select auth.uid()); v_id uuid;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'monitoring_alert_open: caller lacks modeling.write';
  end if;
  insert into public.monitoring_alerts (org_id, run_id, severity, message, payload_json, _dev_stub)
    values (p_org_id, p_run_id, p_severity, p_message, coalesce(p_payload,'{}'::jsonb), true)
    returning id into v_id;
  insert into public.audit_log (org_id, action, entity_type, entity_id, after_json)
    values (p_org_id, 'monitoring.alert_opened', 'monitoring_alerts', v_id,
            jsonb_build_object('severity', p_severity, '_dev_stub', true));
  return v_id;
end;
$$;
revoke execute on function public.monitoring_alert_open(uuid, text, text, uuid, jsonb) from public;
grant  execute on function public.monitoring_alert_open(uuid, text, text, uuid, jsonb) to authenticated, service_role;

create or replace function public.monitoring_alert_acknowledge(
  p_alert_id uuid, p_note text
)
returns uuid language plpgsql set search_path = '' security definer
as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_org uuid;
begin
  select org_id into v_org from public.monitoring_alerts where id = p_alert_id;
  if v_org is null then raise exception 'monitoring_alert_acknowledge: alert not found'; end if;
  if v_caller is null then
    raise exception 'monitoring_alert_acknowledge: requires authenticated person (humans only)';
  end if;
  if not public.has_permission(v_org, 'modeling.write') then
    raise exception 'monitoring_alert_acknowledge: caller lacks modeling.write';
  end if;
  if p_note is null or length(p_note) < 10 then
    raise exception 'monitoring_alert_acknowledge: note >=10 chars';
  end if;
  update public.monitoring_alerts set
    status = 'acknowledged', acknowledged_by = v_actor, acknowledged_at = now(), ack_note = p_note, updated_at = now()
  where id = p_alert_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'monitoring.alert_acknowledged', 'monitoring_alerts', p_alert_id,
            jsonb_build_object('ack_by', v_actor));
  return p_alert_id;
end;
$$;
revoke execute on function public.monitoring_alert_acknowledge(uuid, text) from public;
grant  execute on function public.monitoring_alert_acknowledge(uuid, text) to authenticated, service_role;

create or replace function public.monitoring_alert_resolve(
  p_alert_id uuid, p_note text
)
returns uuid language plpgsql set search_path = '' security definer
as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_org uuid;
begin
  select org_id into v_org from public.monitoring_alerts where id = p_alert_id;
  if v_org is null then raise exception 'monitoring_alert_resolve: alert not found'; end if;
  if v_caller is null then
    raise exception 'monitoring_alert_resolve: requires authenticated person (humans only)';
  end if;
  if not public.has_permission(v_org, 'modeling.write') then
    raise exception 'monitoring_alert_resolve: caller lacks modeling.write';
  end if;
  if p_note is null or length(p_note) < 10 then
    raise exception 'monitoring_alert_resolve: note >=10 chars';
  end if;
  update public.monitoring_alerts set
    status = 'resolved', resolved_by = v_actor, resolved_at = now(), resolve_note = p_note, updated_at = now()
  where id = p_alert_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'monitoring.alert_resolved', 'monitoring_alerts', p_alert_id,
            jsonb_build_object('resolved_by', v_actor));
  return p_alert_id;
end;
$$;
revoke execute on function public.monitoring_alert_resolve(uuid, text) from public;
grant  execute on function public.monitoring_alert_resolve(uuid, text) to authenticated, service_role;

create or replace function public.monitoring_incident_open(
  p_org_id uuid, p_summary text, p_model_id uuid default null,
  p_alert_id uuid default null, p_bias_reaudit_fairness_run_id uuid default null
)
returns uuid language plpgsql set search_path = '' security definer
as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1); v_id uuid;
begin
  if v_caller is null then
    raise exception 'monitoring_incident_open: requires authenticated person';
  end if;
  if not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'monitoring_incident_open: caller lacks modeling.write';
  end if;
  if v_actor is null then
    raise exception 'monitoring_incident_open: no person row for caller';
  end if;
  if p_summary is null or length(p_summary) < 20 then
    raise exception 'monitoring_incident_open: summary >=20 chars';
  end if;
  insert into public.monitoring_incidents (org_id, model_id, alert_id, summary, opened_by, bias_reaudit_fairness_run_id, _dev_stub)
    values (p_org_id, p_model_id, p_alert_id, p_summary, v_actor, p_bias_reaudit_fairness_run_id, true)
    returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'monitoring.incident_opened', 'monitoring_incidents', v_id,
            jsonb_build_object('opened_by', v_actor, 'has_bias_reaudit', p_bias_reaudit_fairness_run_id is not null));
  return v_id;
end;
$$;
revoke execute on function public.monitoring_incident_open(uuid, text, uuid, uuid, uuid) from public;
grant  execute on function public.monitoring_incident_open(uuid, text, uuid, uuid, uuid) to authenticated, service_role;
