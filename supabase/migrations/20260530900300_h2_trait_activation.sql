-- H-2 — Trait Activation Theory Infrastructure (Run 4 of H-1..H-10)
--
-- Tett & Burnett 2003 / Tett et al. 2021: trait expression is moderated
-- by situational cues at task, social, and organizational levels in five
-- categories — demands, distractors, constraints, releasers,
-- facilitators. A role profile that ignores context cannot defensibly
-- claim "this band of Conscientiousness is right for this job" because
-- the appropriate band depends on the situation the trait will operate in.
--
-- This run adds:
--   1. trait_activation_factor_catalog — global registry of factor keys,
--      one row per (factor_key). Each factor declares its level
--      (task|social|organizational), its TAT category, a human-readable
--      name and description, and a primary citation. Per CLAUDE.md
--      "Template-driven" pillar: this is configurable data, not a
--      hardcoded enum, so an I/O psychologist can extend it without
--      a code change.
--   2. role_context_factors — per role_id, the rating of each factor
--      on a 1..5 intensity scale + a free-text rationale. Sparse
--      (you don't need to rate every factor for every role).
--   3. rpc_factor_catalog_signoff — promotes a catalog row from
--      dev_stub to validated (modeling.signoff in any membership).
--   4. rpc_role_context_signoff — promotes the rating set for ONE
--      role from dev_stub to validated (role.signoff in role's org).
--
-- Discipline: every catalog row + every per-role rating ships
-- _dev_stub=true. The factor-key list seeded below is the TAT taxonomy
-- (Tett & Burnett 2003 Table 1); the level/category metadata is direct
-- restatement of the published model, but each row stays dev_stub
-- until our engaged I/O psychologist confirms the operational
-- definitions match our population/context.
--
-- INFRASTRUCTURE ONLY: no modulation math here. How a factor RATING
-- shifts a trait band (the modulation rule) is its own decision domain
-- that depends on having validated trait bands first; that decision
-- system can be added in a follow-up run.

-- ─── 1. Enums ─────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_type where typname='trait_activation_level') then
    create type public.trait_activation_level as enum ('task','social','organizational');
  end if;
  if not exists (select 1 from pg_type where typname='trait_activation_category') then
    create type public.trait_activation_category as enum (
      'demand','distractor','constraint','releaser','facilitator'
    );
  end if;
end $$;

-- ─── 2. Factor catalog ───────────────────────────────────────────────
create table if not exists public.trait_activation_factor_catalog (
  id                          uuid primary key default gen_random_uuid(),
  factor_key                  text not null unique,
  level                       public.trait_activation_level    not null,
  category                    public.trait_activation_category not null,
  name                        text not null,
  description                 text not null,

  primary_citation_id         uuid references public.citations(id),
  validity_status             public.validity_status not null default 'dev_stub',
  _dev_stub                   boolean not null default true,

  signoff_actor_id            uuid references public.people(id),
  signoff_at                  timestamptz,
  signoff_rationale           text,

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  created_by                  uuid references public.people(id),

  constraint tafc_name_min_len          check (length(name) >= 3),
  constraint tafc_description_min_len   check (length(description) >= 20),
  constraint tafc_signoff_rationale_len check (
    signoff_rationale is null or length(signoff_rationale) >= 50
  ),
  constraint tafc_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 50
    )
  )
);

comment on table public.trait_activation_factor_catalog is
  'Global registry of Trait Activation factors (Tett & Burnett 2003). Each row declares a (level, category) pair and the operational definition. Per-row dev_stub seam: a factor cannot be promoted to validated without modeling.signoff + rationale ≥50.';

create index if not exists tafc_level_idx    on public.trait_activation_factor_catalog(level);
create index if not exists tafc_category_idx on public.trait_activation_factor_catalog(category);
create index if not exists tafc_status_idx   on public.trait_activation_factor_catalog(validity_status);

drop trigger if exists trg_tafc_updated_at on public.trait_activation_factor_catalog;
create trigger trg_tafc_updated_at
  before update on public.trait_activation_factor_catalog
  for each row execute function public.set_updated_at();

-- ─── 3. Per-role factor ratings ───────────────────────────────────────
create table if not exists public.role_context_factors (
  id                          uuid primary key default gen_random_uuid(),
  org_id                      uuid not null references public.organizations(id),
  role_id                     uuid not null references public.roles_catalog(id) on delete cascade,
  factor_key                  text not null references public.trait_activation_factor_catalog(factor_key),

  intensity                   smallint not null,           -- 1..5
  rationale                   text not null,               -- ≥30 chars

  validity_status             public.validity_status not null default 'dev_stub',
  _dev_stub                   boolean not null default true,

  signoff_actor_id            uuid references public.people(id),
  signoff_at                  timestamptz,
  signoff_rationale           text,

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  created_by                  uuid references public.people(id),

  constraint rcf_intensity_range check (intensity between 1 and 5),
  constraint rcf_rationale_min_len check (length(rationale) >= 30),
  constraint rcf_signoff_rationale_min_len check (
    signoff_rationale is null or length(signoff_rationale) >= 50
  ),
  constraint rcf_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 50
    )
  ),
  unique (role_id, factor_key)
);

comment on table public.role_context_factors is
  'Per-role Trait Activation factor ratings (1..5 intensity). Sparse — a role only carries rows for factors that materially apply. Per-row sign-off via rpc_role_context_signoff (role.signoff in role.org).';

create index if not exists rcf_org_idx    on public.role_context_factors(org_id);
create index if not exists rcf_role_idx   on public.role_context_factors(role_id);
create index if not exists rcf_factor_idx on public.role_context_factors(factor_key);
create index if not exists rcf_status_idx on public.role_context_factors(validity_status);

drop trigger if exists trg_rcf_updated_at on public.role_context_factors;
create trigger trg_rcf_updated_at
  before update on public.role_context_factors
  for each row execute function public.set_updated_at();

-- ─── 4. Sign-off RPCs ────────────────────────────────────────────────
create or replace function public.rpc_factor_catalog_signoff(
  p_factor_key         text,
  p_decision_rationale text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller_person_id uuid;
  v_row              public.trait_activation_factor_catalog%rowtype;
begin
  if not public.has_global_permission('modeling.signoff') then
    raise exception 'denied: modeling.signoff required' using errcode='42501';
  end if;
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 50 then
    raise exception 'rationale must be at least 50 characters' using errcode='22023';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;
  select * into v_row from public.trait_activation_factor_catalog where factor_key=p_factor_key for update;
  if not found then
    raise exception 'factor % not found', p_factor_key using errcode='P0002';
  end if;
  update public.trait_activation_factor_catalog
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where factor_key=p_factor_key;
  perform public.audit_log_event(
    null, 'trait_factor.signoff', 'trait_activation_factor_catalog', v_row.id,
    to_jsonb(v_row),
    jsonb_build_object('factor_key', p_factor_key, 'signoff_actor_id', v_caller_person_id,
      'rationale_length', length(p_decision_rationale)), null);
  return jsonb_build_object('ok', true, 'factor_key', p_factor_key,
    'validity_status','validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_factor_catalog_signoff(text, text) from public;
grant execute on function public.rpc_factor_catalog_signoff(text, text) to authenticated, service_role;

create or replace function public.rpc_role_context_signoff(
  p_role_id            uuid,
  p_decision_rationale text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller_person_id uuid;
  v_org_id           uuid;
  v_n_rows           int;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 50 then
    raise exception 'rationale must be at least 50 characters' using errcode='22023';
  end if;

  select rc.org_id into v_org_id from public.roles_catalog rc where rc.id=p_role_id;
  if v_org_id is null then
    raise exception 'role % not found or has no org', p_role_id using errcode='P0002';
  end if;

  if not public.has_permission(v_org_id, 'role.signoff') then
    raise exception 'denied: role.signoff required in org %', v_org_id using errcode='42501';
  end if;

  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;

  with upd as (
    update public.role_context_factors
       set validity_status='validated', _dev_stub=false,
           signoff_actor_id=v_caller_person_id, signoff_at=now(),
           signoff_rationale=p_decision_rationale, updated_at=now()
     where role_id=p_role_id
       and validity_status <> 'validated'
    returning 1
  )
  select count(*) into v_n_rows from upd;

  perform public.audit_log_event(
    v_org_id, 'role_context.signoff', 'role_context_factors', null,
    null,
    jsonb_build_object('role_id', p_role_id, 'n_rows_validated', v_n_rows,
      'signoff_actor_id', v_caller_person_id,
      'rationale_length', length(p_decision_rationale)), null);

  return jsonb_build_object('ok', true, 'role_id', p_role_id,
    'n_rows_validated', v_n_rows, 'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_role_context_signoff(uuid, text) from public;
grant execute on function public.rpc_role_context_signoff(uuid, text) to authenticated, service_role;

-- ─── 5. RLS ───────────────────────────────────────────────────────────
alter table public.trait_activation_factor_catalog enable row level security;
alter table public.trait_activation_factor_catalog force  row level security;
alter table public.role_context_factors            enable row level security;
alter table public.role_context_factors            force  row level security;

drop policy if exists tafc_select_authenticated on public.trait_activation_factor_catalog;
create policy tafc_select_authenticated on public.trait_activation_factor_catalog
  for select using ((select auth.uid()) is not null);

drop policy if exists tafc_insert_modeling on public.trait_activation_factor_catalog;
create policy tafc_insert_modeling on public.trait_activation_factor_catalog
  for insert with check (public.has_global_permission('modeling.write'));

drop policy if exists tafc_update_modeling on public.trait_activation_factor_catalog;
create policy tafc_update_modeling on public.trait_activation_factor_catalog
  for update using (public.has_global_permission('modeling.write'))
              with check (public.has_global_permission('modeling.write'));

drop policy if exists rcf_select_org on public.role_context_factors;
create policy rcf_select_org on public.role_context_factors
  for select using (public.has_permission(org_id, 'role.read'));

drop policy if exists rcf_write_role on public.role_context_factors;
create policy rcf_write_role on public.role_context_factors
  for insert with check (public.has_permission(org_id, 'role.create'));

drop policy if exists rcf_update_role on public.role_context_factors;
create policy rcf_update_role on public.role_context_factors
  for update using (public.has_permission(org_id, 'role.create'))
              with check (public.has_permission(org_id, 'role.create'));

grant select on public.trait_activation_factor_catalog, public.role_context_factors to authenticated;
grant insert, update, delete on public.trait_activation_factor_catalog, public.role_context_factors to authenticated;

-- ─── 6. Seed Tett & Burnett 2003 TAT factor taxonomy ─────────────────
-- These are textbook factors with published operational definitions.
-- _dev_stub = true: pending our population's I/O sign-off.
insert into public.trait_activation_factor_catalog
  (factor_key, level, category, name, description, primary_citation_id)
select pt.factor_key, pt.level::public.trait_activation_level,
       pt.category::public.trait_activation_category,
       pt.name, pt.description,
       (select id from public.citations where citation_key='tett-burnett-2003-jap')
from (values
  -- TASK level
  ('task_ambiguity',        'task',          'demand',
   'Task Ambiguity',
   'Degree to which the role''s tasks have unclear goals, methods, or success criteria. High ambiguity demands trait expression of conscientious self-direction.'),
  ('task_complexity',       'task',          'demand',
   'Task Complexity',
   'Number of distinct subtasks, interdependencies, and information sources required to complete the typical workflow. Moderates inverted-U inflection per Le 2011.'),
  ('task_repetition',       'task',          'constraint',
   'Task Repetition',
   'Degree to which the role is repetitive vs varied. High repetition CONSTRAINS extraversion expression and may suppress curiosity-driven facets of Openness.'),
  ('time_pressure',         'task',          'demand',
   'Time Pressure',
   'Degree to which work is governed by hard deadlines, customer-facing real-time response, or compressed cycle times. Activates Conscientiousness and Emotional Stability.'),
  ('autonomy',              'task',          'releaser',
   'Autonomy',
   'Degree of latitude the role-holder has over methods, sequencing, and pace. High autonomy RELEASES intrinsic-trait expression — both helpful (Conscientiousness) and harmful (low integrity) facets.'),
  -- SOCIAL level
  ('team_interdependence',  'social',        'demand',
   'Team Interdependence',
   'Degree to which the role''s outputs require coordination with teammates (vs solo work). Activates Agreeableness and conscientious follow-through.'),
  ('customer_facing',       'social',        'demand',
   'Customer Facing',
   'Fraction of work time spent in real-time interactions with external customers/clients. Activates Extraversion and Emotional Stability; per Grant 2013 favours the ambivert peak, not extreme extraversion.'),
  ('conflict_frequency',    'social',        'demand',
   'Conflict Frequency',
   'How often the role-holder must navigate disagreement (negotiation, mediation, resource conflicts). Activates Emotional Stability and Agreeableness.'),
  -- ORGANIZATIONAL level
  ('strict_compliance',     'organizational','constraint',
   'Strict Compliance Regime',
   'Degree to which the role operates under formal compliance/audit/regulatory constraints. CONSTRAINS Openness expression and amplifies the penalty for low Conscientiousness.'),
  ('change_velocity',       'organizational','demand',
   'Organizational Change Velocity',
   'Rate of organizational restructuring, strategy pivots, or process change the role-holder must absorb. Activates Openness and Emotional Stability.'),
  ('innovation_emphasis',   'organizational','facilitator',
   'Innovation Emphasis',
   'Cultural premium on novel approaches, experimentation, and tolerance of failure. FACILITATES Openness expression and shifts trait targets accordingly.')
) as pt(factor_key, level, category, name, description)
on conflict (factor_key) do nothing;
