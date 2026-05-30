-- H-9 + H-10 — EU AI Act Compliance + Legal Sign-Off (Run 11 of H-1..H-10)
--
-- Combines H-9 (EU AI Act Annex III / IV pipeline infrastructure) and
-- H-10 (legal.signoff permission + Mobley v. Workday vendor-as-
-- employment-agency precedent infrastructure).
--
-- H-9 work:
--   * Strict kind enum on compliance_artifacts (Annex IV technical
--     doc, DPIA, FRIA, instructions for use, validity dossier,
--     serious-incident report, vendor disclosure).
--   * validity_status on compliance_artifacts (was only _dev_stub).
--   * Two-key sign-off: modeling.signoff + legal.signoff. Both
--     required before an artifact transitions to validated.
--   * Annex III high-risk classification field per CHECK.
--
-- H-10 work:
--   * New rbac permission key: legal.signoff
--   * New table: vendor_acknowledgments (Mobley v. Workday precedent
--     — when an org integrates an AI vendor that touches employment
--     decisions, the vendor IS treated as an employment-agency under
--     emerging US/EU case law; this table records the org's
--     acknowledgment of vendor liability obligations).
--   * RPC rpc_compliance_artifact_signoff (dual gate).
--   * RPC rpc_vendor_acknowledgment_signoff.

-- ─── 1. Legal sign-off permission ───────────────────────────────────
insert into public.rbac_permissions (key, description)
values
  ('legal.signoff',
   'Sign off on compliance artifacts (DPIA, FRIA, Annex IV technical documentation) and vendor acknowledgments — legal counsel role.')
on conflict (key) do nothing;

-- ─── 2. Extend compliance_artifacts ─────────────────────────────────
alter table public.compliance_artifacts
  add column if not exists validity_status              public.validity_status not null default 'dev_stub',
  add column if not exists modeling_signoff_actor_id    uuid references public.people(id),
  add column if not exists modeling_signoff_at          timestamptz,
  add column if not exists modeling_signoff_rationale   text,
  add column if not exists legal_signoff_actor_id       uuid references public.people(id),
  add column if not exists legal_signoff_at             timestamptz,
  add column if not exists legal_signoff_rationale      text,
  add column if not exists annex_iii_high_risk_class    text,
  add column if not exists annex_iii_high_risk_rationale text;

alter table public.compliance_artifacts
  drop constraint if exists ca_kind_enum,
  drop constraint if exists ca_annex_iii_enum,
  drop constraint if exists ca_modeling_rationale_len,
  drop constraint if exists ca_legal_rationale_len,
  drop constraint if exists ca_validated_requires_dual_signoff;

alter table public.compliance_artifacts
  add constraint ca_kind_enum check (
    kind in (
      'annex_iv_technical_doc',
      'dpia',
      'fria',
      'instructions_for_use',
      'validity_dossier',
      'serious_incident_report',
      'vendor_disclosure',
      'placement_handoff_record',
      'audit_logs_export',
      'other')),
  add constraint ca_annex_iii_enum check (
    annex_iii_high_risk_class is null or annex_iii_high_risk_class in (
      'employment_recruitment','employment_evaluation','employment_termination',
      'access_to_services','law_enforcement','migration','biometrics',
      'critical_infrastructure','education','justice','democratic_process','not_high_risk')),
  add constraint ca_modeling_rationale_len check (
    modeling_signoff_rationale is null or length(modeling_signoff_rationale) >= 100),
  add constraint ca_legal_rationale_len check (
    legal_signoff_rationale is null or length(legal_signoff_rationale) >= 100),
  add constraint ca_validated_requires_dual_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and modeling_signoff_actor_id is not null
      and modeling_signoff_at is not null
      and modeling_signoff_rationale is not null
      and length(modeling_signoff_rationale) >= 100
      and legal_signoff_actor_id is not null
      and legal_signoff_at is not null
      and legal_signoff_rationale is not null
      and length(legal_signoff_rationale) >= 100
    ));

create index if not exists ca_status_idx on public.compliance_artifacts(validity_status);
create index if not exists ca_kind_idx   on public.compliance_artifacts(kind);

-- ─── 3. vendor_acknowledgments (Mobley v. Workday) ──────────────────
create table if not exists public.vendor_acknowledgments (
  id                          uuid primary key default gen_random_uuid(),
  org_id                      uuid not null references public.organizations(id),
  vendor_name                 text not null,
  vendor_role                 text not null,   -- e.g. 'assessment_provider', 'sourcing_platform'
  acknowledgment_text         text not null,
  workday_precedent_acknowledged boolean not null default false,
  data_processor_agreement_url text,
  effective_from              date not null default current_date,
  effective_to                date,
  validity_status             public.validity_status not null default 'dev_stub',
  _dev_stub                   boolean not null default true,
  signoff_actor_id            uuid references public.people(id),
  signoff_at                  timestamptz,
  signoff_rationale           text,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  created_by                  uuid references public.people(id),

  constraint va_role_enum check (
    vendor_role in ('assessment_provider','sourcing_platform','llm_provider',
                    'cv_screening','scheduler','interview_recorder','reference_checker','other')),
  constraint va_ack_text_len check (length(acknowledgment_text) >= 50),
  constraint va_effective_range check (
    effective_to is null or effective_to >= effective_from),
  constraint va_signoff_rationale_len check (
    signoff_rationale is null or length(signoff_rationale) >= 100),
  constraint va_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and workday_precedent_acknowledged = true
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    ))
);

comment on table public.vendor_acknowledgments is
  'Record of org acknowledgments of vendor-as-employment-agency obligations per Mobley v. Workday (N.D. Cal. 2024). When an org integrates a vendor that touches employment decisions, the vendor inherits employment-agency liability — this table is the org''s formal acknowledgment.';

create index if not exists va_org_idx     on public.vendor_acknowledgments(org_id);
create index if not exists va_status_idx  on public.vendor_acknowledgments(validity_status);
create index if not exists va_vendor_idx  on public.vendor_acknowledgments(vendor_name);

create unique index if not exists va_one_current_per_vendor
  on public.vendor_acknowledgments (org_id, vendor_name)
  where effective_to is null;

-- ─── 4. RPCs ────────────────────────────────────────────────────────
create or replace function public.rpc_compliance_artifact_signoff_modeling(
  p_artifact_id        uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.compliance_artifacts%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.compliance_artifacts where id = p_artifact_id for update;
  if not found then raise exception 'artifact % not found', p_artifact_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.compliance_artifacts
     set modeling_signoff_actor_id=v_caller, modeling_signoff_at=now(),
         modeling_signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_artifact_id;
  perform public.audit_log_event(
    v_row.org_id, 'compliance_artifact.signoff_modeling', 'compliance_artifact', p_artifact_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller, 'rationale_length', length(p_decision_rationale),
      'kind', v_row.kind), null);
  return jsonb_build_object('ok', true, 'artifact_id', p_artifact_id,
    'modeling_signoff_actor_id', v_caller);
end;
$$;

revoke all on function public.rpc_compliance_artifact_signoff_modeling(uuid, text) from public;
grant execute on function public.rpc_compliance_artifact_signoff_modeling(uuid, text) to authenticated, service_role;

create or replace function public.rpc_compliance_artifact_signoff_legal(
  p_artifact_id        uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.compliance_artifacts%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.compliance_artifacts where id = p_artifact_id for update;
  if not found then raise exception 'artifact % not found', p_artifact_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'legal.signoff') then
    raise exception 'denied: legal.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  if v_row.modeling_signoff_actor_id is null then
    raise exception 'modeling sign-off must complete before legal sign-off' using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  -- Both signoffs now present → promote to validated
  update public.compliance_artifacts
     set legal_signoff_actor_id=v_caller, legal_signoff_at=now(),
         legal_signoff_rationale=p_decision_rationale,
         validity_status='validated', _dev_stub=false,
         signed_off_by=v_caller, signed_off_at=now(),
         updated_at=now()
   where id = p_artifact_id;
  perform public.audit_log_event(
    v_row.org_id, 'compliance_artifact.signoff_legal', 'compliance_artifact', p_artifact_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller, 'rationale_length', length(p_decision_rationale),
      'kind', v_row.kind, 'promoted_to_validated', true), null);
  return jsonb_build_object('ok', true, 'artifact_id', p_artifact_id,
    'validity_status', 'validated', 'legal_signoff_actor_id', v_caller);
end;
$$;

revoke all on function public.rpc_compliance_artifact_signoff_legal(uuid, text) from public;
grant execute on function public.rpc_compliance_artifact_signoff_legal(uuid, text) to authenticated, service_role;

create or replace function public.rpc_vendor_acknowledgment_signoff(
  p_id                 uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.vendor_acknowledgments%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.vendor_acknowledgments where id = p_id for update;
  if not found then raise exception 'acknowledgment % not found', p_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'legal.signoff') then
    raise exception 'denied: legal.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  if v_row.workday_precedent_acknowledged is not true then
    raise exception 'workday_precedent_acknowledged must be true before sign-off' using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.vendor_acknowledgments
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_id;
  perform public.audit_log_event(
    v_row.org_id, 'vendor_acknowledgment.signoff', 'vendor_acknowledgment', p_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller, 'vendor_name', v_row.vendor_name,
      'rationale_length', length(p_decision_rationale)), null);
  return jsonb_build_object('ok', true, 'id', p_id,
    'validity_status', 'validated', 'signoff_actor_id', v_caller);
end;
$$;

revoke all on function public.rpc_vendor_acknowledgment_signoff(uuid, text) from public;
grant execute on function public.rpc_vendor_acknowledgment_signoff(uuid, text) to authenticated, service_role;

-- ─── 5. RLS for new table ───────────────────────────────────────────
alter table public.vendor_acknowledgments enable row level security;
alter table public.vendor_acknowledgments force  row level security;

drop policy if exists va_select_org on public.vendor_acknowledgments;
create policy va_select_org on public.vendor_acknowledgments
  for select using (
    public.has_permission(org_id, 'modeling.read')
    or public.has_permission(org_id, 'role.read'));

drop policy if exists va_write_legal on public.vendor_acknowledgments;
create policy va_write_legal on public.vendor_acknowledgments
  for insert with check (public.has_permission(org_id, 'modeling.write'));

drop policy if exists va_update_legal on public.vendor_acknowledgments;
create policy va_update_legal on public.vendor_acknowledgments
  for update using (public.has_permission(org_id, 'modeling.write'))
              with check (public.has_permission(org_id, 'modeling.write'));

grant select on public.vendor_acknowledgments to authenticated;
grant insert, update, delete on public.vendor_acknowledgments to authenticated;
