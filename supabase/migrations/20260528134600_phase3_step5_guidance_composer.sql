-- phase3_step5_guidance_composer — grounded manager guidance.
--
-- Every guidance_items row carries framework_ids[] — enforced by the
-- CHECK constraint added in Step 1. This RPC builds the row from a
-- retrieval over public.frameworks filtered by kind + context, then
-- assembles output_json that explicitly cites each framework. Never
-- freeform output about a named person.

create or replace function public.guidance_compose(
  p_person_id    uuid,
  p_org_id       uuid,
  p_kind         public.guidance_kind,
  p_context_json jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller     uuid := (select auth.uid());
  v_actor_id   uuid;
  v_consent_id uuid;
  v_framework_ids uuid[];
  v_framework_kind text;
  v_outputs    jsonb := '[]'::jsonb;
  v_fw         record;
  v_id         uuid;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'guidance.generate') then
    raise exception 'guidance_compose: caller lacks guidance.generate in org';
  end if;

  select id into v_consent_id from public.consent_grants
    where person_id = p_person_id and granted_to_org_id = p_org_id
      and purpose = 'ongoing_management' and status = 'active'
      and revoked_at is null and (expires_at is null or expires_at > now()) limit 1;
  if v_consent_id is null then
    raise exception 'guidance_compose: no active ongoing_management consent';
  end if;

  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  -- Map guidance_kind → framework kind to retrieve.
  v_framework_kind := case p_kind
    when 'one_on_one_prep'    then 'manager_prompt'
    when 'growth_focus'       then 'manager_prompt'
    when 'check_in_design'    then 'check_in_template'
    when 'team_gap_callout'   then 'manager_prompt'
  end;

  -- DEV-STUB retrieval: pull all frameworks of the matching kind that are
  -- either global or in this org. Phase 4 replaces this with a real
  -- retrieval ranked by relevance to the person's signals + role + re-fit
  -- quadrant carried in p_context_json.
  for v_fw in
    select id, key, body_json from public.frameworks
    where kind = v_framework_kind
      and (org_id is null or org_id = p_org_id)
  loop
    v_framework_ids := array_append(v_framework_ids, v_fw.id);
    v_outputs := v_outputs || jsonb_build_array(jsonb_build_object(
      'framework_id',  v_fw.id,
      'framework_key', v_fw.key,
      'prompt',        v_fw.body_json->>'prompt',
      'citation',      v_fw.body_json->>'citation',
      'trigger',       v_fw.body_json->'trigger',
      'manager_prompts', v_fw.body_json->'manager_prompts',
      '_dev_stub',     true,
      'grounded',      true
    ));
  end loop;

  if array_length(v_framework_ids, 1) is null or array_length(v_framework_ids, 1) = 0 then
    raise exception 'guidance_compose: no frameworks of kind % available (cannot generate ungrounded guidance)', v_framework_kind;
  end if;

  insert into public.guidance_items (
    org_id, person_id, consent_id, kind, framework_ids,
    inputs_json, output_json,
    validity_status, _dev_stub, generated_by, generated_at
  ) values (
    p_org_id, p_person_id, v_consent_id, p_kind, v_framework_ids,
    jsonb_build_object('context', coalesce(p_context_json,'{}'::jsonb), 'kind', p_kind, '_generator', 'guidance_compose_v0'),
    jsonb_build_object('items', v_outputs, '_dev_stub', true, '_grounded', true,
                       'frameworks_count', array_length(v_framework_ids, 1)),
    'dev_stub', true, v_actor_id, now()
  )
  returning id into v_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor_id, 'guidance.composed', 'guidance_items', v_id,
      jsonb_build_object('person_id', p_person_id, 'kind', p_kind,
                          'frameworks_count', array_length(v_framework_ids, 1)));

  return v_id;
end;
$$;
revoke execute on function public.guidance_compose(uuid, uuid, public.guidance_kind, jsonb) from public;
grant  execute on function public.guidance_compose(uuid, uuid, public.guidance_kind, jsonb) to authenticated, service_role;
comment on function public.guidance_compose(uuid, uuid, public.guidance_kind, jsonb) is
  'Generates a grounded guidance row by retrieving frameworks of the matching kind. EVERY output item cites a framework_id. Fails if no frameworks are available — refuses to emit ungrounded guidance.';

-- ---- guidance_record_action(item_id, action, notes) ----
-- Manager records what they did with the guidance. The output cannot
-- be mutated — only the action label + notes.
create or replace function public.guidance_record_action(
  p_item_id uuid,
  p_action  public.guidance_action,
  p_notes   text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller   uuid := (select auth.uid());
  v_actor_id uuid;
  v_item     public.guidance_items%rowtype;
begin
  select * into v_item from public.guidance_items where id = p_item_id;
  if not found then raise exception 'guidance_record_action: item not found'; end if;
  if v_caller is not null and not public.has_permission(v_item.org_id, 'guidance.read') then
    raise exception 'guidance_record_action: caller lacks guidance.read';
  end if;
  if not public.consent_active(v_item.consent_id, 'ongoing_management') then
    raise exception 'guidance_record_action: ongoing_management consent inactive';
  end if;
  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  update public.guidance_items
    set action = p_action, action_at = now(), action_notes = p_notes, updated_at = now()
    where id = p_item_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (v_item.org_id, v_actor_id, 'guidance.action_recorded', 'guidance_items', p_item_id,
      jsonb_build_object('action', v_item.action),
      jsonb_build_object('action', p_action, 'notes', p_notes));

  return p_item_id;
end;
$$;
revoke execute on function public.guidance_record_action(uuid, public.guidance_action, text) from public;
grant  execute on function public.guidance_record_action(uuid, public.guidance_action, text) to authenticated, service_role;
