-- fit_compute_upsert — Phase 1 Step 5 fix.
-- fit_results carries UNIQUE (requisition_id, person_id) — it's a snapshot per
-- pair, not a time series. The initial compute_fit_for_candidate used a plain
-- INSERT which fails on recompute. This switches to an UPSERT: the row id is
-- stable; computed_at + fit_json reflect the latest computation; audit_log
-- captures recompute events.

create or replace function public.compute_fit_for_candidate(
  p_requisition_id uuid,
  p_person_id      uuid
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller       uuid := (select auth.uid());
  v_req          public.requisitions%rowtype;
  v_role         public.roles_catalog%rowtype;
  v_assessment   public.assessments%rowtype;
  v_consent_id   uuid;
  v_per_comp     jsonb := '[]'::jsonb;
  v_trait_ranges jsonb := '[]'::jsonb;
  v_total        numeric := 0;
  v_weight_sum   numeric := 0;
  v_fit_json     jsonb;
  v_fit_id       uuid;
  v_competency   jsonb;
  v_trait        jsonb;
  v_person_score numeric;
  v_stub_value   numeric := 0.5;
begin
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then raise exception 'compute_fit_for_candidate: requisition not found'; end if;
  if v_caller is not null and not public.has_permission(v_req.org_id, 'fit.compute') then
    raise exception 'compute_fit_for_candidate: caller lacks fit.compute';
  end if;

  select * into v_assessment
    from public.assessments
    where person_id = p_person_id and org_id = v_req.org_id and status = 'completed'
    order by completed_at desc nulls last limit 1;
  if not found then
    raise exception 'compute_fit_for_candidate: no completed assessment for person % in org %', p_person_id, v_req.org_id;
  end if;

  select consent_recorded_id into v_consent_id
    from public.assessment_invites where assessment_id = v_assessment.id;
  if v_consent_id is null then raise exception 'compute_fit_for_candidate: assessment has no consent'; end if;

  select * into v_role from public.roles_catalog where id = v_req.role_id;
  if not found then raise exception 'compute_fit_for_candidate: role not found'; end if;

  for v_competency in
    select value from jsonb_array_elements(coalesce(v_role.definition_json->'competencies','[]'::jsonb))
  loop
    select coalesce(raw_score, scaled_score) into v_person_score
      from public.assessment_scores
      where assessment_id = v_assessment.id and scale_key = v_competency->>'key' limit 1;
    v_per_comp := v_per_comp || jsonb_build_array(
      jsonb_build_object(
        'key',           v_competency->>'key',
        'person_value',  to_jsonb(v_person_score),
        'target_weight', (v_competency->>'weight')::numeric,
        'fit_score',     to_jsonb(v_stub_value),
        '_dev_stub',     true
      )
    );
    v_total      := v_total + v_stub_value * coalesce((v_competency->>'weight')::numeric, 0);
    v_weight_sum := v_weight_sum + coalesce((v_competency->>'weight')::numeric, 0);
  end loop;

  for v_trait in
    select value from jsonb_array_elements(coalesce(v_role.definition_json->'trait_targets','[]'::jsonb))
  loop
    select coalesce(raw_score, scaled_score) into v_person_score
      from public.assessment_scores
      where assessment_id = v_assessment.id and scale_key = v_trait->>'trait' limit 1;
    v_trait_ranges := v_trait_ranges || jsonb_build_array(
      jsonb_build_object(
        'trait',        v_trait->>'trait',
        'person_value', to_jsonb(v_person_score),
        'band', jsonb_build_object(
          'min', coalesce((v_trait->'band'->>'min')::numeric, 0),
          'max', coalesce((v_trait->'band'->>'max')::numeric, 1)
        ),
        'status', case
          when v_person_score is null then 'in'
          when v_person_score < coalesce((v_trait->'band'->>'min')::numeric, 0) then 'below'
          when v_person_score > coalesce((v_trait->'band'->>'max')::numeric, 1) then 'above'
          else 'in'
        end,
        '_dev_stub', true
      )
    );
  end loop;

  v_fit_json := jsonb_build_object(
    'per_competency', v_per_comp,
    'trait_ranges',   v_trait_ranges,
    'overall_summary', jsonb_build_object(
      'competency_alignment', jsonb_build_object(
        'weighted_score', case when v_weight_sum > 0 then round(v_total / v_weight_sum, 4) else 0 end,
        'method',         'weighted_average_dev_stub',
        '_dev_stub',      true
      ),
      'trait_alignment', jsonb_build_object(
        'in_band',     (select count(*) from jsonb_array_elements(v_trait_ranges) e where e->>'status'='in'),
        'out_of_band', (select count(*) from jsonb_array_elements(v_trait_ranges) e where e->>'status' in ('below','above')),
        '_dev_stub',   true
      )
    )
  );

  insert into public.fit_results (
    org_id, requisition_id, person_id, role_id, consent_id,
    fit_json, validity_status, _dev_stub, computed_at
  ) values (
    v_req.org_id, p_requisition_id, p_person_id, v_role.id, v_consent_id,
    v_fit_json, 'dev_stub', true, now()
  )
  on conflict (requisition_id, person_id) do update set
    role_id         = excluded.role_id,
    consent_id      = excluded.consent_id,
    fit_json        = excluded.fit_json,
    validity_status = excluded.validity_status,
    _dev_stub       = excluded._dev_stub,
    computed_at     = excluded.computed_at,
    updated_at      = now()
  returning id into v_fit_id;

  insert into public.requisition_candidates (org_id, requisition_id, person_id, stage, fit_score_json)
    values (v_req.org_id, p_requisition_id, p_person_id, 'screening',
      jsonb_build_object(
        'fit_result_id',   v_fit_id,
        'computed_at',     now(),
        'weighted_score',  v_fit_json->'overall_summary'->'competency_alignment'->'weighted_score',
        'validity_status', 'dev_stub',
        '_dev_stub',       true
      ))
    on conflict (requisition_id, person_id)
    do update set fit_score_json = excluded.fit_score_json, updated_at = now();

  return v_fit_id;
end;
$$;
