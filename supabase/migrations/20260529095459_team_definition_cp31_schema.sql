-- Team-Based Role Definition — CP3.1 schema.
-- Six new tables, prefixed `team_definition_*` to avoid the Phase 1
-- `role_definition_evaluations` collision (which is the simpler
-- requisition-keyed flow from test 08 [3]).
--
-- LOAD-BEARING DISCIPLINE — three locks on Stage 2 sealing:
--   * server-side: own-row-only SELECT during stage='rating' via RLS
--   * client-side: UI never queries others' evaluations pre-seal
--   * audit-side: owner-side read RPC logs every attempt as
--     attempted_action='read_during_seal' if called pre-seal
--
-- Peer-personality block: structural CHECK on
-- team_definition_evaluations.rating_json refusing shapes that name a
-- target person + personality dimension (SCIENCE-SPEC §7).

create type public.team_definition_stage as enum
  ('setup','rating','divergence','reconciliation','signed_off','abandoned');
create type public.team_definition_purpose as enum
  ('initial_definition','evolution_revision','periodic_review');
create type public.team_definition_evaluator_role as enum
  ('manager','team_member','peer_team_lead','recruiter','sme_external');
create type public.team_definition_consensus_category as enum
  ('high','moderate','low');
create type public.team_definition_spread_metric as enum
  ('sd','range','percent_disagree','kendalls_w');

-- ============ team_definition_runs ============
create table public.team_definition_runs (
  id                        uuid primary key default extensions.gen_random_uuid(),
  org_id                    uuid not null references public.organizations(id),
  role_family               text not null,
  role_template_id          uuid references public.roles_catalog(id),
  purpose                   public.team_definition_purpose not null default 'initial_definition',
  owner_user_id             uuid not null references public.people(id),
  deadline_at               timestamptz not null,
  stage                     public.team_definition_stage not null default 'setup',
  starts_at                 timestamptz not null default now(),
  completed_at              timestamptz,
  target_role_version_id    uuid references public.roles_catalog(id),
  thresholds_json           jsonb not null default '{}'::jsonb,
  consensus_summary_json    jsonb not null default '{}'::jsonb,
  draft_definition_json     jsonb not null default '{}'::jsonb,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);
create index team_def_runs_org_idx   on public.team_definition_runs (org_id);
create index team_def_runs_stage_idx on public.team_definition_runs (org_id, stage);
create trigger trg_touch_team_def_runs before update on public.team_definition_runs for each row execute function public.set_updated_at();
create trigger trg_audit_team_def_runs after insert or update or delete on public.team_definition_runs for each row execute function public._audit_row();
alter table public.team_definition_runs enable row level security;
alter table public.team_definition_runs force  row level security;

-- Runs are visible to anyone with role.read in the run's org (admins,
-- recruiters, hiring managers). Setup writes require role.create.
create policy team_def_runs_select on public.team_definition_runs for select to authenticated using (
  public.has_permission(org_id, 'role.read')
);
create policy team_def_runs_write on public.team_definition_runs for all to authenticated
  using (public.has_permission(org_id, 'role.create'))
  with check (public.has_permission(org_id, 'role.create'));

-- ============ team_definition_evaluators ============
create table public.team_definition_evaluators (
  id                     uuid primary key default extensions.gen_random_uuid(),
  run_id                 uuid not null references public.team_definition_runs(id) on delete cascade,
  user_id                uuid not null references public.people(id),
  role                   public.team_definition_evaluator_role not null,
  invited_at             timestamptz not null default now(),
  accepted_at            timestamptz,
  submitted_at           timestamptz,
  reminded_at            timestamptz[] not null default '{}',
  weight_in_aggregation  numeric not null default 1.0,
  allow_attribution_on_reveal boolean not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (run_id, user_id)
);
create index team_def_evaluators_run_idx  on public.team_definition_evaluators (run_id);
create index team_def_evaluators_user_idx on public.team_definition_evaluators (user_id);
create trigger trg_touch_team_def_evaluators before update on public.team_definition_evaluators for each row execute function public.set_updated_at();
create trigger trg_audit_team_def_evaluators after insert or update or delete on public.team_definition_evaluators for each row execute function public._audit_row();
alter table public.team_definition_evaluators enable row level security;
alter table public.team_definition_evaluators force  row level security;

-- Evaluators row is visible to: the evaluator themselves; the run owner;
-- anyone with role.create in the run's org.
create policy team_def_evaluators_select on public.team_definition_evaluators for select to authenticated using (
  public.is_self(user_id)
  or exists (select 1 from public.team_definition_runs r where r.id = run_id and public.has_permission(r.org_id, 'role.read'))
);
create policy team_def_evaluators_write on public.team_definition_evaluators for all to authenticated
  using (exists (select 1 from public.team_definition_runs r where r.id = run_id and public.has_permission(r.org_id, 'role.create')))
  with check (exists (select 1 from public.team_definition_runs r where r.id = run_id and public.has_permission(r.org_id, 'role.create')));

-- ============ team_definition_evaluations ============
-- The independent rating. One row per evaluator per run.
--
-- Peer-personality block: CHECK refuses rating_json shapes that name a
-- target person + personality dimension. The legitimate `rating_json`
-- carries ROLE structural ratings only (per-task criticality,
-- competency weights, trait targets for the ROLE context, etc).
create table public.team_definition_evaluations (
  id                              uuid primary key default extensions.gen_random_uuid(),
  run_id                          uuid not null references public.team_definition_runs(id) on delete cascade,
  evaluator_id                    uuid not null references public.team_definition_evaluators(id) on delete cascade,
  submitted_at                    timestamptz,
  rating_json                     jsonb not null default '{}'::jsonb,
  rationale_notes_json            jsonb not null default '{}'::jsonb,
  allow_attribution_on_reveal     boolean not null default true,
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now(),
  unique (run_id, evaluator_id),
  constraint chk_team_def_evaluations_no_peer_personality check (
    not (
      rating_json ? 'target_person_id'
      or rating_json ? 'rater_person_id'
      or rating_json ? 'rates_person'
      or rationale_notes_json ? 'target_person_id'
      or rationale_notes_json ? 'rater_person_id'
      or rationale_notes_json ? 'rates_person'
    )
  )
);
create index team_def_evaluations_run_idx       on public.team_definition_evaluations (run_id);
create index team_def_evaluations_evaluator_idx on public.team_definition_evaluations (evaluator_id);
create trigger trg_touch_team_def_evaluations before update on public.team_definition_evaluations for each row execute function public.set_updated_at();
create trigger trg_audit_team_def_evaluations after insert or update or delete on public.team_definition_evaluations for each row execute function public._audit_row();
alter table public.team_definition_evaluations enable row level security;
alter table public.team_definition_evaluations force  row level security;

-- ============ THE LOAD-BEARING RLS — Stage 2 sealing ============
-- Pre-seal (stage IN ('setup','rating')): an evaluator sees ONLY their
-- own row. Run owner and reconciler see NOTHING via direct SELECT —
-- their legitimate read is via the SECDEF function that logs attempts.
-- Post-seal (stage IN ('divergence','reconciliation','signed_off',
-- 'abandoned')): owner + anyone with role.read can see all rows.
create policy team_def_evaluations_select on public.team_definition_evaluations for select to authenticated using (
  exists (
    select 1 from public.team_definition_evaluators ev
    join public.team_definition_runs r on r.id = ev.run_id
    where ev.id = team_definition_evaluations.evaluator_id
      and (
        -- Own row at any stage
        public.is_self(ev.user_id)
        OR (
          -- Post-seal: org members with role.read can see all rows.
          r.stage in ('divergence','reconciliation','signed_off','abandoned')
          AND public.has_permission(r.org_id, 'role.read')
        )
      )
  )
);

-- Submissions are immutable post-submit. Pre-submit: only the
-- evaluator themselves can UPDATE their own row, only while
-- submitted_at IS NULL.
create policy team_def_evaluations_update on public.team_definition_evaluations for update to authenticated
  using (
    submitted_at is null
    and exists (
      select 1 from public.team_definition_evaluators ev
      where ev.id = team_definition_evaluations.evaluator_id and public.is_self(ev.user_id)
    )
  )
  with check (
    exists (
      select 1 from public.team_definition_evaluators ev
      where ev.id = team_definition_evaluations.evaluator_id and public.is_self(ev.user_id)
    )
  );

-- INSERT: an evaluator (or rpc_submit_evaluation as SECDEF) creates
-- their own row only.
create policy team_def_evaluations_insert on public.team_definition_evaluations for insert to authenticated
  with check (
    exists (
      select 1 from public.team_definition_evaluators ev
      where ev.id = team_definition_evaluations.evaluator_id and public.is_self(ev.user_id)
    )
  );

-- ============ team_definition_divergence_runs ============
create table public.team_definition_divergence_runs (
  id                          uuid primary key default extensions.gen_random_uuid(),
  run_id                      uuid not null references public.team_definition_runs(id) on delete cascade,
  computed_at                 timestamptz not null default now(),
  criterion_key               text not null,
  spread_metric_type          public.team_definition_spread_metric not null,
  spread_value                numeric not null,
  consensus_category          public.team_definition_consensus_category not null,
  flagged_for_reconciliation  boolean not null default false,
  ranges_json                 jsonb not null default '{}'::jsonb,
  created_at                  timestamptz not null default now()
);
create index team_def_divergence_run_idx on public.team_definition_divergence_runs (run_id);
create trigger trg_audit_team_def_divergence after insert or update or delete on public.team_definition_divergence_runs for each row execute function public._audit_row();
alter table public.team_definition_divergence_runs enable row level security;
alter table public.team_definition_divergence_runs force  row level security;
create policy team_def_divergence_select on public.team_definition_divergence_runs for select to authenticated using (
  exists (select 1 from public.team_definition_runs r where r.id = run_id and public.has_permission(r.org_id, 'role.read'))
);
create policy team_def_divergence_write on public.team_definition_divergence_runs for all to authenticated
  using (exists (select 1 from public.team_definition_runs r where r.id = run_id and public.has_permission(r.org_id, 'role.create')))
  with check (exists (select 1 from public.team_definition_runs r where r.id = run_id and public.has_permission(r.org_id, 'role.create')));

-- ============ team_definition_reconciliations ============
create table public.team_definition_reconciliations (
  id                       uuid primary key default extensions.gen_random_uuid(),
  run_id                   uuid not null references public.team_definition_runs(id) on delete cascade,
  criterion_key            text not null,
  reconciler_user_id       uuid not null references public.people(id),
  discussion_notes_text    text,
  final_value_json         jsonb not null default '{}'::jsonb,
  attribution_json         jsonb not null default '{}'::jsonb,
  decided_at               timestamptz not null default now(),
  decision_artefact_link   jsonb not null default '{}'::jsonb,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index team_def_recon_run_idx on public.team_definition_reconciliations (run_id);
create trigger trg_touch_team_def_recon before update on public.team_definition_reconciliations for each row execute function public.set_updated_at();
create trigger trg_audit_team_def_recon after insert or update or delete on public.team_definition_reconciliations for each row execute function public._audit_row();
alter table public.team_definition_reconciliations enable row level security;
alter table public.team_definition_reconciliations force  row level security;
create policy team_def_recon_select on public.team_definition_reconciliations for select to authenticated using (
  exists (select 1 from public.team_definition_runs r where r.id = run_id and public.has_permission(r.org_id, 'role.read'))
);
create policy team_def_recon_write on public.team_definition_reconciliations for all to authenticated
  using (exists (select 1 from public.team_definition_runs r where r.id = run_id and public.has_permission(r.org_id, 'role.create')))
  with check (exists (select 1 from public.team_definition_runs r where r.id = run_id and public.has_permission(r.org_id, 'role.create')));

-- ============ team_definition_thresholds ============
-- The labelled stub seam (per the OVERRIDING PRINCIPLE E).
create table public.team_definition_thresholds (
  id                     uuid primary key default extensions.gen_random_uuid(),
  org_id                 uuid references public.organizations(id),
  threshold_key          text not null,
  value                  numeric not null,
  validity_status        public.validity_status not null default 'dev_stub',
  _dev_stub              boolean not null default true,
  notes_text             text,
  last_signed_off_by     uuid references public.people(id),
  last_signed_off_at     timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (org_id, threshold_key),
  constraint chk_team_def_thresholds_validated_real
    check (validity_status <> 'validated' or coalesce(_dev_stub,false) = false)
);
create trigger trg_touch_team_def_thresholds before update on public.team_definition_thresholds for each row execute function public.set_updated_at();
create trigger trg_audit_team_def_thresholds after insert or update or delete on public.team_definition_thresholds for each row execute function public._audit_row();
alter table public.team_definition_thresholds enable row level security;
alter table public.team_definition_thresholds force  row level security;
create policy team_def_thresholds_select on public.team_definition_thresholds for select to authenticated using (
  org_id is null or public.has_permission(org_id, 'role.read')
);
create policy team_def_thresholds_write on public.team_definition_thresholds for all to authenticated
  using (org_id is null or public.has_permission(org_id, 'role.signoff'))
  with check (org_id is null or public.has_permission(org_id, 'role.signoff'));

-- Seed the global-default thresholds as DEV STUBs.
insert into public.team_definition_thresholds (org_id, threshold_key, value, notes_text) values
  (null, 'low_consensus_sd_cutoff',     1.4, 'DEV STUB — what SD on a 0–5 ordinal counts as low consensus. Tune per I/O psychologist sign-off (SCIENCE-SPEC §7).'),
  (null, 'min_evaluators_for_valid_run',  4, 'DEV STUB — minimum independent evaluators for a run to be considered psychometrically valid.'),
  (null, 'iccc_signoff_cutoff',         0.7, 'DEV STUB — ICC cutoff for sign-off (Shrout & Fleiss 1979 ICC(3,k)).')
on conflict (org_id, threshold_key) do nothing;
