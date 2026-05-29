-- phase4_step6_compliance_artifacts — EU AI Act Annex IV + DPIA + FRIA
-- + validity-dossier assembly tables. SCIENCE-SPEC §12 + Phase 4 §6.
--
-- Three load-bearing rules:
--
--   * ARTIFACTS ARE ASSEMBLED FROM REAL LOGGED DATA. Every artifact
--     row has at least one compliance_artifact_sources row pointing at
--     the underlying record (audit_log, model_cards, fairness_metrics,
--     consent_grants, etc.). The compliance_artifact_assemble RPC is
--     the source of these links; no document can be added without
--     them.
--
--   * THE SYSTEM NEVER SELF-ATTESTS COMPLIANCE. payload_json.
--     self_attestation is NULL on assembly; sign_off_status defaults
--     to 'draft'. Only compliance_artifact_signoff (modeling.signoff
--     gated) can move to 'signed' — and the CHECK
--     chk_compliance_signed_requires_signoff requires both a person +
--     timestamp + >=20-char attestation in that state.
--
--   * POLICY IS DATA. compliance_rules carries the AI Act / GDPR
--     timeline as configurable rows so the Aug-2026 → Dec-2027
--     Omnibus deferral is a config flip, not a code change. The seed
--     marks the Omnibus row "SCHEDULE MARGIN ONLY".

create table public.compliance_artifacts (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  kind            text not null check (kind in (
                    'annex_iv_technical_doc', 'dpia', 'fria',
                    'validity_dossier', 'fairness_audit_report', 'public_fairness_report'
                  )),
  key             text not null,
  version         text not null default '0.0.1-dev',
  scope_json      jsonb not null default '{}'::jsonb,
  payload_json    jsonb not null default '{}'::jsonb,
  generated_at    timestamptz not null default now(),
  sign_off_status text not null default 'draft'
                  check (sign_off_status in ('draft','awaiting_signoff','signed','rejected')),
  signed_off_by   uuid references public.people(id),
  signed_off_at   timestamptz,
  attestation_text text,
  _dev_stub       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (org_id, kind, key, version),
  constraint chk_compliance_signed_requires_signoff
    check (sign_off_status <> 'signed' or (
      signed_off_by is not null and signed_off_at is not null
      and attestation_text is not null and length(attestation_text) >= 20
    ))
);
create index compliance_artifacts_org_idx on public.compliance_artifacts (org_id, kind);
create trigger trg_touch_compliance_artifacts before update on public.compliance_artifacts
  for each row execute function public.set_updated_at();
create trigger trg_audit_compliance_artifacts after insert or update or delete on public.compliance_artifacts
  for each row execute function public._audit_row();
alter table public.compliance_artifacts enable row level security;
alter table public.compliance_artifacts force  row level security;
create policy compliance_artifacts_select on public.compliance_artifacts for select using (
  public.has_permission(org_id, 'org.read')
);
create policy compliance_artifacts_write on public.compliance_artifacts for all
  using (public.has_permission(org_id, 'modeling.write'))
  with check (public.has_permission(org_id, 'modeling.write'));

create table public.compliance_artifact_sources (
  id           uuid primary key default extensions.gen_random_uuid(),
  artifact_id  uuid not null references public.compliance_artifacts(id) on delete cascade,
  source_table text not null,
  source_id    uuid not null,
  source_kind  text,
  excerpt_json jsonb not null default '{}'::jsonb,
  _dev_stub    boolean not null default true,
  created_at   timestamptz not null default now()
);
create index compliance_artifact_sources_artifact_idx on public.compliance_artifact_sources (artifact_id);
alter table public.compliance_artifact_sources enable row level security;
alter table public.compliance_artifact_sources force  row level security;
create policy compliance_artifact_sources_select on public.compliance_artifact_sources for select using (
  exists (select 1 from public.compliance_artifacts a
          where a.id = compliance_artifact_sources.artifact_id
            and public.has_permission(a.org_id, 'org.read'))
);
create policy compliance_artifact_sources_write on public.compliance_artifact_sources for all using (
  exists (select 1 from public.compliance_artifacts a
          where a.id = compliance_artifact_sources.artifact_id
            and public.has_permission(a.org_id, 'modeling.write'))
) with check (
  exists (select 1 from public.compliance_artifacts a
          where a.id = compliance_artifact_sources.artifact_id
            and public.has_permission(a.org_id, 'modeling.write'))
);

create table public.compliance_rules (
  id              uuid primary key default extensions.gen_random_uuid(),
  key             text not null unique,
  regulation      text not null check (regulation in ('eu_ai_act','gdpr','workplace_act','uniform_guidelines')),
  article_ref     text,
  effective_from  date,
  effective_until date,
  rule_json       jsonb not null default '{}'::jsonb,
  active          boolean not null default true,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create trigger trg_touch_compliance_rules before update on public.compliance_rules
  for each row execute function public.set_updated_at();
alter table public.compliance_rules enable row level security;
alter table public.compliance_rules force  row level security;
create policy compliance_rules_select on public.compliance_rules for select using (true);

insert into public.compliance_rules (key, regulation, article_ref, effective_from, rule_json, notes) values
  ('ai_act_high_risk_doc_required_2026_08','eu_ai_act','Annex IV','2026-08-02',
    jsonb_build_object('artifact_kinds', jsonb_build_array('annex_iv_technical_doc','validity_dossier'),
                       'description','Annex IV technical documentation required for high-risk AI systems'),
    'Original AI Act high-risk deadline — Aug 2026'),
  ('ai_act_fria_required_2026_08','eu_ai_act','Art. 27','2026-08-02',
    jsonb_build_object('artifact_kinds', jsonb_build_array('fria'),
                       'description','Fundamental Rights Impact Assessment for deployers of high-risk AI'),
    'AI Act Art. 27 — FRIA'),
  ('gdpr_art_35_dpia_when_high_risk','gdpr','Art. 35','2018-05-25',
    jsonb_build_object('artifact_kinds', jsonb_build_array('dpia'),
                       'description','DPIA required when processing is likely to result in a high risk to rights and freedoms'),
    'GDPR Art. 35 DPIA'),
  ('ai_act_omnibus_standalone_deferral_2027_12','eu_ai_act','Omnibus','2027-12-02',
    jsonb_build_object('artifact_kinds', jsonb_build_array('annex_iv_technical_doc'),
                       'description','Dec 2027 Omnibus deferral for standalone high-risk systems — SCHEDULE MARGIN ONLY'),
    'Treat as margin, not permission slip — keep building to Aug-2026 spec')
on conflict (key) do nothing;
