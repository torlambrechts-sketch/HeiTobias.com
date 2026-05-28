-- fit_scoring_tables — Phase 1 capability: multi-dimensional fit + placement
-- report + human-in-the-loop hiring decision capture.
--
--   fit_results        — multi-dim fit per (requisition, person). fit_json
--                        shape requires per_competency + trait_ranges +
--                        overall_summary with multi-axis keys. The schema
--                        cannot represent "single verdict number".
--   placement_reports  — generated client-ready output (HTML/PDF reference).
--   hiring_decisions   — the HUMAN decision + override + rationale.
--                        Required before placement_execute (Step 5 wires that in).

create type public.fit_band_status as enum ('in','below','above');
create type public.hiring_decision as enum ('advance','reject','hire','withdraw');

-- ---- fit_results --------------------------------------------------------

create table public.fit_results (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id)        on delete restrict,
  requisition_id  uuid not null references public.requisitions(id)         on delete cascade,
  person_id       uuid not null references public.people(id)               on delete restrict,
  role_id         uuid not null references public.roles_catalog(id)        on delete restrict,
  consent_id      uuid not null references public.consent_grants(id)       on delete restrict,
  fit_json        jsonb not null default '{}'::jsonb,
  validity_status public.validity_status not null default 'dev_stub',
  _dev_stub       boolean not null default false,
  computed_at     timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  unique (requisition_id, person_id),

  -- The shape rules out "single verdict number" by REQUIRING multi-axis keys
  -- in overall_summary and the per-dimension arrays.
  constraint chk_fit_json_shape check (
    extensions.jsonb_matches_schema(
      schema := '{
        "type":"object",
        "required":["per_competency","trait_ranges","overall_summary"],
        "properties":{
          "per_competency":{
            "type":"array",
            "items":{
              "type":"object",
              "required":["key","person_value","target_weight","fit_score"],
              "properties":{
                "key":           {"type":"string"},
                "person_value":  {"type":["number","null"]},
                "target_weight": {"type":"number","minimum":0,"maximum":1},
                "fit_score":     {"type":["number","null"]}
              },
              "additionalProperties":true
            }
          },
          "trait_ranges":{
            "type":"array",
            "items":{
              "type":"object",
              "required":["trait","person_value","band","status"],
              "properties":{
                "trait":        {"type":"string"},
                "person_value": {"type":["number","null"]},
                "band":{
                  "type":"object",
                  "required":["min","max"],
                  "properties":{
                    "min":{"type":"number"},
                    "max":{"type":"number"}
                  },
                  "additionalProperties":false
                },
                "status":{"enum":["in","below","above"]}
              },
              "additionalProperties":true
            }
          },
          "cognitive_demand":{"type":["object","null"]},
          "context_fit":     {"type":["object","null"]},
          "overall_summary":{
            "type":"object",
            "required":["competency_alignment","trait_alignment"],
            "properties":{
              "competency_alignment":{"type":"object"},
              "trait_alignment":     {"type":"object"}
            },
            "additionalProperties":true
          }
        },
        "additionalProperties":true
      }'::json,
      instance := fit_json
    )
  ),

  -- I/O seam: validated fit_results need a real fit (not all-null) and not flagged stub.
  constraint chk_fit_validated_real check (
    validity_status <> 'validated'
    or (jsonb_array_length(coalesce(fit_json->'per_competency','[]'::jsonb)) > 0
        and coalesce(_dev_stub, false) = false)
  )
);

create index fit_results_req_idx    on public.fit_results (requisition_id);
create index fit_results_person_idx on public.fit_results (person_id);
create index fit_results_role_idx   on public.fit_results (role_id);

create trigger trg_fit_results_updated_at
  before update on public.fit_results
  for each row execute function public.set_updated_at();
create trigger trg_audit_fit_results
  after insert or update or delete on public.fit_results
  for each row execute function public._audit_row();

alter table public.fit_results enable row level security;

create policy fit_results_select on public.fit_results
  for select to authenticated
  using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'fit.read')
      and public.in_scope(org_id, person_id)
      and public.consent_active(consent_id)
    )
  );
create policy fit_results_insert on public.fit_results
  for insert to authenticated
  with check (
    public.has_permission(org_id, 'fit.compute')
    and public.consent_active(consent_id)
  );
create policy fit_results_update on public.fit_results
  for update to authenticated
  using      (public.has_permission(org_id, 'fit.compute') and public.consent_active(consent_id))
  with check (public.has_permission(org_id, 'fit.compute') and public.consent_active(consent_id));

comment on table public.fit_results is
  'Multi-dimensional fit per (requisition, person). fit_json schema FORBIDS the single-verdict-number shape — overall_summary requires multi-axis keys.';

-- ---- placement_reports --------------------------------------------------

create table public.placement_reports (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete restrict,
  requisition_id  uuid not null references public.requisitions(id)  on delete cascade,
  person_id       uuid not null references public.people(id)        on delete restrict,
  fit_result_id   uuid not null references public.fit_results(id)   on delete restrict,
  report_html     text,
  report_pdf_url  text,
  generated_by    uuid references public.people(id) on delete set null,
  generated_at    timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index placement_reports_req_idx on public.placement_reports (requisition_id);
create index placement_reports_fit_idx on public.placement_reports (fit_result_id);

create trigger trg_placement_reports_updated_at
  before update on public.placement_reports
  for each row execute function public.set_updated_at();
create trigger trg_audit_placement_reports
  after insert or update or delete on public.placement_reports
  for each row execute function public._audit_row();

alter table public.placement_reports enable row level security;

create policy placement_reports_select on public.placement_reports
  for select to authenticated
  using (public.has_permission(org_id, 'fit.read'));
create policy placement_reports_insert on public.placement_reports
  for insert to authenticated
  with check (public.has_permission(org_id, 'fit.compute'));
create policy placement_reports_update on public.placement_reports
  for update to authenticated
  using      (public.has_permission(org_id, 'fit.compute'))
  with check (public.has_permission(org_id, 'fit.compute'));

comment on table public.placement_reports is
  'Generated client-ready placement report. Carries the rendered HTML or a URL to the PDF.';

-- ---- hiring_decisions (the human-in-the-loop record) -------------------

create table public.hiring_decisions (
  id                        uuid primary key default extensions.gen_random_uuid(),
  org_id                    uuid not null references public.organizations(id) on delete restrict,
  requisition_candidate_id  uuid not null references public.requisition_candidates(id) on delete cascade,
  fit_result_id             uuid references public.fit_results(id) on delete set null,
  decision                  public.hiring_decision not null,
  rationale                 text not null,
  overrode_recommendation   boolean not null default false,
  recommendation_summary    text,
  decided_by                uuid not null references public.people(id) on delete restrict,
  decided_at                timestamptz not null default now(),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  unique (requisition_candidate_id, decided_at)
);

create index hiring_decisions_req_cand_idx on public.hiring_decisions (requisition_candidate_id);
create index hiring_decisions_decided_by_idx on public.hiring_decisions (decided_by);

create trigger trg_hiring_decisions_updated_at
  before update on public.hiring_decisions
  for each row execute function public.set_updated_at();
create trigger trg_audit_hiring_decisions
  after insert or update or delete on public.hiring_decisions
  for each row execute function public._audit_row();

alter table public.hiring_decisions enable row level security;

create policy hiring_decisions_select on public.hiring_decisions
  for select to authenticated
  using (public.has_permission(org_id, 'fit.read') or public.has_permission(org_id, 'hiring.decide'));

create policy hiring_decisions_insert on public.hiring_decisions
  for insert to authenticated
  with check (
    public.has_permission(org_id, 'hiring.decide')
    and public.is_self(decided_by)
  );

-- UPDATE is allowed only by the original decider, only on the same day, only for typo fixes
-- to rationale. Locking the decision keeps the audit trail meaningful.
create policy hiring_decisions_update on public.hiring_decisions
  for update to authenticated
  using (
    public.is_self(decided_by)
    and decided_at >= now() - interval '24 hours'
  )
  with check (
    public.is_self(decided_by)
  );

comment on table public.hiring_decisions is
  'Human-in-the-loop record of every hiring decision. overrode_recommendation captures cases where the human went against the multi-dimensional fit signal. EU AI Act requirement.';
