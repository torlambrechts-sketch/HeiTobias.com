-- ITEM 3: module availability tri-state + toggle RPC.
-- See migration body for the discipline; mirrors what was applied.

create type public.module_availability as enum
  ('available', 'requires_part2', 'requires_expert_signoff');

alter table public.modules add column availability public.module_availability not null default 'available';
alter table public.modules add column availability_note text;

update public.modules set availability = 'available' where key in
  ('role_architecture','team_definition','assessment_engine','fit_scoring','lifecycle','candidate_experience');

insert into public.modules (key, name, availability, availability_note) values
  ('role_library',       'Role Library',                  'available',
     'The signed-off-role catalogue + version history.'),
  ('refit_engine',       'Re-fit Engine',                 'available',
     'Quarterly trait/role re-evaluation; emits flight-risk + growth-gap signals.'),
  ('guidance_composer',  'Guidance Composer',             'available',
     'Grounded LLM helper for 1:1 prep — Frameworks Library + structured data only.'),
  ('requisitions',       'Requisitions Lifecycle',        'requires_part2',
     'Coming in Operations Layer Part 2 — requisition creation, candidate pipeline, placement.'),
  ('manager_workspace',  'Manager Workspace',             'requires_part2',
     'Coming in Operations Layer Part 2 — team list, person detail, developmental 1:1 prep.'),
  ('modeling_admin',     'Modeling Admin',                'requires_expert_signoff',
     'Requires modeling.signoff GRANT (HANDOFF H-8). Pareto + model cards + AI Act Annex IV.'),
  ('fairness_audit',     'Fairness Audit',                'requires_expert_signoff',
     'Requires I/O-psych + legal verdict (HANDOFF H-3). Per-group disparate-impact monitoring.')
on conflict (key) do update set
  availability = excluded.availability,
  availability_note = excluded.availability_note;

update public.modules set availability = 'requires_part2',
  availability_note = 'Coming in Operations Layer Part 2 — candidate /take/<token> flow.'
  where key = 'candidate_experience';

create or replace function public._check_org_modules_availability()
returns trigger language plpgsql set search_path = '' as $$
declare v_avail public.module_availability;
begin
  if NEW.enabled then
    select availability into v_avail from public.modules where key = NEW.module_key;
    if v_avail is null then raise exception 'org_modules: unknown module_key %', NEW.module_key; end if;
    if v_avail <> 'available' then
      raise exception 'org_modules: cannot enable % — availability=%', NEW.module_key, v_avail;
    end if;
  end if;
  return NEW;
end;
$$;
drop trigger if exists trg_check_org_modules_availability on public.org_modules;
create trigger trg_check_org_modules_availability
  before insert or update on public.org_modules
  for each row execute function public._check_org_modules_availability();

create or replace function public.org_module_set_enabled(
  p_org_id uuid,
  p_module_key text,
  p_enabled boolean,
  p_rationale text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_id     uuid;
  v_old    boolean;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'org_module_set_enabled: rationale >=20 chars required';
  end if;
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'org_module_set_enabled: requires org.manage_all';
  end if;
  select id, enabled into v_id, v_old from public.org_modules where org_id = p_org_id and module_key = p_module_key;
  if v_id is null then
    insert into public.org_modules (org_id, module_key, enabled) values (p_org_id, p_module_key, p_enabled)
      returning id into v_id;
  else
    update public.org_modules set enabled = p_enabled, updated_at = now() where id = v_id;
  end if;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (p_org_id, v_actor, 'org.module_toggled', 'org_modules', v_id,
      jsonb_build_object('was_enabled', v_old),
      jsonb_build_object('module_key', p_module_key, 'enabled', p_enabled, 'rationale_excerpt', left(p_rationale, 200)));
  insert into public.admin_decisions (org_id, kind, decided_by, rationale, target_entity_type, target_entity_id, overrode_recommendation)
    values (p_org_id, 'module_toggle', v_actor, p_rationale, 'org_modules', v_id, true);
  return v_id;
end;
$$;
revoke execute on function public.org_module_set_enabled(uuid, text, boolean, text) from public;
grant  execute on function public.org_module_set_enabled(uuid, text, boolean, text) to authenticated, service_role;

create or replace function public.org_modules_state(p_org_id uuid)
returns table (
  module_key text,
  module_name text,
  availability public.module_availability,
  availability_note text,
  enabled boolean,
  last_toggled_at timestamptz
) language plpgsql set search_path = '' security definer as $$
begin
  if (select auth.uid()) is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'org_modules_state: requires org.manage_all';
  end if;
  return query
    select m.key, m.name, m.availability, m.availability_note,
           coalesce(om.enabled, false) as enabled,
           om.updated_at
    from public.modules m
    left join public.org_modules om on om.org_id = p_org_id and om.module_key = m.key
    order by m.key;
end;
$$;
revoke execute on function public.org_modules_state(uuid) from public;
grant  execute on function public.org_modules_state(uuid) to authenticated, service_role;
