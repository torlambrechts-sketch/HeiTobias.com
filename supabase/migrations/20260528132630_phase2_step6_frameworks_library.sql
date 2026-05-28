-- phase2_step6_frameworks_library — labeled DEV-STUB management frameworks.
--
-- Same I/O-seam discipline as Phase 1's psychometric instruments:
-- the engine is ours to build; the content is pluggable, labeled, and
-- never fabricated as "validated". Adding licensed framework content
-- is a row update against this table — no code change needed.

create table public.frameworks (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid references public.organizations(id),   -- null = global
  key             text not null,
  kind            text not null check (kind in ('milestone_template','manager_prompt','check_in_template')),
  name            text not null,
  body_json       jsonb not null default '{}'::jsonb,
  validity_status public.validity_status not null default 'dev_stub',
  _dev_stub       boolean not null default true,
  vendor          text,
  version         text not null default '0.0.1-dev',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (org_id, key, version),
  -- Same load-bearing check as the Phase 1 I/O seam: a validated row may
  -- not carry an empty body_json or claim _dev_stub.
  constraint chk_frameworks_validated_real
    check (validity_status <> 'validated'
           or (body_json <> '{}'::jsonb and coalesce(_dev_stub, false) = false))
);
create index frameworks_kind_idx on public.frameworks (kind);
create index frameworks_org_idx  on public.frameworks (org_id);

create trigger trg_touch_frameworks before update on public.frameworks
  for each row execute function public.set_updated_at();
create trigger trg_audit_frameworks after insert or update or delete on public.frameworks
  for each row execute function public._audit_row();

alter table public.frameworks enable row level security;
alter table public.frameworks force  row level security;

create policy frameworks_select on public.frameworks
  for select using (
    org_id is null
    or public.has_permission(org_id, 'org.read')
  );
create policy frameworks_write on public.frameworks
  for all using (
    org_id is not null and public.has_permission(org_id, 'org.manage_all')
  ) with check (
    org_id is not null and public.has_permission(org_id, 'org.manage_all')
  );

-- ---- kickstart_plans ----
-- One row per generated plan. plan_json holds the 30/60/90 milestones
-- (each milestone cites a framework_id — that's the grounded-not-freeform
-- discipline made structural).
create table public.kickstart_plans (
  id                 uuid primary key default extensions.gen_random_uuid(),
  org_id             uuid not null references public.organizations(id),
  person_id          uuid not null references public.people(id),
  role_id            uuid references public.roles_catalog(id),
  ongoing_consent_id uuid not null references public.consent_grants(id),
  plan_json          jsonb not null,
  frameworks_used    uuid[] not null default '{}',
  validity_status    public.validity_status not null default 'dev_stub',
  _dev_stub          boolean not null default true,
  generated_by       uuid references public.people(id),
  generated_at       timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index kickstart_plans_person_idx on public.kickstart_plans (person_id, org_id);

create trigger trg_touch_kickstart_plans before update on public.kickstart_plans
  for each row execute function public.set_updated_at();
create trigger trg_audit_kickstart_plans after insert or update or delete on public.kickstart_plans
  for each row execute function public._audit_row();

alter table public.kickstart_plans enable row level security;
alter table public.kickstart_plans force  row level security;

-- Read: subject sees their own; manager / people_ops with org.read + ongoing_management consent.
create policy kickstart_plans_select on public.kickstart_plans
  for select using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'org.read')
      and public.in_scope(org_id, person_id)
      and public.consent_active(ongoing_consent_id, 'ongoing_management')
    )
  );

create policy kickstart_plans_insert on public.kickstart_plans
  for insert with check (
    public.has_permission(org_id, 'org.manage_all')
    and public.consent_active(ongoing_consent_id, 'ongoing_management')
  );

-- ---- Seed DEV-STUB frameworks ----
insert into public.frameworks (org_id, key, kind, name, body_json, validity_status, _dev_stub, vendor) values
(null, 'week1_orientation', 'milestone_template', 'DEV STUB · Week 1 — orientation',
  jsonb_build_object(
    'day_offset', 7,
    'title', 'First week orientation',
    'narrative', 'DEV STUB — replace with licensed onboarding framework.',
    'manager_prompts', jsonb_build_array(
      'Walk through team rituals and the codebase tour.',
      'Pair them with a buddy for week 1.',
      'Schedule a no-agenda 1:1 to surface questions.'
    )
  ), 'dev_stub', true, 'HeiTobias (DEV STUB)'),
(null, 'day30_first_contribution', 'milestone_template', 'DEV STUB · Day 30 — first contribution',
  jsonb_build_object(
    'day_offset', 30,
    'title', 'First independent contribution',
    'narrative', 'DEV STUB — replace with real framework.',
    'manager_prompts', jsonb_build_array(
      'Confirm they''ve shipped one small but visible piece.',
      'Run a structured check-in: what''s clear, what''s ambiguous, what''s blocking.'
    )
  ), 'dev_stub', true, 'HeiTobias (DEV STUB)'),
(null, 'day60_responsibility_widening', 'milestone_template', 'DEV STUB · Day 60 — widening responsibility',
  jsonb_build_object(
    'day_offset', 60,
    'title', 'Widening responsibility',
    'narrative', 'DEV STUB — replace.',
    'manager_prompts', jsonb_build_array(
      'Hand them a project of meaningful scope.',
      'Surface any divergence between role expectations and observed work.'
    )
  ), 'dev_stub', true, 'HeiTobias (DEV STUB)'),
(null, 'day90_re_fit_check', 'milestone_template', 'DEV STUB · Day 90 — first re-fit check',
  jsonb_build_object(
    'day_offset', 90,
    'title', 'First re-fit check',
    'narrative', 'DEV STUB — replace. Bridges into Phase 3 re-fit cadence.',
    'manager_prompts', jsonb_build_array(
      'Compare role definition against observed strengths/gaps.',
      'Plan the next 90 days of development with the employee.',
      'Capture explicit decision: continue, recalibrate, intervene.'
    )
  ), 'dev_stub', true, 'HeiTobias (DEV STUB)'),

-- Trait-tailored prompts the generator MAY include based on the person's profile.
(null, 'prompt_low_ambiguity_tolerance', 'manager_prompt',
  'DEV STUB · Low ambiguity tolerance — front-load structure',
  jsonb_build_object(
    'trigger', jsonb_build_object('trait', 'tolerance_for_ambiguity', 'when', 'below'),
    'prompt', 'Front-load explicit structure: written scope, weekly milestones, named owner for each decision.',
    'citation', 'DEV STUB — replace with licensed framework reference.'
  ), 'dev_stub', true, 'HeiTobias (DEV STUB)'),
(null, 'prompt_high_collaboration_drive', 'manager_prompt',
  'DEV STUB · High collaboration drive — channel into mentorship',
  jsonb_build_object(
    'trigger', jsonb_build_object('trait', 'collaboration_drive', 'when', 'above'),
    'prompt', 'Channel collaborative energy into mentorship of a junior or a cross-team integration project.',
    'citation', 'DEV STUB — replace.'
  ), 'dev_stub', true, 'HeiTobias (DEV STUB)');

-- ---- kickstart_generate(person_id) ----
-- Reads the person's role + profile (gated by ongoing_management consent),
-- pulls every milestone_template + applicable manager_prompt from frameworks,
-- assembles a plan_json where EVERY milestone cites a framework_id.
-- Idempotent only by re-running — each call inserts a new plan row.
create or replace function public.kickstart_generate(
  p_person_id uuid,
  p_org_id    uuid
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller    uuid := (select auth.uid());
  v_actor_id  uuid;
  v_ongoing   uuid;
  v_role      public.roles_catalog%rowtype;
  v_plan_id   uuid;
  v_milestones jsonb := '[]'::jsonb;
  v_used      uuid[] := '{}';
  v_tpl       record;
  v_prompt    record;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'kickstart_generate: caller lacks org.manage_all in org';
  end if;

  -- Active ongoing_management consent required (Phase 2 §3 purpose ladder).
  select id into v_ongoing
    from public.consent_grants
    where person_id = p_person_id and granted_to_org_id = p_org_id
      and purpose = 'ongoing_management' and status = 'active'
      and revoked_at is null and (expires_at is null or expires_at > now())
    limit 1;
  if v_ongoing is null then
    raise exception 'kickstart_generate: no active ongoing_management consent for (person, org). Capture via placement_activate first.';
  end if;

  -- Find a role to anchor the plan against (most-recent position).
  select rc.* into v_role
    from public.positions pos
    join public.roles_catalog rc on rc.id = pos.role_id
    where pos.person_id = p_person_id and pos.org_id = p_org_id
    order by pos.start_date desc nulls last
    limit 1;

  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  -- Assemble milestones from every milestone_template framework.
  for v_tpl in
    select id, key, body_json from public.frameworks
    where kind = 'milestone_template' and (org_id is null or org_id = p_org_id)
    order by (body_json->>'day_offset')::int
  loop
    v_milestones := v_milestones || jsonb_build_array(jsonb_build_object(
      'framework_id',  v_tpl.id,
      'framework_key', v_tpl.key,
      'day_offset',    v_tpl.body_json->>'day_offset',
      'title',         v_tpl.body_json->>'title',
      'narrative',     v_tpl.body_json->>'narrative',
      'manager_prompts', v_tpl.body_json->'manager_prompts',
      '_dev_stub',     true,
      'grounded',      true
    ));
    v_used := array_append(v_used, v_tpl.id);
  end loop;

  -- Pull any trait-tailored manager_prompts that match the role's trait targets.
  -- DEV-STUB tailoring: we just include all prompts and mark which trait
  -- they're conditioned on so the manager view can show grounding chips.
  declare v_tailored jsonb := '[]'::jsonb;
  begin
    for v_prompt in
      select id, key, body_json from public.frameworks
      where kind = 'manager_prompt' and (org_id is null or org_id = p_org_id)
    loop
      v_tailored := v_tailored || jsonb_build_array(jsonb_build_object(
        'framework_id',  v_prompt.id,
        'framework_key', v_prompt.key,
        'trigger',       v_prompt.body_json->'trigger',
        'prompt',        v_prompt.body_json->>'prompt',
        'citation',      v_prompt.body_json->>'citation',
        '_dev_stub',     true,
        'grounded',      true
      ));
      v_used := array_append(v_used, v_prompt.id);
    end loop;

    insert into public.kickstart_plans (
      org_id, person_id, role_id, ongoing_consent_id,
      plan_json, frameworks_used, validity_status, _dev_stub,
      generated_by, generated_at
    ) values (
      p_org_id, p_person_id, v_role.id, v_ongoing,
      jsonb_build_object(
        'milestones',         v_milestones,
        'tailored_prompts',   v_tailored,
        'role_title',         coalesce(v_role.title, '(no role)'),
        'role_id',            v_role.id,
        '_dev_stub',          true,
        '_grounded',          true,
        '_generator',         'kickstart_generate_v0'
      ),
      v_used, 'dev_stub', true, v_actor_id, now()
    )
    returning id into v_plan_id;
  end;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor_id, 'kickstart.generated', 'kickstart_plans', v_plan_id,
      jsonb_build_object('person_id', p_person_id, 'frameworks_used', array_length(v_used,1),
                          'ongoing_consent_id', v_ongoing));

  return v_plan_id;
end;
$$;
revoke execute on function public.kickstart_generate(uuid, uuid) from public;
grant  execute on function public.kickstart_generate(uuid, uuid) to authenticated, service_role;
comment on function public.kickstart_generate(uuid, uuid) is
  'Generates a DEV-STUB 90-day kickstart plan for a person in an employer org. Requires active ongoing_management consent. Every milestone + tailored prompt cites a framework_id (grounded, not freeform). Plan row carries validity_status=dev_stub and _dev_stub=true.';
