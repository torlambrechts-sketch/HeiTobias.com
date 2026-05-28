-- science_spec_functions — RPC bodies for SCIENCE-SPEC enforcement.
-- Split from the structural migration because adding a new enum value
-- (consent_purpose 'fairness_monitoring') can't be used in the same
-- transaction as code that references it on some Postgres versions.

-- guidance_compose v1: refusal-aware. Refused queries write a STRUCTURED
-- refusal row that cites the refusal_policy_v0 framework so the audit
-- trail stays grounded (no silent skips).
create or replace function public.guidance_compose(
  p_person_id    uuid,
  p_org_id       uuid,
  p_kind         public.guidance_kind,
  p_context_json jsonb default '{}'::jsonb
)
returns uuid
language plpgsql set search_path = '' security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor_id uuid; v_consent_id uuid;
  v_framework_ids uuid[]; v_framework_kind text;
  v_outputs jsonb := '[]'::jsonb; v_fw record; v_id uuid;
  v_refusal public.guidance_refusal_kind;
  v_refusal_framework_id uuid; v_refusal_body jsonb;
begin
  if v_caller is not null and not public.has_permission(p_org_id,'guidance.generate') then
    raise exception 'guidance_compose: caller lacks guidance.generate in org';
  end if;
  select id into v_consent_id from public.consent_grants
    where person_id = p_person_id and granted_to_org_id = p_org_id
      and purpose = 'ongoing_management' and status = 'active'
      and revoked_at is null and (expires_at is null or expires_at > now()) limit 1;
  if v_consent_id is null then raise exception 'guidance_compose: no active ongoing_management consent'; end if;
  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  -- SCIENCE-SPEC §6: refusal categories. Short-circuit + STILL cite the
  -- refusal policy framework (grounded audit trail).
  v_refusal := public._infer_guidance_refusal(p_context_json);
  if v_refusal is not null then
    select id, body_json into v_refusal_framework_id, v_refusal_body
      from public.frameworks
      where kind = 'manager_prompt' and key = 'refusal_policy_v0' limit 1;
    if v_refusal_framework_id is null then
      raise exception 'guidance_compose: refusal policy framework missing — cannot refuse without grounding';
    end if;
    insert into public.guidance_items (
      org_id, person_id, consent_id, kind, framework_ids,
      inputs_json, output_json,
      refusal_kind, validity_status, _dev_stub, generated_by, generated_at
    ) values (
      p_org_id, p_person_id, v_consent_id, p_kind, array[v_refusal_framework_id],
      jsonb_build_object('context', coalesce(p_context_json,'{}'::jsonb), 'kind', p_kind,
                         '_generator','guidance_compose_v1','_refused', true),
      jsonb_build_object(
        'refused',     true,
        'refusal_kind', v_refusal,
        'redirect',    v_refusal_body->>(v_refusal::text),
        'citation',    v_refusal_body->>'citation',
        '_dev_stub',   true,
        '_grounded',   true,
        '_generator',  'guidance_compose_v1'
      ),
      v_refusal, 'dev_stub', true, v_actor_id, now()
    )
    returning id into v_id;
    insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
      values (p_org_id, v_actor_id, 'guidance.refused', 'guidance_items', v_id,
        jsonb_build_object('person_id', p_person_id, 'refusal_kind', v_refusal));
    return v_id;
  end if;

  -- Normal grounded composition.
  v_framework_kind := case p_kind
    when 'one_on_one_prep'  then 'manager_prompt'
    when 'growth_focus'     then 'manager_prompt'
    when 'check_in_design'  then 'check_in_template'
    when 'team_gap_callout' then 'manager_prompt'
  end;
  for v_fw in
    select id, key, body_json from public.frameworks
    where kind = v_framework_kind and (org_id is null or org_id = p_org_id)
      and key <> 'refusal_policy_v0'
  loop
    v_framework_ids := array_append(v_framework_ids, v_fw.id);
    v_outputs := v_outputs || jsonb_build_array(jsonb_build_object(
      'framework_id',  v_fw.id, 'framework_key', v_fw.key,
      'prompt',        v_fw.body_json->>'prompt',
      'citation',      v_fw.body_json->>'citation',
      'trigger',       v_fw.body_json->'trigger',
      'manager_prompts', v_fw.body_json->'manager_prompts',
      '_dev_stub',     true, 'grounded', true));
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
    jsonb_build_object('context', coalesce(p_context_json,'{}'::jsonb), 'kind', p_kind, '_generator','guidance_compose_v1'),
    jsonb_build_object('items', v_outputs, '_dev_stub', true, '_grounded', true,
                       'frameworks_count', array_length(v_framework_ids, 1)),
    'dev_stub', true, v_actor_id, now()
  )
  returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor_id, 'guidance.composed', 'guidance_items', v_id,
      jsonb_build_object('person_id', p_person_id, 'kind', p_kind, 'frameworks_count', array_length(v_framework_ids, 1)));
  return v_id;
end;
$$;
revoke execute on function public.guidance_compose(uuid, uuid, public.guidance_kind, jsonb) from public;
grant  execute on function public.guidance_compose(uuid, uuid, public.guidance_kind, jsonb) to authenticated, service_role;

-- lifecycle_decision_record — same INFORMING-not-DECIDING discipline as
-- Phase 1's hiring_decision_record, but for post-hire actions. Rationale
-- REQUIRED. AuthZ: org.manage_all. Audited as 'lifecycle.decision'.
create or replace function public.lifecycle_decision_record(
  p_person_id               uuid,
  p_org_id                  uuid,
  p_kind                    public.lifecycle_decision_kind,
  p_rationale               text,
  p_overrode_recommendation boolean default false,
  p_recommendation_summary  text default null,
  p_refit_evaluation_id     uuid default null,
  p_guidance_item_id        uuid default null
)
returns uuid
language plpgsql set search_path = '' security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor_id uuid; v_consent_id uuid; v_id uuid;
begin
  if p_rationale is null or length(btrim(p_rationale)) = 0 then
    raise exception 'lifecycle_decision_record: rationale is required (text, non-empty)';
  end if;
  if v_caller is not null and not public.has_permission(p_org_id,'org.manage_all') then
    raise exception 'lifecycle_decision_record: caller lacks org.manage_all in org';
  end if;
  select id into v_consent_id from public.consent_grants
    where person_id = p_person_id and granted_to_org_id = p_org_id
      and purpose = 'ongoing_management' and status = 'active'
      and revoked_at is null and (expires_at is null or expires_at > now()) limit 1;
  if v_consent_id is null then
    raise exception 'lifecycle_decision_record: requires active ongoing_management consent';
  end if;
  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;
  if v_actor_id is null then
    raise exception 'lifecycle_decision_record: caller has no people row';
  end if;
  insert into public.lifecycle_decisions (
    org_id, person_id, consent_id, kind, rationale,
    overrode_recommendation, recommendation_summary,
    refit_evaluation_id, guidance_item_id,
    decided_by, decided_at
  ) values (
    p_org_id, p_person_id, v_consent_id, p_kind, p_rationale,
    coalesce(p_overrode_recommendation, false), p_recommendation_summary,
    p_refit_evaluation_id, p_guidance_item_id,
    v_actor_id, now()
  )
  returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor_id, 'lifecycle.decision', 'lifecycle_decisions', v_id,
      jsonb_build_object(
        'person_id', p_person_id, 'kind', p_kind, 'rationale', p_rationale,
        'overrode_recommendation', coalesce(p_overrode_recommendation, false),
        'refit_evaluation_id', p_refit_evaluation_id,
        'guidance_item_id', p_guidance_item_id
      ));
  return v_id;
end;
$$;
revoke execute on function public.lifecycle_decision_record(uuid, uuid, public.lifecycle_decision_kind, text, boolean, text, uuid, uuid) from public;
grant  execute on function public.lifecycle_decision_record(uuid, uuid, public.lifecycle_decision_kind, text, boolean, text, uuid, uuid) to authenticated, service_role;
comment on function public.lifecycle_decision_record(uuid, uuid, public.lifecycle_decision_kind, text, boolean, text, uuid, uuid) is
  'Records a human decision on a post-hire lifecycle action. Rationale REQUIRED. AuthZ: org.manage_all. SCIENCE-SPEC §5.';
