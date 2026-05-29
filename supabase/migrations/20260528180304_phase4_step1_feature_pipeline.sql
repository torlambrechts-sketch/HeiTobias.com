-- phase4_step1_feature_pipeline — consent-gated, lineage-tracked feature
-- pipeline for the Phase 4 modeling layer.
--
-- Two principles structurally enforced (SCIENCE-SPEC §§9, 10 + Phase 4
-- prompt overriding-principle):
--
--   * SYNTHETIC ONLY until experts engage. Every row in feature_views /
--     model_datasets carries _dev_stub=true and source='synthetic'.
--     The chk_validated_real CHECK refuses validity_status='validated'
--     while _dev_stub=true.
--
--   * MODELING DATA IS CONSENT-GATED. Only subjects with an active
--     research_anonymized consent grant for the org enter the feature
--     store. Revocation drops them on the next refresh (and the test
--     proves it).
--
-- Plus features are TRAIT-RANGE FIT SCORES + complexity-conditional
-- cognitive — never raw traits (SCIENCE-SPEC §1).

-- ---- consent_purpose already has research_anonymized from Phase 0;
-- ---- we just wire candidate-side granting + RLS gates around it.

-- research_consent_grant — candidate (via their consent_token) grants
-- research_anonymized to a named employer org. Same shape as Phase 2's
-- portability_grant — idempotent, audited.
create or replace function public.research_consent_grant(
  p_token            text,
  p_employer_org_id  uuid,
  p_scope_json       jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_person_id uuid;
  v_org       public.organizations%rowtype;
  v_existing  uuid;
  v_id        uuid;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'research_consent_grant: token required';
  end if;
  select (r).person_id into v_person_id from public._consent_token_resolve(p_token) r;
  if v_person_id is null then
    raise exception 'research_consent_grant: invalid or expired token';
  end if;
  select * into v_org from public.organizations where id = p_employer_org_id;
  if not found then raise exception 'research_consent_grant: org not found'; end if;

  select id into v_existing from public.consent_grants
    where person_id = v_person_id
      and granted_to_org_id = p_employer_org_id
      and purpose = 'research_anonymized'
      and status = 'active' and revoked_at is null
      and (expires_at is null or expires_at > now())
    limit 1;
  if v_existing is not null then return v_existing; end if;

  insert into public.consent_grants (person_id, granted_to_org_id, purpose, legal_basis, scope_json)
    values (v_person_id, p_employer_org_id, 'research_anonymized', 'consent', coalesce(p_scope_json, '{}'::jsonb))
    returning id into v_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_employer_org_id, v_person_id, 'consent.granted', 'consent_grants', v_id,
      jsonb_build_object('purpose','research_anonymized','source','candidate_dashboard'));
  return v_id;
end;
$$;
revoke execute on function public.research_consent_grant(text, uuid, jsonb) from public;
grant  execute on function public.research_consent_grant(text, uuid, jsonb) to anon, authenticated, service_role;
comment on function public.research_consent_grant(text, uuid, jsonb) is
  'Anon, token-gated. Data subject grants research_anonymized to a named employer org. Required before their data can enter a feature_view / model_dataset.';

-- ============ feature_views ============
-- A registered feature definition: a name, a computation reference, and
-- versioned lineage of the input tables/columns. Each computed row in
-- the feature store carries a feature_view_id + a subject_consent_id so
-- we can prove (a) it was derived under valid consent and (b) it can be
-- reproduced from the same source rows.
create table public.feature_views (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  key             text not null,
  version         text not null default '0.0.1-dev',
  description     text,
  feature_kind    text not null check (feature_kind in (
                    'trait_range_fit',           -- SCIENCE-SPEC §1: fit-vs-band, not raw trait
                    'complexity_conditional_cognitive',
                    'pulse_trend',
                    'role_context_factor'
                  )),
  source_tables   text[] not null,               -- lineage: which public tables fed this
  feature_spec    jsonb not null default '{}'::jsonb,
  validity_status public.validity_status not null default 'dev_stub',
  _dev_stub       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (org_id, key, version),
  constraint chk_feature_views_validated_real
    check (validity_status <> 'validated'
           or (feature_spec <> '{}'::jsonb and coalesce(_dev_stub, false) = false))
);
create index feature_views_kind_idx on public.feature_views (feature_kind);
create trigger trg_touch_feature_views before update on public.feature_views
  for each row execute function public.set_updated_at();
create trigger trg_audit_feature_views after insert or update or delete on public.feature_views
  for each row execute function public._audit_row();
alter table public.feature_views enable row level security;
alter table public.feature_views force  row level security;
create policy feature_views_select on public.feature_views for select using (
  public.has_permission(org_id, 'org.read')
);
create policy feature_views_write on public.feature_views for all
  using (public.has_permission(org_id, 'org.manage_all'))
  with check (public.has_permission(org_id, 'org.manage_all'));

-- ============ feature_rows ============
-- The computed feature values. (person × feature_view × valid_at) →
-- value_json. EVERY row carries consent_id so RLS + revocation work.
create table public.feature_rows (
  id               uuid primary key default extensions.gen_random_uuid(),
  org_id           uuid not null references public.organizations(id),
  feature_view_id  uuid not null references public.feature_views(id) on delete cascade,
  person_id        uuid not null references public.people(id),
  consent_id       uuid not null references public.consent_grants(id),
  valid_at         timestamptz not null,
  value_json       jsonb not null,
  source_refs      jsonb not null default '{}'::jsonb,  -- lineage of which specific rows fed this
  _dev_stub        boolean not null default true,
  computed_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index feature_rows_view_idx    on public.feature_rows (feature_view_id, valid_at desc);
create index feature_rows_person_idx  on public.feature_rows (person_id, feature_view_id);
create trigger trg_touch_feature_rows before update on public.feature_rows
  for each row execute function public.set_updated_at();
create trigger trg_audit_feature_rows after insert or update or delete on public.feature_rows
  for each row execute function public._audit_row();
alter table public.feature_rows enable row level security;
alter table public.feature_rows force  row level security;

-- Self-leg (data subject) + has_permission + consent_active(consent_id, 'research_anonymized').
-- Note: research_anonymized is the gating purpose for the modeling pipeline.
create policy feature_rows_select on public.feature_rows for select using (
  public.is_self(person_id)
  or (
    public.has_permission(org_id, 'modeling.read')
    and public.consent_active(consent_id, 'research_anonymized')
  )
);
create policy feature_rows_insert on public.feature_rows for insert with check (
  public.has_permission(org_id, 'modeling.write')
  and public.consent_active(consent_id, 'research_anonymized')
);

-- ============ model_datasets ============
-- A FROZEN view of feature_rows at a particular instant — what the
-- training run sees. dataset_subjects records which (person, consent_id)
-- pairs were captured; if a subject later revokes research_anonymized,
-- the audit trail still shows they WERE in this dataset (compliance:
-- "what data did the model see?") but they MUST be excluded from any
-- NEW dataset frozen after the revoke.
create table public.model_datasets (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  key             text not null,
  version         text not null default '0.0.1-dev',
  feature_view_id uuid not null references public.feature_views(id),
  frozen_at       timestamptz not null default now(),
  subject_count   int not null default 0,
  source          text not null default 'synthetic' check (source in ('synthetic','real')),
  notes           text,
  validity_status public.validity_status not null default 'dev_stub',
  _dev_stub       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (org_id, key, version),
  constraint chk_model_datasets_synthetic_only_until_validated
    check (validity_status <> 'validated' or source = 'real'),
  constraint chk_model_datasets_validated_real
    check (validity_status <> 'validated' or coalesce(_dev_stub, false) = false)
);
create trigger trg_touch_model_datasets before update on public.model_datasets
  for each row execute function public.set_updated_at();
create trigger trg_audit_model_datasets after insert or update or delete on public.model_datasets
  for each row execute function public._audit_row();
alter table public.model_datasets enable row level security;
alter table public.model_datasets force  row level security;
create policy model_datasets_select on public.model_datasets for select using (
  public.has_permission(org_id, 'modeling.read')
);
create policy model_datasets_write on public.model_datasets for all
  using (public.has_permission(org_id, 'modeling.write'))
  with check (public.has_permission(org_id, 'modeling.write'));

create table public.model_dataset_subjects (
  id          uuid primary key default extensions.gen_random_uuid(),
  dataset_id  uuid not null references public.model_datasets(id) on delete cascade,
  person_id   uuid not null references public.people(id),
  consent_id  uuid not null references public.consent_grants(id),  -- the active research_anonymized at freeze time
  feature_row_ids uuid[] not null default '{}',
  unique (dataset_id, person_id)
);
create index model_dataset_subjects_dataset_idx on public.model_dataset_subjects (dataset_id);
alter table public.model_dataset_subjects enable row level security;
alter table public.model_dataset_subjects force  row level security;
create policy model_dataset_subjects_select on public.model_dataset_subjects for select using (
  public.is_self(person_id)
  or exists (
    select 1 from public.model_datasets d
    where d.id = model_dataset_subjects.dataset_id
      and public.has_permission(d.org_id, 'modeling.read')
  )
);

-- ============ permissions ============
insert into public.rbac_permissions (key, description) values
  ('modeling.read',  'Read feature_views / feature_rows / model_datasets (Phase 4)'),
  ('modeling.write', 'Register feature_views and freeze model_datasets (Phase 4)')
on conflict (key) do nothing;
-- Grant to org_admin only by default. people_ops_admin is intentionally
-- excluded — Phase 4 work is gated to a smaller "research" surface.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id from public.rbac_roles r cross join public.rbac_permissions p
  where r.org_id is null and r.key = 'org_admin'
    and p.key in ('modeling.read','modeling.write')
on conflict do nothing;
