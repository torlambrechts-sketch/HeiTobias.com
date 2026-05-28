-- team_definition_tables — Phase 1 capability: team-based role definition.
--
--   role_definition_evaluations    — one row per (evaluator, requisition).
--                                    ratings_json carries the evaluator's
--                                    independent ratings of role criteria.
--                                    submitted_at null = locked draft, only
--                                    visible to the evaluator themself.
--   role_definition_reconciliations — the divergence calc + reconciled spec
--                                    produced by combining all submitted
--                                    evaluations. May produce a new
--                                    roles_catalog version via the Phase 0 RPC.
--
-- HARD RULE (CLAUDE.md "never" list): this is rating of role *criteria*, not
-- rating of people. There is NO table here that lets peers rate each other's
-- personalities, and there must never be one. Team composition derivations
-- elsewhere operate ONLY on members' own validated profiles.

-- ---- role_definition_evaluations -----------------------------------------

create table public.role_definition_evaluations (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  requisition_id  uuid not null references public.requisitions(id) on delete cascade,
  evaluator_id    uuid not null references public.people(id)        on delete restrict,
  ratings_json    jsonb not null default '[]'::jsonb,
  submitted_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  unique (requisition_id, evaluator_id),

  -- ratings_json: array of {criterion, importance, rationale?}.
  --   - criterion : string key (matches a competency_frameworks competencies key)
  --   - importance: number 0..1
  --   - rationale : optional free text
  constraint chk_rde_ratings_shape check (
    extensions.jsonb_matches_schema(
      schema := '{
        "type":"array",
        "items":{
          "type":"object",
          "required":["criterion","importance"],
          "properties":{
            "criterion":{"type":"string"},
            "importance":{"type":"number","minimum":0,"maximum":1},
            "rationale":{"type":["string","null"]}
          },
          "additionalProperties":false
        }
      }'::json,
      instance := ratings_json
    )
  )
);

create index role_definition_evaluations_req_idx
  on public.role_definition_evaluations (requisition_id);
create index role_definition_evaluations_evaluator_idx
  on public.role_definition_evaluations (evaluator_id);
create index role_definition_evaluations_submitted_partial
  on public.role_definition_evaluations (requisition_id)
  where submitted_at is not null;

create trigger trg_rde_updated_at
  before update on public.role_definition_evaluations
  for each row execute function public.set_updated_at();
create trigger trg_audit_role_definition_evaluations
  after insert or update or delete on public.role_definition_evaluations
  for each row execute function public._audit_row();

alter table public.role_definition_evaluations enable row level security;

-- SELECT: independence lock. You see (a) your own rows always, (b) others'
-- SUBMITTED rows iff you have either reconcile permission OR your own
-- submitted row for the same requisition. Drafts never leak.
create policy rde_select on public.role_definition_evaluations
  for select to authenticated
  using (
    public.is_self(evaluator_id)
    or (
      submitted_at is not null
      and (
        public.has_permission(org_id, 'team_definition.reconcile')
        or exists (
          select 1 from public.role_definition_evaluations mine
          where mine.requisition_id = role_definition_evaluations.requisition_id
            and public.is_self(mine.evaluator_id)
            and mine.submitted_at is not null
        )
      )
    )
  );

-- INSERT: only insert your own row, and only with the rating permission.
create policy rde_insert on public.role_definition_evaluations
  for insert to authenticated
  with check (
    public.is_self(evaluator_id)
    and public.has_permission(org_id, 'team_definition.rate')
  );

-- UPDATE: only your own DRAFT row. Once submitted_at is set, the row is locked.
-- WITH CHECK still requires self so an UPDATE cannot reassign the row.
create policy rde_update on public.role_definition_evaluations
  for update to authenticated
  using      (public.is_self(evaluator_id) and submitted_at is null)
  with check (public.is_self(evaluator_id));

-- DELETE: own draft only. Submitted rows are immutable history.
create policy rde_delete on public.role_definition_evaluations
  for delete to authenticated
  using (public.is_self(evaluator_id) and submitted_at is null);

comment on table public.role_definition_evaluations is
  'One row per (evaluator, requisition) carrying that evaluator''s independent ratings of role criteria. Drafts are private to the evaluator; submitted rows are visible to others who have also submitted (or who have team_definition.reconcile). NO peer-personality rating here — criteria importance only.';

-- ---- role_definition_reconciliations -------------------------------------

create table public.role_definition_reconciliations (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id) on delete restrict,
  requisition_id      uuid not null references public.requisitions(id)  on delete restrict,
  -- divergence_json: per-criterion spread/disagreement stats. Surfaced, not averaged silently.
  divergence_json     jsonb not null default '{}'::jsonb
                        check (jsonb_typeof(divergence_json) = 'object'),
  -- reconciled_json: the final, agreed-upon ratings_json shape (same schema as evaluations).
  reconciled_json     jsonb not null default '[]'::jsonb
                        check (jsonb_typeof(reconciled_json) = 'array'),
  produced_role_id    uuid references public.roles_catalog(id) on delete set null,
  reconciled_by       uuid references public.people(id) on delete set null,
  reconciled_at       timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index rdr_req_idx       on public.role_definition_reconciliations (requisition_id);
create index rdr_produced_idx  on public.role_definition_reconciliations (produced_role_id);

create trigger trg_rdr_updated_at
  before update on public.role_definition_reconciliations
  for each row execute function public.set_updated_at();
create trigger trg_audit_role_definition_reconciliations
  after insert or update or delete on public.role_definition_reconciliations
  for each row execute function public._audit_row();

alter table public.role_definition_reconciliations enable row level security;

-- SELECT: anyone in the org with role.read or reconcile.
create policy rdr_select on public.role_definition_reconciliations
  for select to authenticated
  using (
    public.has_permission(org_id, 'role.read')
    or public.has_permission(org_id, 'team_definition.reconcile')
  );

-- INSERT/UPDATE: reconcile permission.
create policy rdr_insert on public.role_definition_reconciliations
  for insert to authenticated
  with check (public.has_permission(org_id, 'team_definition.reconcile'));
create policy rdr_update on public.role_definition_reconciliations
  for update to authenticated
  using      (public.has_permission(org_id, 'team_definition.reconcile'))
  with check (public.has_permission(org_id, 'team_definition.reconcile'));

comment on table public.role_definition_reconciliations is
  'Aggregated divergence + reconciled spec from a team-based role definition. divergence_json surfaces disagreement; produced_role_id links to the resulting roles_catalog version.';
