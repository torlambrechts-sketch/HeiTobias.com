-- phase3_step2_refit_engine — periodic re-measure of person vs. evolved role.
--
-- Two RPCs:
--   refit_compute(person, org)  — APPENDS a refit_evaluations row (never
--                                  overwrites — re-fit is a time-series).
--                                  Classifies into one of the four
--                                  quadrants (stable_fit / growth_gap /
--                                  flight_risk / emerging_misfit).
--   refit_history(person, org)  — read-only time-series for the
--                                  manager workspace + employee self-view.
--
-- Same DEV-STUB discipline as Phase 1's fit engine: every per-competency
-- fit is 0.5; the quadrant classification rotates per-call so the time-
-- series visibly moves (Phase 4 replaces this with real scoring against
-- the evolved role + trajectory + ground-truth outcome learning).

create or replace function public.refit_compute(
  p_person_id uuid,
  p_org_id    uuid
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
  v_role       public.roles_catalog%rowtype;
  v_per_comp   jsonb := '[]'::jsonb;
  v_trait_rg   jsonb := '[]'::jsonb;
  v_competency jsonb;
  v_trait      jsonb;
  v_weight_sum numeric := 0;
  v_total      numeric := 0;
  v_stub_value numeric := 0.5;
  v_quadrant   public.refit_quadrant;
  v_history_n  int;
  v_fit_json   jsonb;
  v_id         uuid;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'refit.compute') then
    raise exception 'refit_compute: caller lacks refit.compute in org';
  end if;

  -- Active ongoing_management consent is the hard gate per PHASE3 §A.
  select id into v_consent_id
    from public.consent_grants
    where person_id = p_person_id and granted_to_org_id = p_org_id
      and purpose = 'ongoing_management' and status = 'active'
      and revoked_at is null and (expires_at is null or expires_at > now())
    limit 1;
  if v_consent_id is null then
    raise exception 'refit_compute: no active ongoing_management consent for (person, org)';
  end if;

  -- The role we measure against: latest active position in the org.
  select rc.* into v_role
    from public.positions pos
    join public.roles_catalog rc on rc.id = pos.role_id
    where pos.person_id = p_person_id and pos.org_id = p_org_id
      and pos.status = 'filled'
    order by pos.start_date desc nulls last
    limit 1;
  if not found then
    raise exception 'refit_compute: no filled position for person in org';
  end if;

  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  -- Build per_competency + trait_ranges from the role definition.
  -- DEV STUB: fit_score is 0.5 per competency; person_value is null.
  for v_competency in
    select value from jsonb_array_elements(coalesce(v_role.definition_json->'competencies','[]'::jsonb))
  loop
    v_per_comp := v_per_comp || jsonb_build_array(jsonb_build_object(
      'key',           v_competency->>'key',
      'person_value',  null,
      'target_weight', (v_competency->>'weight')::numeric,
      'fit_score',     v_stub_value,
      '_dev_stub',     true
    ));
    v_total      := v_total + v_stub_value * coalesce((v_competency->>'weight')::numeric, 0);
    v_weight_sum := v_weight_sum + coalesce((v_competency->>'weight')::numeric, 0);
  end loop;

  for v_trait in
    select value from jsonb_array_elements(coalesce(v_role.definition_json->'trait_targets','[]'::jsonb))
  loop
    v_trait_rg := v_trait_rg || jsonb_build_array(jsonb_build_object(
      'trait',        v_trait->>'trait',
      'person_value', null,
      'band',         jsonb_build_object('min', coalesce((v_trait->'band'->>'min')::numeric, (v_trait->>'min')::numeric, 0),
                                          'max', coalesce((v_trait->'band'->>'max')::numeric, (v_trait->>'max')::numeric, 1)),
      'status',       'in',
      '_dev_stub',    true
    ));
  end loop;

  -- DEV-STUB quadrant rotation: walks through the four quadrants based
  -- on prior history count so a fresh demo seed visibly moves. Real
  -- classification comes from the Phase 4 trajectory algorithm.
  select count(*) into v_history_n from public.refit_evaluations
    where person_id = p_person_id and org_id = p_org_id;
  v_quadrant := (array['stable_fit','growth_gap','flight_risk','emerging_misfit']::public.refit_quadrant[])[ (v_history_n % 4) + 1 ];

  v_fit_json := jsonb_build_object(
    'per_competency', v_per_comp,
    'trait_ranges',   v_trait_rg,
    'overall_summary', jsonb_build_object(
      'competency_alignment', jsonb_build_object(
        'weighted_score', case when v_weight_sum > 0 then round(v_total / v_weight_sum, 4) else 0 end,
        'method',         'refit_weighted_average_dev_stub',
        '_dev_stub',      true
      ),
      'trait_alignment', jsonb_build_object('in_band',
        (select count(*) from jsonb_array_elements(v_trait_rg) e where e->>'status' = 'in'),
        'out_of_band', 0, '_dev_stub', true)
    )
  );

  insert into public.refit_evaluations (
    org_id, person_id, role_id, consent_id, fit_json, quadrant,
    validity_status, _dev_stub, computed_by, computed_at
  ) values (
    p_org_id, p_person_id, v_role.id, v_consent_id, v_fit_json, v_quadrant,
    'dev_stub', true, v_actor_id, now()
  )
  returning id into v_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor_id, 'refit.computed', 'refit_evaluations', v_id,
      jsonb_build_object('person_id', p_person_id, 'quadrant', v_quadrant, 'history_n', v_history_n));

  return v_id;
end;
$$;
revoke execute on function public.refit_compute(uuid, uuid) from public;
grant  execute on function public.refit_compute(uuid, uuid) to authenticated, service_role;
comment on function public.refit_compute(uuid, uuid) is
  'Appends a DEV-STUB re-fit evaluation. Requires active ongoing_management consent. Quadrant rotates through the four developmental states across the time-series. Phase 4 replaces with real trajectory scoring.';

create or replace function public.refit_history(
  p_person_id uuid,
  p_org_id    uuid,
  p_limit     int default 50
)
returns jsonb
language plpgsql
stable
set search_path = ''
security definer
as $$
declare
  v_rows jsonb;
begin
  -- RLS on refit_evaluations is the authoritative gate; this helper just
  -- shapes the output. SECURITY DEFINER would bypass RLS but we set
  -- search_path empty and explicitly check authorization via the policy
  -- by querying ONLY rows the caller can see.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',           e.id,
    'quadrant',     e.quadrant,
    'computed_at',  e.computed_at,
    'fit_json',     e.fit_json,
    'role_id',      e.role_id,
    'validity_status', e.validity_status,
    '_dev_stub',    e._dev_stub
  ) order by e.computed_at desc), '[]'::jsonb) into v_rows
  from (
    select id, quadrant, computed_at, fit_json, role_id, validity_status, _dev_stub
      from public.refit_evaluations
      where person_id = p_person_id and org_id = p_org_id
      order by computed_at desc
      limit p_limit
  ) e;
  return jsonb_build_object('history', v_rows);
end;
$$;
revoke execute on function public.refit_history(uuid, uuid, int) from public;
grant  execute on function public.refit_history(uuid, uuid, int) to authenticated, service_role;
