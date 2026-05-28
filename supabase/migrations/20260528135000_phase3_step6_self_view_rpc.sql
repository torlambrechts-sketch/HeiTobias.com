-- phase3_step6_self_view_rpc — token-gated employee self-view.
-- The same data the manager sees, returned to the data subject via their
-- long-lived consent_token. NON-SURVEILLANCE discipline made structural:
-- there is no manager-only data; the employee always has visibility.

create or replace function public.lifecycle_self_view(p_token text)
returns jsonb
language plpgsql
stable
set search_path = ''
security definer
as $$
declare
  v_person_id uuid;
  v_pulses    jsonb;
  v_signals   jsonb;
  v_refit     jsonb;
  v_guidance  jsonb;
  v_outcomes  jsonb;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'lifecycle_self_view: token required';
  end if;
  select (r).person_id into v_person_id from public._consent_token_resolve(p_token) r;
  if v_person_id is null then
    raise exception 'lifecycle_self_view: invalid or expired token';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'submitted_at', submitted_at, 'org_id', org_id,
    'body_json', body_json
  ) order by submitted_at desc), '[]'::jsonb) into v_pulses
  from public.pulse_checkins where person_id = v_person_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'value_json', value_json, 'source_json', source_json,
    'generated_at', generated_at, '_dev_stub', _dev_stub
  ) order by generated_at desc), '[]'::jsonb) into v_signals
  from public.signals where person_id = v_person_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'quadrant', quadrant, 'computed_at', computed_at,
    'fit_json', fit_json, '_dev_stub', _dev_stub
  ) order by computed_at desc), '[]'::jsonb) into v_refit
  from public.refit_evaluations where person_id = v_person_id;

  -- The employee can see guidance written about them, with framework citations.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'output_json', output_json,
    'action', action, 'action_at', action_at, 'generated_at', generated_at
  ) order by generated_at desc), '[]'::jsonb) into v_guidance
  from public.guidance_items where person_id = v_person_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'happened_at', happened_at, 'notes', notes
  ) order by happened_at desc), '[]'::jsonb) into v_outcomes
  from public.outcome_captures where person_id = v_person_id;

  return jsonb_build_object(
    'pulses',   v_pulses,
    'signals',  v_signals,
    'refit',    v_refit,
    'guidance', v_guidance,
    'outcomes', v_outcomes
  );
end;
$$;
revoke execute on function public.lifecycle_self_view(text) from public;
grant  execute on function public.lifecycle_self_view(text) to anon, authenticated, service_role;
comment on function public.lifecycle_self_view(text) is
  'Anon, token-gated. Returns the data subject''s pulses + signals + re-fit history + guidance + outcomes — exactly what a manager would see. No manager-only data exists.';
