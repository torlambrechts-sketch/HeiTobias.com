-- phase4_step7_monitoring — drift / fairness-over-time / retrain-trigger
-- + incident scaffold. Phase 4 §7.
--
-- Two load-bearing rules:
--
--   * NOTHING AUTO-REMEDIATES A PEOPLE DECISION. monitoring_alerts.status
--     enum has NO 'auto_remediated' value — the only transitions are
--     'open' → 'acknowledged' → 'resolved', and both require an
--     authenticated person + a note (chk_ack_requires_human,
--     chk_resolve_requires_human). Alerts inform humans; humans close
--     them.
--
--   * RETRAIN MUST CARRY A BIAS RE-AUDIT. monitoring_incidents has
--     bias_reaudit_fairness_run_id pointing at a fairness_runs row. A
--     retrain incident without that reference is permitted (e.g. for
--     a non-people model), but for the people-affecting models the UI
--     + monitoring loop will enforce its presence (SCIENCE-SPEC §10
--     "mandatory bias re-audit on retrain").

create table public.monitoring_runs (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  model_id        uuid references public.model_registry(id),
  kind            text not null check (kind in (
                    'input_drift','output_drift','fairness_overtime',
                    'retrain_trigger_check','calibration_check'
                  )),
  ran_at          timestamptz not null default now(),
  payload_json    jsonb not null default '{}'::jsonb,
  triggered_alert boolean not null default false,
  retrain_triggered boolean not null default false,
  _dev_stub       boolean not null default true,
  created_at      timestamptz not null default now()
);
create index monitoring_runs_org_idx on public.monitoring_runs (org_id, ran_at desc);
create index monitoring_runs_model_idx on public.monitoring_runs (model_id, ran_at desc);
create trigger trg_audit_monitoring_runs after insert or update or delete on public.monitoring_runs
  for each row execute function public._audit_row();
alter table public.monitoring_runs enable row level security;
alter table public.monitoring_runs force  row level security;
create policy monitoring_runs_select on public.monitoring_runs for select using (
  public.has_permission(org_id, 'modeling.read')
);
create policy monitoring_runs_write on public.monitoring_runs for all
  using (public.has_permission(org_id, 'modeling.write'))
  with check (public.has_permission(org_id, 'modeling.write'));

create table public.monitoring_alerts (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  run_id          uuid references public.monitoring_runs(id),
  severity        text not null check (severity in ('info','warning','high','critical')),
  message         text not null,
  payload_json    jsonb not null default '{}'::jsonb,
  status          text not null default 'open'
                  check (status in ('open','acknowledged','resolved')),
  acknowledged_by uuid references public.people(id),
  acknowledged_at timestamptz,
  ack_note        text,
  resolved_by     uuid references public.people(id),
  resolved_at     timestamptz,
  resolve_note    text,
  opened_at       timestamptz not null default now(),
  _dev_stub       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint chk_ack_requires_human
    check (status <> 'acknowledged' or (acknowledged_by is not null and acknowledged_at is not null)),
  constraint chk_resolve_requires_human
    check (status <> 'resolved' or (resolved_by is not null and resolved_at is not null
                                    and resolve_note is not null and length(resolve_note) >= 10))
);
create index monitoring_alerts_org_idx on public.monitoring_alerts (org_id, opened_at desc);
create trigger trg_touch_monitoring_alerts before update on public.monitoring_alerts
  for each row execute function public.set_updated_at();
create trigger trg_audit_monitoring_alerts after insert or update or delete on public.monitoring_alerts
  for each row execute function public._audit_row();
alter table public.monitoring_alerts enable row level security;
alter table public.monitoring_alerts force  row level security;
create policy monitoring_alerts_select on public.monitoring_alerts for select using (
  public.has_permission(org_id, 'modeling.read')
);
create policy monitoring_alerts_write on public.monitoring_alerts for all
  using (public.has_permission(org_id, 'modeling.write'))
  with check (public.has_permission(org_id, 'modeling.write'));

create table public.monitoring_incidents (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  model_id        uuid references public.model_registry(id),
  alert_id        uuid references public.monitoring_alerts(id),
  summary         text not null check (length(summary) >= 20),
  opened_by       uuid not null references public.people(id),
  opened_at       timestamptz not null default now(),
  bias_reaudit_fairness_run_id uuid references public.fairness_runs(id),
  resolved_at     timestamptz,
  resolved_by     uuid references public.people(id),
  resolution_note text,
  _dev_stub       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index monitoring_incidents_org_idx on public.monitoring_incidents (org_id, opened_at desc);
create trigger trg_touch_monitoring_incidents before update on public.monitoring_incidents
  for each row execute function public.set_updated_at();
create trigger trg_audit_monitoring_incidents after insert or update or delete on public.monitoring_incidents
  for each row execute function public._audit_row();
alter table public.monitoring_incidents enable row level security;
alter table public.monitoring_incidents force  row level security;
create policy monitoring_incidents_select on public.monitoring_incidents for select using (
  public.has_permission(org_id, 'modeling.read')
);
create policy monitoring_incidents_write on public.monitoring_incidents for all
  using (public.has_permission(org_id, 'modeling.write'))
  with check (public.has_permission(org_id, 'modeling.write'));
