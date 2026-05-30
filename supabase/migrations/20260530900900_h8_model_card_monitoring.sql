-- H-8 — Model Card + Monitoring Discipline (Run 10 of H-1..H-10)
--
-- Model card discipline (EU AI Act Art. 11/13/14 — technical
-- documentation, transparency, human oversight). A model card cannot
-- be promoted to validated without:
--   * substantive intended_use (≥100 chars)
--   * non-empty limits_json
--   * non-empty data_lineage_json
--   * non-null fairness_metrics_json
--   * substantive ethical_considerations (≥100 chars)
--   * monitoring_plan_json (added in this run)
--   * human_oversight_plan text (added in this run, Art. 14)
--   * transparency_disclosures_text (added in this run, Art. 13)
--   * modeling.signoff actor + at + rationale ≥100 chars
--
-- Monitoring discipline:
--   * Alert status enum: open | acknowledged | resolved | suppressed
--   * Alert severity enum: info | warning | critical
--   * RPC for ack + resolve
--   * Incident close requires bias_reaudit_fairness_run_id linked
--     (so any monitoring incident closure has a fresh fairness audit
--     trail backing it)

-- ─── 1. Extend model_cards ──────────────────────────────────────────
alter table public.model_cards
  add column if not exists monitoring_plan_json         jsonb,
  add column if not exists human_oversight_plan         text,
  add column if not exists transparency_disclosures_text text,
  add column if not exists signoff_rationale            text;

alter table public.model_cards
  drop constraint if exists mc_intended_use_min_len,
  drop constraint if exists mc_ethics_min_len,
  drop constraint if exists mc_oversight_min_len,
  drop constraint if exists mc_transparency_min_len,
  drop constraint if exists mc_signoff_rationale_len,
  drop constraint if exists mc_validated_requires_full;

alter table public.model_cards
  add constraint mc_intended_use_min_len check (
    intended_use is null or length(intended_use) >= 30),
  add constraint mc_ethics_min_len check (
    ethical_considerations is null or length(ethical_considerations) >= 30),
  add constraint mc_oversight_min_len check (
    human_oversight_plan is null or length(human_oversight_plan) >= 30),
  add constraint mc_transparency_min_len check (
    transparency_disclosures_text is null or length(transparency_disclosures_text) >= 30),
  add constraint mc_signoff_rationale_len check (
    signoff_rationale is null or length(signoff_rationale) >= 100),
  add constraint mc_validated_requires_full check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and intended_use is not null and length(intended_use) >= 100
      and limits_json is not null and limits_json <> '{}'::jsonb
      and data_lineage_json is not null and data_lineage_json <> '{}'::jsonb
      and fairness_metrics_json is not null
      and ethical_considerations is not null and length(ethical_considerations) >= 100
      and human_oversight_plan is not null and length(human_oversight_plan) >= 30
      and transparency_disclosures_text is not null and length(transparency_disclosures_text) >= 30
      and monitoring_plan_json is not null
      and signed_off_by is not null
      and signed_off_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    ));

-- ─── 2. Extend monitoring_alerts: enums for status + severity ──────
alter table public.monitoring_alerts
  drop constraint if exists ma_status_enum,
  drop constraint if exists ma_severity_enum;

alter table public.monitoring_alerts
  add constraint ma_status_enum check (
    status is null or status in ('open','acknowledged','resolved','suppressed')),
  add constraint ma_severity_enum check (
    severity is null or severity in ('info','warning','critical'));

create index if not exists ma_status_idx on public.monitoring_alerts(status);
create index if not exists ma_severity_idx on public.monitoring_alerts(severity);
create index if not exists ma_open_idx on public.monitoring_alerts(opened_at)
  where status in ('open','acknowledged');

-- ─── 3. RPC: model card sign-off ────────────────────────────────────
create or replace function public.rpc_model_card_signoff(
  p_card_id            uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_caller_person_id uuid;
  v_card             public.model_cards%rowtype;
  v_model            public.model_registry%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_card from public.model_cards where id = p_card_id for update;
  if not found then
    raise exception 'model_card % not found', p_card_id using errcode='P0002';
  end if;
  select * into v_model from public.model_registry where id = v_card.model_id;
  if v_model.id is null then
    raise exception 'model_card has orphan model_id %', v_card.model_id using errcode='P0002';
  end if;
  if not public.has_permission(v_model.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_model.org_id using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;

  -- Per-field gates (mirror the CHECK so we give friendly errors)
  if v_card.intended_use is null or length(v_card.intended_use) < 100 then
    raise exception 'intended_use must be >=100 chars for validated card' using errcode='22023'; end if;
  if v_card.ethical_considerations is null or length(v_card.ethical_considerations) < 100 then
    raise exception 'ethical_considerations must be >=100 chars' using errcode='22023'; end if;
  if v_card.human_oversight_plan is null then
    raise exception 'human_oversight_plan required (AI Act Art. 14)' using errcode='22023'; end if;
  if v_card.transparency_disclosures_text is null then
    raise exception 'transparency_disclosures_text required (AI Act Art. 13)' using errcode='22023'; end if;
  if v_card.monitoring_plan_json is null then
    raise exception 'monitoring_plan_json required' using errcode='22023'; end if;
  if v_card.fairness_metrics_json is null then
    raise exception 'fairness_metrics_json required' using errcode='22023'; end if;

  update public.model_cards
     set validity_status='validated', _dev_stub=false,
         signed_off_by=v_caller_person_id, signed_off_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_card_id;

  perform public.audit_log_event(
    v_model.org_id, 'model_card.signoff', 'model_card', p_card_id, to_jsonb(v_card),
    jsonb_build_object('signed_off_by', v_caller_person_id, 'signed_off_at', now(),
      'rationale_length', length(p_decision_rationale),
      'model_id', v_card.model_id), null);

  return jsonb_build_object('ok', true, 'card_id', p_card_id,
    'validity_status', 'validated', 'signed_off_by', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_model_card_signoff(uuid, text) from public;
grant execute on function public.rpc_model_card_signoff(uuid, text) to authenticated, service_role;

-- ─── 4. RPCs: alert ack + resolve ───────────────────────────────────
create or replace function public.rpc_monitoring_alert_acknowledge(
  p_alert_id uuid, p_note text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.monitoring_alerts%rowtype;
begin
  select * into v_row from public.monitoring_alerts where id = p_alert_id for update;
  if not found then
    raise exception 'alert % not found', p_alert_id using errcode='P0002';
  end if;
  if not public.has_permission(v_row.org_id, 'modeling.read') then
    raise exception 'denied: modeling.read required in org %', v_row.org_id using errcode='42501';
  end if;
  if v_row.status <> 'open' then
    raise exception 'alert is % (only open alerts can be acknowledged)', v_row.status using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;
  update public.monitoring_alerts
     set status='acknowledged', acknowledged_by=v_caller, acknowledged_at=now(),
         ack_note=p_note, updated_at=now()
   where id = p_alert_id;
  perform public.audit_log_event(
    v_row.org_id, 'monitoring_alert.ack', 'monitoring_alert', p_alert_id, to_jsonb(v_row),
    jsonb_build_object('acknowledged_by', v_caller, 'note', p_note), null);
  return jsonb_build_object('ok', true, 'alert_id', p_alert_id, 'status', 'acknowledged');
end;
$$;

revoke all on function public.rpc_monitoring_alert_acknowledge(uuid, text) from public;
grant execute on function public.rpc_monitoring_alert_acknowledge(uuid, text) to authenticated, service_role;

create or replace function public.rpc_monitoring_alert_resolve(
  p_alert_id uuid, p_note text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.monitoring_alerts%rowtype;
begin
  if p_note is null or length(trim(p_note)) < 20 then
    raise exception 'resolve note must be at least 20 characters' using errcode='22023';
  end if;
  select * into v_row from public.monitoring_alerts where id = p_alert_id for update;
  if not found then raise exception 'alert % not found', p_alert_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'modeling.write') then
    raise exception 'denied: modeling.write required' using errcode='42501';
  end if;
  if v_row.status not in ('open','acknowledged') then
    raise exception 'alert is % (cannot resolve)', v_row.status using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.monitoring_alerts
     set status='resolved', resolved_by=v_caller, resolved_at=now(),
         resolve_note=p_note, updated_at=now()
   where id = p_alert_id;
  perform public.audit_log_event(
    v_row.org_id, 'monitoring_alert.resolve', 'monitoring_alert', p_alert_id, to_jsonb(v_row),
    jsonb_build_object('resolved_by', v_caller, 'note', p_note), null);
  return jsonb_build_object('ok', true, 'alert_id', p_alert_id, 'status', 'resolved');
end;
$$;

revoke all on function public.rpc_monitoring_alert_resolve(uuid, text) from public;
grant execute on function public.rpc_monitoring_alert_resolve(uuid, text) to authenticated, service_role;

create or replace function public.rpc_monitoring_incident_close(
  p_incident_id uuid, p_resolution_note text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.monitoring_incidents%rowtype;
begin
  if p_resolution_note is null or length(trim(p_resolution_note)) < 50 then
    raise exception 'resolution note must be at least 50 characters' using errcode='22023';
  end if;
  select * into v_row from public.monitoring_incidents where id = p_incident_id for update;
  if not found then raise exception 'incident % not found', p_incident_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required to close incidents' using errcode='42501';
  end if;
  if v_row.bias_reaudit_fairness_run_id is null then
    raise exception 'cannot close incident without bias_reaudit_fairness_run_id linkage' using errcode='22023';
  end if;
  if v_row.resolved_at is not null then
    raise exception 'incident already closed at %', v_row.resolved_at using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.monitoring_incidents
     set resolved_at=now(), resolved_by=v_caller, resolution_note=p_resolution_note,
         updated_at=now()
   where id = p_incident_id;
  perform public.audit_log_event(
    v_row.org_id, 'monitoring_incident.close', 'monitoring_incident', p_incident_id, to_jsonb(v_row),
    jsonb_build_object('resolved_by', v_caller, 'note', p_resolution_note,
      'bias_reaudit_fairness_run_id', v_row.bias_reaudit_fairness_run_id), null);
  return jsonb_build_object('ok', true, 'incident_id', p_incident_id, 'closed', true);
end;
$$;

revoke all on function public.rpc_monitoring_incident_close(uuid, text) from public;
grant execute on function public.rpc_monitoring_incident_close(uuid, text) to authenticated, service_role;
