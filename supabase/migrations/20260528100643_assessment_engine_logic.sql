-- assessment_engine_logic — Phase 1 Step 4.
--
-- Brings the candidate pipeline alive on top of the Step 1 tables:
--   assessment_invite_create   — recruiter creates assessment+invite, returns token
--   assessment_capture_consent — anon (token-gated) records consent_grants row,
--                                wires it onto the invite, advances assessment
--                                to 'in_progress'
--   assessment_submit_response — anon (token-gated) writes a response, gated
--                                by consent being already captured
--   assessment_run_scoring     — recruiter triggers DEV-STUB scoring; one
--                                assessment_scores row per scale in the
--                                instrument's body_json.scales[]
--
-- All RPCs are SECURITY DEFINER with locked search_path. The token is just
-- a UUID string; entropy is sufficient. The invite IS the bearer credential.

-- ---------------- assessment_invite_create ------------------------------
create or replace function public.assessment_invite_create(
  p_org_id          uuid,
  p_person_id       uuid,
  p_instrument_key  text,
  p_assessment_type public.assessment_type default 'personality',
  p_expires_in_days int default 14
)
returns jsonb
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller        uuid := (select auth.uid());
  v_actor_id      uuid;
  v_assessment_id uuid;
  v_invite_id     uuid;
  v_token         text;
begin
  if v_caller is not null then
    if not public.has_permission(p_org_id, 'assessment.invite') then
      raise exception 'assessment_invite_create: caller lacks assessment.invite';
    end if;
  end if;

  if not exists (
    select 1 from public.assessment_instruments
    where key = p_instrument_key and (org_id is null or org_id = p_org_id)
  ) then
    raise exception 'assessment_invite_create: unknown instrument %', p_instrument_key;
  end if;

  if p_expires_in_days <= 0 then
    raise exception 'assessment_invite_create: expires_in_days must be > 0';
  end if;

  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  insert into public.assessments (org_id, person_id, instrument_key, type, status)
    values (p_org_id, p_person_id, p_instrument_key, p_assessment_type, 'invited')
    returning id into v_assessment_id;

  v_token := extensions.gen_random_uuid()::text;

  insert into public.assessment_invites (
    org_id, assessment_id, person_id, token, expires_at, created_by
  ) values (
    p_org_id, v_assessment_id, p_person_id, v_token,
    now() + (p_expires_in_days || ' days')::interval,
    v_actor_id
  )
  returning id into v_invite_id;

  return jsonb_build_object(
    'invite_id',     v_invite_id,
    'assessment_id', v_assessment_id,
    'token',         v_token
  );
end;
$$;

revoke execute on function public.assessment_invite_create(uuid, uuid, text, public.assessment_type, int) from public;
grant  execute on function public.assessment_invite_create(uuid, uuid, text, public.assessment_type, int) to authenticated, service_role;
comment on function public.assessment_invite_create(uuid, uuid, text, public.assessment_type, int) is
  'Creates assessment + invite + token. AuthZ: assessment.invite in org. Returns {invite_id, assessment_id, token}.';

-- ---------------- assessment_capture_consent ----------------------------
-- Anon-callable: the candidate (not yet authenticated) accepts consent via
-- their invite token. Idempotent: if consent already recorded, returns it.
create or replace function public.assessment_capture_consent(
  p_token text
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_invite     public.assessment_invites%rowtype;
  v_consent_id uuid;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'assessment_capture_consent: token required';
  end if;

  select * into v_invite from public.assessment_invites where token = p_token;
  if not found then
    raise exception 'assessment_capture_consent: invalid token';
  end if;
  if v_invite.used_at is not null then
    raise exception 'assessment_capture_consent: invite already used';
  end if;
  if v_invite.expires_at <= now() then
    raise exception 'assessment_capture_consent: invite expired';
  end if;

  -- Idempotent
  if v_invite.consent_recorded_id is not null then
    return v_invite.consent_recorded_id;
  end if;

  insert into public.consent_grants (
    person_id, granted_to_org_id, purpose, legal_basis, scope_json
  ) values (
    v_invite.person_id, v_invite.org_id, 'hiring_decision', 'consent',
    jsonb_build_object(
      'assessment_id', v_invite.assessment_id,
      'invite_id',     v_invite.id
    )
  )
  returning id into v_consent_id;

  update public.assessment_invites
    set consent_recorded_id = v_consent_id, updated_at = now()
    where id = v_invite.id;

  update public.assessments
    set status = 'in_progress', updated_at = now()
    where id = v_invite.assessment_id and status = 'invited';

  return v_consent_id;
end;
$$;

revoke execute on function public.assessment_capture_consent(text) from public;
grant  execute on function public.assessment_capture_consent(text) to anon, authenticated, service_role;
comment on function public.assessment_capture_consent(text) is
  'Anon-callable. Validates invite token, creates consent_grants(purpose=hiring_decision), wires onto invite, advances assessment to in_progress. Idempotent.';

-- ---------------- assessment_submit_response ----------------------------
-- Anon-callable. Validates token + consent then writes a response.
create or replace function public.assessment_submit_response(
  p_token         text,
  p_item_id       uuid,
  p_response_json jsonb
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_invite      public.assessment_invites%rowtype;
  v_assessment  public.assessments%rowtype;
  v_item        public.assessment_items%rowtype;
  v_response_id uuid;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'assessment_submit_response: token required';
  end if;

  select * into v_invite from public.assessment_invites where token = p_token;
  if not found then raise exception 'assessment_submit_response: invalid token'; end if;
  if v_invite.used_at is not null then raise exception 'assessment_submit_response: invite already used'; end if;
  if v_invite.expires_at <= now() then raise exception 'assessment_submit_response: invite expired'; end if;
  if v_invite.consent_recorded_id is null then
    raise exception 'assessment_submit_response: consent not captured (call assessment_capture_consent first)';
  end if;

  select * into v_assessment from public.assessments where id = v_invite.assessment_id;
  select * into v_item       from public.assessment_items where id = p_item_id;
  if not found then raise exception 'assessment_submit_response: unknown item'; end if;
  if not exists (
    select 1 from public.assessment_instruments ai
    where ai.key = v_assessment.instrument_key and ai.id = v_item.instrument_id
  ) then
    raise exception 'assessment_submit_response: item does not belong to assessment instrument';
  end if;

  insert into public.assessment_responses (
    org_id, assessment_id, person_id, item_id, response_json, consent_id
  ) values (
    v_invite.org_id, v_invite.assessment_id, v_invite.person_id,
    p_item_id, p_response_json, v_invite.consent_recorded_id
  )
  returning id into v_response_id;

  return v_response_id;
end;
$$;

revoke execute on function public.assessment_submit_response(text, uuid, jsonb) from public;
grant  execute on function public.assessment_submit_response(text, uuid, jsonb) to anon, authenticated, service_role;
comment on function public.assessment_submit_response(text, uuid, jsonb) is
  'Anon-callable. Writes a single response gated by token + consent + item belonging to the assessment instrument.';

-- ---------------- assessment_run_scoring --------------------------------
-- Recruiter-triggered. Produces one assessment_scores row per scale via the
-- _dev_stub_score helper (clearly fake values; validity_status=dev_stub).
-- Marks assessment status=completed, invite.used_at.
create or replace function public.assessment_run_scoring(
  p_assessment_id uuid
)
returns int
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller     uuid := (select auth.uid());
  v_assessment public.assessments%rowtype;
  v_instrument public.assessment_instruments%rowtype;
  v_invite     public.assessment_invites%rowtype;
  v_scale_key  text;
  v_count      int := 0;
begin
  select * into v_assessment from public.assessments where id = p_assessment_id;
  if not found then raise exception 'assessment_run_scoring: assessment not found'; end if;

  if v_caller is not null and not public.has_permission(v_assessment.org_id, 'assessment.write') then
    raise exception 'assessment_run_scoring: caller lacks assessment.write';
  end if;

  if v_assessment.status not in ('in_progress', 'invited') then
    raise exception 'assessment_run_scoring: assessment status is % (must be in_progress)', v_assessment.status;
  end if;

  select * into v_invite from public.assessment_invites where assessment_id = p_assessment_id;
  if not found then raise exception 'assessment_run_scoring: no invite for assessment'; end if;
  if v_invite.consent_recorded_id is null then
    raise exception 'assessment_run_scoring: no consent captured';
  end if;

  select * into v_instrument from public.assessment_instruments where key = v_assessment.instrument_key;
  if not found then raise exception 'assessment_run_scoring: unknown instrument %', v_assessment.instrument_key; end if;

  for v_scale_key in
    select jsonb_array_elements_text(coalesce(v_instrument.body_json->'scales', '[]'::jsonb))
  loop
    perform public._dev_stub_score(p_assessment_id, v_assessment.person_id, v_invite.consent_recorded_id, v_scale_key);
    v_count := v_count + 1;
  end loop;

  update public.assessments
    set status = 'completed', completed_at = now(), updated_at = now()
    where id = p_assessment_id;

  update public.assessment_invites
    set used_at = now(), updated_at = now()
    where id = v_invite.id;

  return v_count;
end;
$$;

revoke execute on function public.assessment_run_scoring(uuid) from public;
grant  execute on function public.assessment_run_scoring(uuid) to authenticated, service_role;
comment on function public.assessment_run_scoring(uuid) is
  'Recruiter-triggered. Produces DEV-STUB scores per instrument scale, marks assessment completed + invite used.';
