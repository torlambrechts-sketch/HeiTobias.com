-- phase3_step3_pulse_signals — consented check-ins + derived signals.
--
-- Authenticated employee submits their own pulse (is_self). Managers can
-- read aggregated signals derived from the pulses + structured profile
-- data — never raw background telemetry, and never anything the employee
-- can't see on their own /me/profile view (DEVELOPMENTAL-not-surveillance
-- discipline).

-- Seed a DEV-STUB check-in template the UI uses by default.
insert into public.frameworks (org_id, key, kind, name, body_json, validity_status, _dev_stub, vendor) values
(null, 'pulse_v0_quarterly', 'check_in_template',
  'DEV STUB · Quarterly pulse — energy / clarity / support',
  jsonb_build_object(
    'cadence_days', 90,
    'questions', jsonb_build_array(
      jsonb_build_object('key','energy',  'prompt','How''s your energy in this role right now?', 'scale', jsonb_build_array(1,2,3,4,5)),
      jsonb_build_object('key','clarity', 'prompt','Is what''s expected of you clear?',           'scale', jsonb_build_array(1,2,3,4,5)),
      jsonb_build_object('key','support', 'prompt','Are you getting the support you need?',      'scale', jsonb_build_array(1,2,3,4,5))
    ),
    'free_text_key', 'note',
    'free_text_prompt', 'Anything you want to flag (optional)'
  ),
  'dev_stub', true, 'HeiTobias (DEV STUB)')
on conflict (org_id, key, version) do nothing;

-- ---- pulse_submit(consent_id, template_id, body_json) ----
-- Anon-callable? No — Step 0 answer was authenticated only. The data
-- subject submits their own pulse; auth.uid() must resolve to a person
-- whose id matches. body_json is validated soft (must contain answers).
create or replace function public.pulse_submit(
  p_consent_id uuid,
  p_template_id uuid,
  p_body_json   jsonb
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller     uuid := (select auth.uid());
  v_person     public.people%rowtype;
  v_consent    public.consent_grants%rowtype;
  v_id         uuid;
begin
  if v_caller is null then
    raise exception 'pulse_submit: authentication required';
  end if;
  select * into v_person from public.people where auth_user_id = v_caller limit 1;
  if not found then
    raise exception 'pulse_submit: no person row for caller';
  end if;
  select * into v_consent from public.consent_grants where id = p_consent_id;
  if not found then raise exception 'pulse_submit: consent not found'; end if;
  if v_consent.person_id <> v_person.id then
    raise exception 'pulse_submit: consent does not belong to caller (is_self check failed)';
  end if;
  if v_consent.purpose <> 'ongoing_management' or v_consent.status <> 'active'
     or v_consent.revoked_at is not null
     or (v_consent.expires_at is not null and v_consent.expires_at <= now())
  then
    raise exception 'pulse_submit: requires active ongoing_management consent';
  end if;
  if p_body_json is null or jsonb_typeof(p_body_json) <> 'object' then
    raise exception 'pulse_submit: body_json must be an object';
  end if;

  insert into public.pulse_checkins (org_id, person_id, consent_id, template_id, submitted_at, body_json)
    values (v_consent.granted_to_org_id, v_person.id, p_consent_id, p_template_id, now(), p_body_json)
    returning id into v_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_consent.granted_to_org_id, v_person.id, 'pulse.submitted', 'pulse_checkins', v_id,
      jsonb_build_object('template_id', p_template_id, 'consent_id', p_consent_id));

  return v_id;
end;
$$;
revoke execute on function public.pulse_submit(uuid, uuid, jsonb) from public;
grant  execute on function public.pulse_submit(uuid, uuid, jsonb) to authenticated, service_role;
comment on function public.pulse_submit(uuid, uuid, jsonb) is
  'Authenticated employee submits a pulse check-in. Self-only (consent must belong to caller). Audited.';

-- ---- signal_compute(person, org) ----
-- Aggregates the most recent N pulse_checkins into signals. Every signal
-- carries source_json citing the pulse_ids that fed it — the employee
-- sees exactly what's feeding the manager view.
create or replace function public.signal_compute(
  p_person_id uuid,
  p_org_id    uuid,
  p_window_n  int default 4
)
returns int
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller     uuid := (select auth.uid());
  v_actor_id   uuid;
  v_consent_id uuid;
  v_count      int := 0;
  v_key        text;
  v_avg        numeric;
  v_pulse_ids  uuid[];
  v_n          int;
  v_keys constant text[] := array['energy','clarity','support'];
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'pulse.read') then
    raise exception 'signal_compute: caller lacks pulse.read in org';
  end if;
  select id into v_consent_id from public.consent_grants
    where person_id = p_person_id and granted_to_org_id = p_org_id
      and purpose = 'ongoing_management' and status = 'active'
      and revoked_at is null and (expires_at is null or expires_at > now()) limit 1;
  if v_consent_id is null then
    raise exception 'signal_compute: no active ongoing_management consent';
  end if;
  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  foreach v_key in array v_keys
  loop
    with recent as (
      select id, body_json
        from public.pulse_checkins
        where person_id = p_person_id and org_id = p_org_id
        order by submitted_at desc
        limit p_window_n
    ),
    extracted as (
      select r.id,
             (item->>'value')::numeric as value
        from recent r,
        lateral jsonb_array_elements(coalesce(r.body_json->'answers','[]'::jsonb)) item
        where item->>'key' = v_key
    )
    select avg(value), array_agg(id), count(*)
      into v_avg, v_pulse_ids, v_n
      from extracted;

    if v_n > 0 then
      insert into public.signals (
        org_id, person_id, consent_id, kind, value_json, source_json,
        validity_status, _dev_stub, generated_by, generated_at
      ) values (
        p_org_id, p_person_id, v_consent_id, v_key || '_trend',
        jsonb_build_object('mean', round(v_avg, 2), 'n', v_n, 'window_days', null),
        jsonb_build_object('pulse_ids', to_jsonb(v_pulse_ids), 'window_n', p_window_n, 'key', v_key,
                           'source','pulse_checkins'),
        'dev_stub', true, v_actor_id, now()
      );
      v_count := v_count + 1;
    end if;
  end loop;

  if v_count > 0 then
    insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
      values (p_org_id, v_actor_id, 'signal.computed', 'signals', null,
        jsonb_build_object('person_id', p_person_id, 'signals_count', v_count, 'window_n', p_window_n));
  end if;
  return v_count;
end;
$$;
revoke execute on function public.signal_compute(uuid, uuid, int) from public;
grant  execute on function public.signal_compute(uuid, uuid, int) to authenticated, service_role;
comment on function public.signal_compute(uuid, uuid, int) is
  'Aggregates the most recent N pulse_checkins into derived signals. Every signal carries source_json with the pulse_ids that fed it — never freeform, never background-collected.';
