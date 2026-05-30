-- H-1b — Predictor Combination Audit Trail (Run 2 of H-1..H-10)
--
-- When an org chooses a predictor combination for a role (or for one
-- specific requisition), we record the choice in versioned form so a
-- future Annex IV / DPIA can reconstruct any historical decision. The
-- decision references which evidence_base_positions (and which
-- evidence_base version_id) were in scope at the time.
--
-- Per the H-1..H-10 prompt's "extend existing tables" answer: this
-- table REFERENCES roles_catalog and requisitions (it does not extend
-- them). Predictor selection is its own decision domain, separate from
-- role definition (roles_catalog.definition_json) and from per-
-- candidate fit (fit_results.fit_json). Storing it alongside either
-- would mix concerns and obscure the audit trail.

-- ─── 1. Enum + table ─────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_type where typname = 'predictor_combo_scope') then
    create type public.predictor_combo_scope as enum ('role','requisition');
  end if;
end $$;

create table if not exists public.predictor_combination_decisions (
  id                          uuid primary key default gen_random_uuid(),
  org_id                      uuid not null references public.organizations(id),
  scope                       public.predictor_combo_scope not null,

  role_id                     uuid references public.roles_catalog(id),
  requisition_id              uuid references public.requisitions(id),

  -- Pin to a versioned evidence-base snapshot
  evidence_base_version_id    text not null,

  -- The combo itself: array of objects with shape
  --   { predictor_type: <evidence_predictor_type>,
  --     weight: <numeric 0..1>,
  --     anchor_position_id: <uuid → evidence_base_positions.id>,
  --     anchor_validity: <numeric 0..1, copied at decision time>,
  --     rationale: <text>,
  --     notes: <text?> }
  combo_json                  jsonb not null,
  weights_sum_to              numeric(5,3),

  -- Overall rationale for this combo choice
  rationale                   text not null,

  -- Versioning chain
  supersedes_id               uuid references public.predictor_combination_decisions(id),
  superseded_at               timestamptz,                    -- null = current

  -- Dev-stub seam
  validity_status             public.validity_status not null default 'dev_stub',
  _dev_stub                   boolean not null default true,

  -- Sign-off (modeling.signoff in this org)
  signoff_actor_id            uuid references public.people(id),
  signoff_at                  timestamptz,
  signoff_rationale           text,

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  created_by                  uuid references public.people(id),
  is_demo_data                boolean not null default false,

  constraint pcd_scope_role_present check (
    scope <> 'role' or role_id is not null
  ),
  constraint pcd_scope_req_present check (
    scope <> 'requisition' or requisition_id is not null
  ),
  constraint pcd_rationale_min_len check (
    length(rationale) >= 50
  ),
  constraint pcd_signoff_rationale_min_len check (
    signoff_rationale is null or length(signoff_rationale) >= 100
  ),
  constraint pcd_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    )
  ),
  constraint pcd_weights_sum_close_to_one check (
    weights_sum_to is null
    or (weights_sum_to >= 0.990 and weights_sum_to <= 1.010)
  ),
  constraint pcd_combo_is_nonempty_array check (
    jsonb_typeof(combo_json) = 'array' and jsonb_array_length(combo_json) >= 1
  )
);

comment on table public.predictor_combination_decisions is
  'Versioned predictor-combination decisions per org. Each row pins a (predictors × weights × evidence_base_version) choice with rationale and (optionally) sign-off. References roles_catalog / requisitions but is a separate audit-trail entity. supersedes_id chains; superseded_at IS NULL means current.';

create index if not exists pcd_org_idx          on public.predictor_combination_decisions(org_id);
create index if not exists pcd_role_idx         on public.predictor_combination_decisions(role_id)        where role_id is not null;
create index if not exists pcd_requisition_idx  on public.predictor_combination_decisions(requisition_id) where requisition_id is not null;
create index if not exists pcd_status_idx       on public.predictor_combination_decisions(validity_status);
create index if not exists pcd_supersedes_idx   on public.predictor_combination_decisions(supersedes_id) where supersedes_id is not null;

-- One CURRENT (superseded_at IS NULL) row per (org, scope, role_id, requisition_id).
-- The two columns role_id / requisition_id are mutually exclusive per scope, so a
-- single conflict pattern with COALESCE-to-uuid-nil keeps the index sane.
create unique index if not exists pcd_one_current_per_target
  on public.predictor_combination_decisions
     (org_id, scope,
      coalesce(role_id,        '00000000-0000-0000-0000-000000000000'::uuid),
      coalesce(requisition_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where superseded_at is null;

-- ─── 2. updated_at trigger ───────────────────────────────────────────
drop trigger if exists trg_pcd_updated_at on public.predictor_combination_decisions;
create trigger trg_pcd_updated_at
  before update on public.predictor_combination_decisions
  for each row execute function public.set_updated_at();

-- ─── 3. View: current decisions joined to evidence base ──────────────
create or replace view public.v_current_predictor_combination as
select
  pcd.id,
  pcd.org_id,
  pcd.scope,
  pcd.role_id,
  pcd.requisition_id,
  pcd.evidence_base_version_id,
  pcd.combo_json,
  pcd.weights_sum_to,
  pcd.rationale,
  pcd.validity_status,
  pcd._dev_stub,
  pcd.signoff_actor_id,
  pcd.signoff_at,
  pcd.created_at,
  pcd.created_by
from public.predictor_combination_decisions pcd
where pcd.superseded_at is null;

-- ─── 4. RPC: persist a new combo decision (atomic supersede + insert)
create or replace function public.rpc_predictor_combo_decision(
  p_org_id              uuid,
  p_scope               public.predictor_combo_scope,
  p_role_id             uuid,
  p_requisition_id      uuid,
  p_combo               jsonb,
  p_rationale           text,
  p_evidence_version    text default 'ebv-2025-01'
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_person_id  uuid;
  v_new_id            uuid;
  v_prior_id          uuid;
  v_weights_sum       numeric;
  v_item              jsonb;
  v_predictor_type    text;
  v_weight            numeric;
  v_anchor_position   uuid;
  v_anchor_row        public.evidence_base_positions%rowtype;
  v_seen_predictors   text[] := array[]::text[];
begin
  -- Permission gate
  if not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'denied: modeling.write required in org %', p_org_id using errcode='42501';
  end if;
  -- Caller identity
  select pp.id into v_caller_person_id
    from public.people pp where pp.auth_user_id = (select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;
  -- Rationale
  if p_rationale is null or length(trim(p_rationale)) < 50 then
    raise exception 'rationale must be at least 50 characters' using errcode='22023';
  end if;
  -- Scope coherence
  if p_scope = 'role' and p_role_id is null then
    raise exception 'role scope requires role_id' using errcode='22023';
  end if;
  if p_scope = 'requisition' and p_requisition_id is null then
    raise exception 'requisition scope requires requisition_id' using errcode='22023';
  end if;
  -- Combo shape
  if jsonb_typeof(p_combo) <> 'array' or jsonb_array_length(p_combo) < 1 then
    raise exception 'combo_json must be a non-empty array' using errcode='22023';
  end if;

  -- Walk combo entries: validate each + sum weights
  v_weights_sum := 0;
  for v_item in select * from jsonb_array_elements(p_combo) loop
    v_predictor_type := v_item->>'predictor_type';
    v_weight         := (v_item->>'weight')::numeric;
    v_anchor_position:= (v_item->>'anchor_position_id')::uuid;

    if v_predictor_type is null then
      raise exception 'combo entry missing predictor_type' using errcode='22023';
    end if;
    if v_weight is null or v_weight < 0 or v_weight > 1 then
      raise exception 'combo entry weight out of [0,1]: %', v_weight using errcode='22023';
    end if;
    if v_predictor_type = any(v_seen_predictors) then
      raise exception 'duplicate predictor_type in combo: %', v_predictor_type using errcode='22023';
    end if;
    v_seen_predictors := v_seen_predictors || v_predictor_type;

    if v_anchor_position is null then
      raise exception 'combo entry missing anchor_position_id for %', v_predictor_type
        using errcode='22023';
    end if;
    select * into v_anchor_row from public.evidence_base_positions
     where id = v_anchor_position;
    if not found then
      raise exception 'anchor_position_id % does not exist', v_anchor_position
        using errcode='P0002';
    end if;
    if v_anchor_row.predictor_type::text <> v_predictor_type then
      raise exception 'anchor_position_id % is for predictor_type % but combo entry says %',
        v_anchor_position, v_anchor_row.predictor_type, v_predictor_type
        using errcode='22023';
    end if;
    if v_anchor_row.version_id <> p_evidence_version then
      raise exception 'anchor_position_id % belongs to version % but combo pins version %',
        v_anchor_position, v_anchor_row.version_id, p_evidence_version
        using errcode='22023';
    end if;
    v_weights_sum := v_weights_sum + v_weight;
  end loop;

  if v_weights_sum < 0.990 or v_weights_sum > 1.010 then
    raise exception 'sum of weights must be ≈1.0, got %', v_weights_sum
      using errcode='22023';
  end if;

  -- Find + supersede prior current
  select id into v_prior_id
    from public.predictor_combination_decisions
   where org_id = p_org_id
     and scope = p_scope
     and coalesce(role_id,        '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(p_role_id,      '00000000-0000-0000-0000-000000000000'::uuid)
     and coalesce(requisition_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(p_requisition_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and superseded_at is null
   for update;

  if v_prior_id is not null then
    update public.predictor_combination_decisions
       set superseded_at = now(), updated_at = now()
     where id = v_prior_id;
  end if;

  insert into public.predictor_combination_decisions
    (org_id, scope, role_id, requisition_id,
     evidence_base_version_id, combo_json, weights_sum_to,
     rationale, supersedes_id,
     validity_status, _dev_stub, created_by)
  values
    (p_org_id, p_scope, p_role_id, p_requisition_id,
     p_evidence_version, p_combo, v_weights_sum,
     p_rationale, v_prior_id,
     'dev_stub', true, v_caller_person_id)
  returning id into v_new_id;

  perform public.audit_log_event(
    p_org_id, 'predictor_combo.decision', 'predictor_combination_decision', v_new_id,
    case when v_prior_id is null then null
         else jsonb_build_object('superseded_id', v_prior_id) end,
    jsonb_build_object(
      'scope', p_scope,
      'role_id', p_role_id,
      'requisition_id', p_requisition_id,
      'evidence_version', p_evidence_version,
      'weights_sum', v_weights_sum,
      'n_predictors', jsonb_array_length(p_combo),
      'predictors', v_seen_predictors,
      'rationale_length', length(p_rationale),
      'actor', v_caller_person_id
    ),
    null);

  return jsonb_build_object(
    'ok', true,
    'id', v_new_id,
    'superseded_id', v_prior_id,
    'weights_sum_to', v_weights_sum,
    'validity_status', 'dev_stub');
end;
$$;

revoke all on function public.rpc_predictor_combo_decision(uuid, public.predictor_combo_scope, uuid, uuid, jsonb, text, text) from public;
grant execute on function public.rpc_predictor_combo_decision(uuid, public.predictor_combo_scope, uuid, uuid, jsonb, text, text)
  to authenticated, service_role;

-- ─── 5. RPC: sign-off a combo decision ───────────────────────────────
create or replace function public.rpc_predictor_combo_signoff(
  p_combo_id           uuid,
  p_decision_rationale text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_person_id uuid;
  v_row              public.predictor_combination_decisions%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;

  select * into v_row from public.predictor_combination_decisions
   where id = p_combo_id for update;
  if not found then
    raise exception 'predictor_combination_decision % not found', p_combo_id
      using errcode='P0002';
  end if;

  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id
      using errcode='42501';
  end if;
  select pp.id into v_caller_person_id
    from public.people pp where pp.auth_user_id = (select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;

  update public.predictor_combination_decisions
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_combo_id;

  perform public.audit_log_event(
    v_row.org_id, 'predictor_combo.signoff', 'predictor_combination_decision', p_combo_id,
    to_jsonb(v_row),
    jsonb_build_object(
      'signoff_actor_id', v_caller_person_id,
      'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'previous_status', v_row.validity_status,
      'previous_dev_stub', v_row._dev_stub),
    null);

  return jsonb_build_object('ok', true, 'id', p_combo_id,
    'validity_status','validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_predictor_combo_signoff(uuid, text) from public;
grant execute on function public.rpc_predictor_combo_signoff(uuid, text) to authenticated, service_role;

-- ─── 6. RLS ───────────────────────────────────────────────────────────
alter table public.predictor_combination_decisions enable row level security;
alter table public.predictor_combination_decisions force  row level security;

drop policy if exists pcd_select_org_member on public.predictor_combination_decisions;
create policy pcd_select_org_member on public.predictor_combination_decisions
  for select using (
    public.has_permission(org_id, 'modeling.read')
    or public.has_permission(org_id, 'modeling.write')
    or public.has_permission(org_id, 'role.read')
  );

drop policy if exists pcd_insert_modeling on public.predictor_combination_decisions;
create policy pcd_insert_modeling on public.predictor_combination_decisions
  for insert with check (public.has_permission(org_id, 'modeling.write'));

drop policy if exists pcd_update_modeling on public.predictor_combination_decisions;
create policy pcd_update_modeling on public.predictor_combination_decisions
  for update using (public.has_permission(org_id, 'modeling.write'))
              with check (public.has_permission(org_id, 'modeling.write'));

drop policy if exists pcd_delete_modeling on public.predictor_combination_decisions;
create policy pcd_delete_modeling on public.predictor_combination_decisions
  for delete using (public.has_permission(org_id, 'modeling.write'));

grant select on public.predictor_combination_decisions,
                public.v_current_predictor_combination
  to authenticated;
grant insert, update, delete on public.predictor_combination_decisions to authenticated;
