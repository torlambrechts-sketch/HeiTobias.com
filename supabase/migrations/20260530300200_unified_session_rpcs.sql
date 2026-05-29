-- Unified-session RPCs: init, state, submit_item, submit_prep, mark_section.
-- All are SECDEF + search_path='' and anon-callable (the token is the auth).

create or replace function public.assessment_session_init(p_token text, p_demo boolean default false)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_invite public.assessment_invites%rowtype;
  v_session_id uuid;
  v_sections jsonb;
begin
  select * into v_invite from public.assessment_invites where token = p_token;
  if not found then raise exception 'assessment_session_init: token not found'; end if;
  select id into v_session_id from public.assessment_sessions where invite_token = p_token;
  if v_session_id is not null then return v_session_id; end if;
  v_sections := jsonb_build_object(
    'personality',     jsonb_build_object('complete', false, 'total_items', case when p_demo then 5 else 12 end, 'answered_items', 0, '_dev_stub', true),
    'cognitive',       jsonb_build_object('complete', false, 'total_items', case when p_demo then 10 else 25 end, 'answered_items', 0, '_dev_stub', true),
    'values',          jsonb_build_object('complete', false, 'total_items', case when p_demo then 8 else 24 end, 'answered_items', 0, '_dev_stub', true),
    'structured_prep', jsonb_build_object('complete', false, 'total_items', case when p_demo then 2 else null end, 'answered_items', 0, '_dev_stub', true)
  );
  insert into public.assessment_sessions (invite_id, invite_token, org_id, person_id, demo_mode, status, sections_json, is_demo_data)
  values (v_invite.id, p_token, v_invite.org_id, v_invite.person_id, p_demo, 'in_progress', v_sections,
          coalesce((select is_demo_data from public.organizations where id = v_invite.org_id), false))
  returning id into v_session_id;
  return v_session_id;
end;
$$;
revoke execute on function public.assessment_session_init(text, boolean) from public;
grant  execute on function public.assessment_session_init(text, boolean) to authenticated, anon, service_role;

create or replace function public.assessment_session_state(p_token text)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_session   public.assessment_sessions%rowtype;
  v_invite    public.assessment_invites%rowtype;
  v_cog_inst  uuid;
  v_val_inst  uuid;
  v_cog_items jsonb;
  v_val_items jsonb;
  v_role_id   uuid;
  v_competencies jsonb;
  v_prep_rows  jsonb;
  v_prep_total int;
begin
  select * into v_session from public.assessment_sessions where invite_token = p_token;
  if not found then return jsonb_build_object('error', 'session not initialised'); end if;
  select * into v_invite from public.assessment_invites where id = v_session.invite_id;

  select id into v_cog_inst from public.assessment_instruments where key = 'sample_cognitive_v0' limit 1;
  with limited_items as (
    select i.id, i.key, i.prompt, i.item_type, i.item_json, i._dev_stub,
           exists (select 1 from public.assessment_responses r where r.item_id = i.id and r.person_id = v_session.person_id) as answered
    from public.assessment_items i where i.instrument_id = v_cog_inst
    order by i.key
    limit (case when v_session.demo_mode then 10 else 25 end)
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'key', key, 'prompt', prompt, 'item_json', item_json, '_dev_stub', _dev_stub, 'answered', answered)), '[]'::jsonb)
    into v_cog_items from limited_items;

  select id into v_val_inst from public.assessment_instruments where key = 'sample_values_v0' limit 1;
  with limited_items as (
    select i.id, i.key, i.prompt, i.item_type, i.item_json, i._dev_stub,
           exists (select 1 from public.assessment_responses r where r.item_id = i.id and r.person_id = v_session.person_id) as answered
    from public.assessment_items i where i.instrument_id = v_val_inst
    order by i.key
    limit (case when v_session.demo_mode then 8 else 24 end)
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'key', key, 'prompt', prompt, 'item_json', item_json, '_dev_stub', _dev_stub, 'answered', answered)), '[]'::jsonb)
    into v_val_items from limited_items;

  select req.role_id into v_role_id from public.requisition_candidates rc
    join public.requisitions req on req.id = rc.requisition_id
    where rc.person_id = v_session.person_id and rc.org_id = v_session.org_id
    order by rc.created_at desc limit 1;
  if v_role_id is not null then
    select definition_json -> 'competencies' into v_competencies from public.roles_catalog where id = v_role_id;
  end if;
  if v_competencies is null or jsonb_typeof(v_competencies) <> 'array' then
    v_competencies := jsonb_build_array(
      jsonb_build_object('key','analyzing','label','Analyzing and interpreting'),
      jsonb_build_object('key','collaborating','label','Collaborating and influencing'),
      jsonb_build_object('key','adapting','label','Adapting and responding to change'),
      jsonb_build_object('key','delivering','label','Delivering results'),
      jsonb_build_object('key','leading','label','Leading and supporting others')
    );
  end if;
  v_prep_total := case when v_session.demo_mode then 2 else jsonb_array_length(v_competencies) end;
  with comps as (
    select cv.value as comp, row_number() over () as rn from jsonb_array_elements(v_competencies) cv
  ), limited as (
    select comp from comps where rn <= v_prep_total
  ), enriched as (
    select c.comp,
           coalesce(p.response_text, '') as response_text,
           p.answered_at is not null as answered
    from limited c
    left join public.assessment_prep_responses p on p.session_id = v_session.id
                                                 and p.competency_key = (c.comp->>'key')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', (comp->>'key'),
    'label', coalesce(comp->>'label', comp->>'key'),
    'prompt_text',
      'Describe a time you demonstrated ' || coalesce(comp->>'label', comp->>'key') || '. ' ||
      'What was the SITUATION? What was your TASK? What ACTIONS did you take? What was the RESULT? (~200-400 chars)',
    'response_text', response_text,
    'answered', answered
  )), '[]'::jsonb)
  into v_prep_rows from enriched;

  return jsonb_build_object(
    'session_id', v_session.id,
    'invite_token', p_token,
    'demo_mode', v_session.demo_mode,
    'status', v_session.status::text,
    'org_id', v_session.org_id,
    'person_id', v_session.person_id,
    'consent_captured', v_invite.consent_recorded_id is not null,
    'expires_at', v_invite.expires_at,
    'sections', jsonb_build_object(
      'cognitive', jsonb_build_object(
        'items', v_cog_items,
        'total', jsonb_array_length(v_cog_items),
        'answered', (select count(*) from jsonb_array_elements(v_cog_items) x where (x->>'answered')::boolean),
        '_dev_stub', true, 'validity_status', 'dev_stub'
      ),
      'values', jsonb_build_object(
        'items', v_val_items,
        'total', jsonb_array_length(v_val_items),
        'answered', (select count(*) from jsonb_array_elements(v_val_items) x where (x->>'answered')::boolean),
        '_dev_stub', true, 'validity_status', 'dev_stub'
      ),
      'structured_prep', jsonb_build_object(
        'items', v_prep_rows,
        'total', jsonb_array_length(v_prep_rows),
        'answered', (select count(*) from jsonb_array_elements(v_prep_rows) x where (x->>'answered')::boolean),
        '_dev_stub', true,
        'methodology_note', 'These responses inform the live structured interview your recruiter will conduct. Structured interview is the top single predictor of job performance in the Sackett et al. 2022 revised validity hierarchy (ρ≈.42). We front-load this rather than burying it.'
      )
    ),
    'started_at', v_session.started_at,
    'completed_at', v_session.completed_at
  );
end;
$$;
revoke execute on function public.assessment_session_state(text) from public;
grant  execute on function public.assessment_session_state(text) to authenticated, anon, service_role;

create or replace function public.assessment_session_submit_item(
  p_token text, p_item_id uuid, p_value int
)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_session public.assessment_sessions%rowtype;
  v_invite  public.assessment_invites%rowtype;
  v_assessment_id uuid;
begin
  select * into v_session from public.assessment_sessions where invite_token = p_token;
  if not found then raise exception 'assessment_session_submit_item: session not found'; end if;
  select * into v_invite from public.assessment_invites where id = v_session.invite_id;
  if v_invite.consent_recorded_id is null then
    raise exception 'assessment_session_submit_item: consent not captured';
  end if;
  v_assessment_id := v_invite.assessment_id;
  insert into public.assessment_responses (org_id, assessment_id, item_id, person_id, consent_id, response_json)
  values (v_session.org_id, v_assessment_id, p_item_id, v_session.person_id, v_invite.consent_recorded_id,
          jsonb_build_object('value', p_value))
  on conflict do nothing;
  update public.assessment_sessions set updated_at = now() where id = v_session.id;
  return jsonb_build_object('item_id', p_item_id, 'value', p_value);
end;
$$;
revoke execute on function public.assessment_session_submit_item(text, uuid, int) from public;
grant  execute on function public.assessment_session_submit_item(text, uuid, int) to authenticated, anon, service_role;

create or replace function public.assessment_session_submit_prep(
  p_token text, p_competency_key text, p_response_text text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_session  public.assessment_sessions%rowtype;
  v_invite   public.assessment_invites%rowtype;
  v_role_id  uuid;
  v_comp     jsonb;
  v_id       uuid;
begin
  select * into v_session from public.assessment_sessions where invite_token = p_token;
  if not found then raise exception 'assessment_session_submit_prep: session not found'; end if;
  select * into v_invite from public.assessment_invites where id = v_session.invite_id;
  if v_invite.consent_recorded_id is null then
    raise exception 'assessment_session_submit_prep: consent not captured';
  end if;
  select req.role_id into v_role_id from public.requisition_candidates rc
    join public.requisitions req on req.id = rc.requisition_id
    where rc.person_id = v_session.person_id and rc.org_id = v_session.org_id
    order by rc.created_at desc limit 1;
  if v_role_id is not null then
    select cv.value into v_comp
    from public.roles_catalog rc
    cross join lateral jsonb_array_elements(coalesce(rc.definition_json -> 'competencies', '[]'::jsonb)) cv
    where rc.id = v_role_id and cv.value ->> 'key' = p_competency_key
    limit 1;
  end if;
  insert into public.assessment_prep_responses (session_id, competency_key, competency_label, prompt_text, response_text, answered_at)
  values (v_session.id, p_competency_key, coalesce(v_comp ->> 'label', p_competency_key),
          'STAR prompt for ' || p_competency_key, p_response_text, now())
  on conflict (session_id, competency_key) do update set
    response_text = excluded.response_text, answered_at = now(), updated_at = now()
  returning id into v_id;
  update public.assessment_sessions set updated_at = now() where id = v_session.id;
  return v_id;
end;
$$;
revoke execute on function public.assessment_session_submit_prep(text, text, text) from public;
grant  execute on function public.assessment_session_submit_prep(text, text, text) to authenticated, anon, service_role;

create or replace function public.assessment_session_mark_section(p_token text, p_section text)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_session public.assessment_sessions%rowtype;
  v_sections jsonb;
  v_all_done boolean;
begin
  select * into v_session from public.assessment_sessions where invite_token = p_token;
  if not found then raise exception 'assessment_session_mark_section: session not found'; end if;
  if p_section not in ('personality','cognitive','values','structured_prep') then
    raise exception 'assessment_session_mark_section: unknown section %', p_section;
  end if;
  v_sections := v_session.sections_json;
  v_sections := jsonb_set(v_sections, array[p_section, 'complete'], to_jsonb(true));
  v_sections := jsonb_set(v_sections, array[p_section, 'completed_at'], to_jsonb(now()::text));
  v_all_done := (v_sections -> 'personality' ->> 'complete')::boolean
            and (v_sections -> 'cognitive' ->> 'complete')::boolean
            and (v_sections -> 'values' ->> 'complete')::boolean
            and (v_sections -> 'structured_prep' ->> 'complete')::boolean;
  update public.assessment_sessions set
    sections_json = v_sections,
    status = case when v_all_done then 'completed' else status end,
    completed_at = case when v_all_done then now() else completed_at end,
    updated_at = now()
  where id = v_session.id;
  if v_all_done then
    update public.assessments set status = 'completed', completed_at = now()
      where person_id = v_session.person_id and status <> 'completed';
    insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
      values (v_session.org_id, v_session.person_id, 'assessment.session_completed',
              'assessment_sessions', v_session.id,
              jsonb_build_object('demo_mode', v_session.demo_mode, 'completed_at', now()));
  end if;
  return jsonb_build_object('section', p_section, 'all_done', v_all_done);
end;
$$;
revoke execute on function public.assessment_session_mark_section(text, text) from public;
grant  execute on function public.assessment_session_mark_section(text, text) to authenticated, anon, service_role;
