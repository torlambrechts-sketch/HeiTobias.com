-- assessment_engine_tables — Phase 1 capability: assessment engine.
--
-- The PIPELINE is ours; the CONTENT (items, formulas, norms) is pluggable.
-- See CLAUDE.md *Validated science & DEV STUBs* and PHASE1-SPEC §4.
--
--   assessment_instruments  — the catalog. validity_status enum carries provenance.
--   assessment_items        — items within an instrument. _dev_stub flags fabricated values.
--   assessment_responses    — a candidate's response to one item. CONSENT-SCOPED:
--                             every row carries a consent_id (NOT NULL) that must
--                             be active for the row to be readable (consent_active()).
--   assessment_scores       — derived scores. Carries validity_status + _dev_stub
--                             + DB CHECK refusing 'validated' rows that carry
--                             stub values. This is the load-bearing I/O seam.
--   _dev_stub_score(...)    — labeled stub function that emits placeholder values
--                             with validity_status='dev_stub' and _dev_stub=true.
--                             Replace with licensed-instrument scoring when ready.

-- ---- assessment_instruments ---------------------------------------------

create table public.assessment_instruments (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid references public.organizations(id) on delete cascade, -- null = global instrument
  key             text not null,
  name            text not null,
  vendor          text,
  licensed_by     text,
  validity_status public.validity_status not null default 'dev_stub',
  version         text not null default '0.1.0',
  body_json       jsonb not null default '{}'::jsonb
                    check (jsonb_typeof(body_json) = 'object'),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (org_id, key, version)
);

create unique index assessment_instruments_global_unique
  on public.assessment_instruments (key, version) where org_id is null;
create index assessment_instruments_org_idx
  on public.assessment_instruments (org_id) where org_id is not null;

create trigger trg_assessment_instruments_updated_at
  before update on public.assessment_instruments
  for each row execute function public.set_updated_at();
create trigger trg_audit_assessment_instruments
  after insert or update or delete on public.assessment_instruments
  for each row execute function public._audit_row();

alter table public.assessment_instruments enable row level security;

create policy ai_select on public.assessment_instruments
  for select to authenticated
  using (org_id is null or public.has_permission(org_id, 'assessment.read'));
create policy ai_insert on public.assessment_instruments
  for insert to authenticated
  with check (org_id is not null and public.has_permission(org_id, 'assessment.write'));
create policy ai_update on public.assessment_instruments
  for update to authenticated
  using      (org_id is not null and public.has_permission(org_id, 'assessment.write'))
  with check (org_id is not null and public.has_permission(org_id, 'assessment.write'));

comment on table public.assessment_instruments is
  'Assessment instrument catalog. validity_status enum is the provenance gate (dev_stub | licensed | validated).';

-- ---- assessment_items ---------------------------------------------------

create table public.assessment_items (
  id              uuid primary key default extensions.gen_random_uuid(),
  instrument_id   uuid not null references public.assessment_instruments(id) on delete cascade,
  key             text not null,
  prompt          text not null,
  item_type       text not null check (item_type in ('likert','multiple_choice','open','timed','ranking')),
  item_json       jsonb not null default '{}'::jsonb
                    check (jsonb_typeof(item_json) = 'object'),
  _dev_stub       boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (instrument_id, key)
);

create index assessment_items_instrument_idx on public.assessment_items (instrument_id);

create trigger trg_assessment_items_updated_at
  before update on public.assessment_items
  for each row execute function public.set_updated_at();
create trigger trg_audit_assessment_items
  after insert or update or delete on public.assessment_items
  for each row execute function public._audit_row();

alter table public.assessment_items enable row level security;

-- Items are readable iff the parent instrument is readable (and we re-derive
-- that via a join). Phase 0 pattern.
create policy items_select on public.assessment_items
  for select to authenticated
  using (
    exists (
      select 1 from public.assessment_instruments inst
      where inst.id = assessment_items.instrument_id
        and (inst.org_id is null or public.has_permission(inst.org_id, 'assessment.read'))
    )
  );
create policy items_insert on public.assessment_items
  for insert to authenticated
  with check (
    exists (
      select 1 from public.assessment_instruments inst
      where inst.id = assessment_items.instrument_id
        and inst.org_id is not null
        and public.has_permission(inst.org_id, 'assessment.write')
    )
  );
create policy items_update on public.assessment_items
  for update to authenticated
  using (
    exists (
      select 1 from public.assessment_instruments inst
      where inst.id = assessment_items.instrument_id
        and inst.org_id is not null
        and public.has_permission(inst.org_id, 'assessment.write')
    )
  )
  with check (
    exists (
      select 1 from public.assessment_instruments inst
      where inst.id = assessment_items.instrument_id
        and inst.org_id is not null
        and public.has_permission(inst.org_id, 'assessment.write')
    )
  );

-- ---- assessment_responses (consent-scoped) ------------------------------

create table public.assessment_responses (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete restrict,
  assessment_id   uuid not null references public.assessments(id)   on delete cascade,
  item_id         uuid not null references public.assessment_items(id) on delete restrict,
  person_id       uuid not null references public.people(id)        on delete restrict,
  consent_id      uuid not null references public.consent_grants(id) on delete restrict,
  response_json   jsonb not null default '{}'::jsonb
                    check (jsonb_typeof(response_json) = 'object'),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (assessment_id, item_id)
);

create index assessment_responses_assessment_idx on public.assessment_responses (assessment_id);
create index assessment_responses_person_idx     on public.assessment_responses (person_id);
create index assessment_responses_consent_idx    on public.assessment_responses (consent_id);

create trigger trg_assessment_responses_updated_at
  before update on public.assessment_responses
  for each row execute function public.set_updated_at();
create trigger trg_audit_assessment_responses
  after insert or update or delete on public.assessment_responses
  for each row execute function public._audit_row();

alter table public.assessment_responses enable row level security;

-- SELECT: is_self OR (assessment.read AND in_scope AND consent_active).
-- This is the same Phase-0 personal-data pattern as profiles_select.
create policy responses_select on public.assessment_responses
  for select to authenticated
  using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'assessment.read')
      and public.in_scope(org_id, person_id)
      and public.consent_active(consent_id)
    )
  );

-- INSERT: an authenticated caller writing a response for themselves with an
-- active consent grant they own. The candidate-experience module (migration 21)
-- adds an additional permissive policy for the anon role with invite-token.
create policy responses_insert_self on public.assessment_responses
  for insert to authenticated
  with check (
    public.is_self(person_id)
    and public.consent_active(consent_id)
  );

-- UPDATE: only updaters with assessment.write in the org; consent must still be active.
create policy responses_update on public.assessment_responses
  for update to authenticated
  using (
    public.has_permission(org_id, 'assessment.write')
    and public.consent_active(consent_id)
  )
  with check (
    public.has_permission(org_id, 'assessment.write')
    and public.consent_active(consent_id)
  );

comment on table public.assessment_responses is
  'A candidate response to one item. Consent-scoped: every row carries an active consent_grants reference. RLS uses Phase 0 consent_active() helper.';

-- ---- assessment_scores (the I/O seam) ----------------------------------

create table public.assessment_scores (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id) on delete restrict,
  assessment_id       uuid not null references public.assessments(id)   on delete cascade,
  person_id           uuid not null references public.people(id)        on delete restrict,
  consent_id          uuid not null references public.consent_grants(id) on delete restrict,
  scale_key           text not null,
  raw_score           numeric,
  scaled_score        numeric,
  norm_band           text,
  validity_status     public.validity_status not null default 'dev_stub',
  _dev_stub           boolean not null default false,
  validity_flags_json jsonb not null default '{}'::jsonb
                        check (jsonb_typeof(validity_flags_json) = 'object'),
  computed_at         timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (assessment_id, scale_key),

  -- THE I/O SEAM ENFORCEMENT (CLAUDE.md / Validated science & DEV STUBs).
  -- A 'validated' score MUST have a real raw_score AND must NOT carry the
  -- per-value stub flag. A dev_stub may have null values.
  constraint chk_scores_validated_real check (
    validity_status <> 'validated'
    or (raw_score is not null and coalesce(_dev_stub, false) = false)
  )
);

create index assessment_scores_assessment_idx on public.assessment_scores (assessment_id);
create index assessment_scores_person_idx     on public.assessment_scores (person_id);
create index assessment_scores_consent_idx    on public.assessment_scores (consent_id);

create trigger trg_assessment_scores_updated_at
  before update on public.assessment_scores
  for each row execute function public.set_updated_at();
create trigger trg_audit_assessment_scores
  after insert or update or delete on public.assessment_scores
  for each row execute function public._audit_row();

alter table public.assessment_scores enable row level security;

-- SELECT: same personal-data pattern.
create policy scores_select on public.assessment_scores
  for select to authenticated
  using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'assessment.read')
      and public.in_scope(org_id, person_id)
      and public.consent_active(consent_id)
    )
  );

-- INSERT/UPDATE: assessment.write in org.
create policy scores_insert on public.assessment_scores
  for insert to authenticated
  with check (
    public.has_permission(org_id, 'assessment.write')
    and public.consent_active(consent_id)
  );
create policy scores_update on public.assessment_scores
  for update to authenticated
  using      (public.has_permission(org_id, 'assessment.write'))
  with check (public.has_permission(org_id, 'assessment.write'));

comment on table public.assessment_scores is
  'Derived scores. validity_status (provenance) + _dev_stub (per-value fabrication) + DB CHECK make the I/O seam load-bearing — a stub cannot be promoted to validated without real values.';

-- ---- _dev_stub_score function ------------------------------------------
-- Labeled stub: emits placeholder scores so the pipeline runs end-to-end on
-- fake data. Replace with licensed-instrument scoring in the assessment_engine
-- module's scoring config when ready.

create or replace function public._dev_stub_score(
  p_assessment_id uuid,
  p_person_id     uuid,
  p_consent_id    uuid,
  p_scale_key     text
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_org uuid;
  v_id  uuid;
begin
  select org_id into v_org from public.assessments where id = p_assessment_id;
  if v_org is null then
    raise exception '_dev_stub_score: assessment not found (id=%)', p_assessment_id;
  end if;

  -- DEV STUB — replace with licensed-instrument + I/O-validated scoring.
  -- Per CLAUDE.md *Validated science & DEV STUBs*: validity_status='dev_stub'
  -- and _dev_stub=true. raw_score / scaled_score stay null so the DB CHECK
  -- continues to refuse any future promotion to 'validated' without real values.
  insert into public.assessment_scores (
    org_id, assessment_id, person_id, consent_id, scale_key,
    raw_score, scaled_score, norm_band,
    validity_status, _dev_stub, validity_flags_json
  ) values (
    v_org, p_assessment_id, p_person_id, p_consent_id, p_scale_key,
    null, null, null,
    'dev_stub', true,
    jsonb_build_object(
      'dev_stub', true,
      'note', 'DEV STUB — replace with licensed instrument + I/O-validated scoring'
    )
  )
  returning id into v_id;

  return v_id;
end;
$$;
comment on function public._dev_stub_score(uuid,uuid,uuid,text) is
  'DEV STUB. Inserts a placeholder assessment_scores row with null score values and validity_status=dev_stub. Replace at module-config level with licensed instrument scoring.';

revoke execute on function public._dev_stub_score(uuid,uuid,uuid,text) from public;
grant  execute on function public._dev_stub_score(uuid,uuid,uuid,text) to authenticated, service_role;
