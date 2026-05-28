-- fit_and_placement_report_engine — Phase 1 Step 5.
--
-- Two SECURITY DEFINER RPCs:
--   compute_fit_for_candidate(req_id, person_id)
--       Computes a DEV-STUB fit result: per-competency match,
--       trait-range membership, overall summary. Writes fit_results
--       (validity_status='dev_stub', _dev_stub=true) and refreshes
--       requisition_candidates.fit_score_json with a summary.
--       Does NOT touch requisition_candidates.decision — humans decide.
--   placement_report_generate(req_id, person_id)
--       Generates an HTML report from the latest fit_result.
--       Report opens with the EU-AI-Act / Phase 1 §10 disclaimer:
--       "informs a human decision; never auto-decides".
--
-- The fit_json shape conforms to chk_fit_json_shape (per_competency,
-- trait_ranges, overall_summary). DEV STUB fields use clearly fake
-- values (0.5 fixed) so a reviewer cannot mistake them for real science.

-- ---------------- compute_fit_for_candidate -----------------------------
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
  v_stub_value   numeric := 0.5;  -- DEV STUB: every per-competency fit is 0.5
begin
  -- Load requisition
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then raise exception 'compute_fit_for_candidate: requisition not found'; end if;

  -- AuthZ
  if v_caller is not null and not public.has_permission(v_req.org_id, 'fit.compute') then
    raise exception 'compute_fit_for_candidate: caller lacks fit.compute';
  end if;

  -- Latest completed assessment for the person in this org
  select * into v_assessment
    from public.assessments
    where person_id = p_person_id
      and org_id = v_req.org_id
      and status = 'completed'
    order by completed_at desc nulls last
    limit 1;
  if not found then
    raise exception 'compute_fit_for_candidate: no completed assessment for person % in org %', p_person_id, v_req.org_id;
  end if;

  -- Consent attached to that assessment
  select consent_recorded_id into v_consent_id
    from public.assessment_invites
    where assessment_id = v_assessment.id;
  if v_consent_id is null then
    raise exception 'compute_fit_for_candidate: assessment has no consent';
  end if;

  -- Load role definition
  select * into v_role from public.roles_catalog where id = v_req.role_id;
  if not found then raise exception 'compute_fit_for_candidate: role not found'; end if;

  -- Build per_competency: iterate role.definition_json.competencies; for each,
  -- look up a matching scale by key (DEV STUB 1-to-1 string match).
  for v_competency in
    select value from jsonb_array_elements(coalesce(v_role.definition_json->'competencies','[]'::jsonb))
  loop
    select coalesce(raw_score, scaled_score) into v_person_score
      from public.assessment_scores
      where assessment_id = v_assessment.id and scale_key = v_competency->>'key'
      limit 1;
    -- DEV STUB: fit_score is a fixed 0.5 placeholder regardless of person_value.
    v_per_comp := v_per_comp || jsonb_build_array(
      jsonb_build_object(
        'key',           v_competency->>'key',
        'person_value',  to_jsonb(v_person_score),  -- null for dev_stub scores
        'target_weight', (v_competency->>'weight')::numeric,
        'fit_score',     to_jsonb(v_stub_value),
        '_dev_stub',     true
      )
    );
    v_total      := v_total + v_stub_value * coalesce((v_competency->>'weight')::numeric, 0);
    v_weight_sum := v_weight_sum + coalesce((v_competency->>'weight')::numeric, 0);
  end loop;

  -- Build trait_ranges: iterate role.definition_json.trait_targets (if any).
  for v_trait in
    select value from jsonb_array_elements(coalesce(v_role.definition_json->'trait_targets','[]'::jsonb))
  loop
    select coalesce(raw_score, scaled_score) into v_person_score
      from public.assessment_scores
      where assessment_id = v_assessment.id and scale_key = v_trait->>'trait'
      limit 1;
    v_trait_ranges := v_trait_ranges || jsonb_build_array(
      jsonb_build_object(
        'trait',        v_trait->>'trait',
        'person_value', to_jsonb(v_person_score),
        'band', jsonb_build_object(
          'min', coalesce((v_trait->'band'->>'min')::numeric, 0),
          'max', coalesce((v_trait->'band'->>'max')::numeric, 1)
        ),
        -- DEV STUB: status='in' vacuously when person_value is null
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

  -- Assemble fit_json (shape validated by chk_fit_json_shape)
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

  -- Insert fit_results (always dev_stub from this RPC)
  insert into public.fit_results (
    org_id, requisition_id, person_id, role_id, consent_id,
    fit_json, validity_status, _dev_stub, computed_at
  ) values (
    v_req.org_id, p_requisition_id, p_person_id, v_role.id, v_consent_id,
    v_fit_json, 'dev_stub', true, now()
  )
  returning id into v_fit_id;

  -- Refresh requisition_candidates.fit_score_json with a SUMMARY (informs humans).
  -- Insert the candidate row if it doesn't exist; otherwise update.
  insert into public.requisition_candidates (org_id, requisition_id, person_id, stage, fit_score_json)
    values (v_req.org_id, p_requisition_id, p_person_id, 'screening',
      jsonb_build_object(
        'fit_result_id',    v_fit_id,
        'computed_at',      now(),
        'weighted_score',   v_fit_json->'overall_summary'->'competency_alignment'->'weighted_score',
        'validity_status',  'dev_stub',
        '_dev_stub',        true
      ))
    on conflict (requisition_id, person_id)
    do update set
      fit_score_json = excluded.fit_score_json,
      updated_at     = now();

  return v_fit_id;
end;
$$;

revoke execute on function public.compute_fit_for_candidate(uuid, uuid) from public;
grant  execute on function public.compute_fit_for_candidate(uuid, uuid) to authenticated, service_role;
comment on function public.compute_fit_for_candidate(uuid, uuid) is
  'Computes DEV-STUB fit (per-competency + trait_ranges) from the latest completed assessment. Writes fit_results, refreshes requisition_candidates.fit_score_json. Never touches .decision — humans decide.';

-- ---------------- placement_report_generate -----------------------------
-- Builds an HTML report from the latest fit_result. Report opens with the
-- human-in-the-loop / EU AI Act disclaimer. AuthZ: fit.read in org.
create or replace function public.placement_report_generate(
  p_requisition_id uuid,
  p_person_id      uuid
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller    uuid := (select auth.uid());
  v_req       public.requisitions%rowtype;
  v_actor_id  uuid;
  v_fit       public.fit_results%rowtype;
  v_person    public.people%rowtype;
  v_role      public.roles_catalog%rowtype;
  v_report_id uuid;
  v_html      text;
  v_comp_rows text := '';
  v_trait_rows text := '';
  v_disclaimer text;
  v_row jsonb;
begin
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then raise exception 'placement_report_generate: requisition not found'; end if;

  if v_caller is not null and not public.has_permission(v_req.org_id, 'fit.read') then
    raise exception 'placement_report_generate: caller lacks fit.read';
  end if;

  select * into v_fit from public.fit_results
    where requisition_id = p_requisition_id and person_id = p_person_id
    order by computed_at desc limit 1;
  if not found then
    raise exception 'placement_report_generate: no fit_result for this candidate; run compute_fit_for_candidate first';
  end if;

  select * into v_person from public.people where id = p_person_id;
  select * into v_role   from public.roles_catalog where id = v_fit.role_id;
  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  v_disclaimer := '<div class="hitl-disclaimer" style="background:#fff3cd;padding:12px;border-left:4px solid #ff9800;">' ||
    '<strong>DEV STUB — informs a human decision; never auto-decides.</strong> ' ||
    'Per EU AI Act and HeiTobias policy: this report and any fit score it contains are ' ||
    'advisory inputs only. A qualified human assessor is the decision-maker. Validity status: ' ||
    coalesce(v_fit.validity_status::text, 'dev_stub') || '.</div>';

  -- Competency table rows
  for v_row in select value from jsonb_array_elements(coalesce(v_fit.fit_json->'per_competency','[]'::jsonb))
  loop
    v_comp_rows := v_comp_rows ||
      '<tr><td>' || coalesce(v_row->>'key','') ||
      '</td><td>' || coalesce(v_row->>'target_weight','-') ||
      '</td><td>' || coalesce(v_row->>'person_value','—') ||
      '</td><td>' || coalesce(v_row->>'fit_score','—') ||
      '</td></tr>';
  end loop;

  -- Trait table rows
  for v_row in select value from jsonb_array_elements(coalesce(v_fit.fit_json->'trait_ranges','[]'::jsonb))
  loop
    v_trait_rows := v_trait_rows ||
      '<tr><td>' || coalesce(v_row->>'trait','') ||
      '</td><td>' || coalesce(v_row->>'person_value','—') ||
      '</td><td>' || coalesce((v_row->'band'->>'min'),'-') || '–' || coalesce((v_row->'band'->>'max'),'-') ||
      '</td><td>' || coalesce(v_row->>'status','—') ||
      '</td></tr>';
  end loop;

  v_html :=
    '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Placement Report — ' ||
    coalesce(v_person.full_name,'(unknown)') || ' · ' || coalesce(v_role.title,'(unknown role)') ||
    '</title></head><body>' ||
    v_disclaimer ||
    '<h1>Placement Report (DEV STUB)</h1>' ||
    '<p><strong>Candidate:</strong> ' || coalesce(v_person.full_name,'') || '<br>' ||
    '<strong>Role:</strong> ' || coalesce(v_role.title,'') || ' (v' || coalesce(v_role.version::text,'?') || ')<br>' ||
    '<strong>Computed:</strong> ' || to_char(v_fit.computed_at, 'YYYY-MM-DD HH24:MI:SS TZ') || '</p>' ||
    '<h2>Competency alignment</h2>' ||
    '<p><em>Weighted score (DEV STUB):</em> ' ||
       coalesce((v_fit.fit_json->'overall_summary'->'competency_alignment'->>'weighted_score'),'—') || '</p>' ||
    '<table border="1" cellpadding="6"><thead><tr><th>Competency</th><th>Target weight</th><th>Person value</th><th>Fit (stub)</th></tr></thead><tbody>' ||
    v_comp_rows || '</tbody></table>' ||
    '<h2>Trait ranges</h2>' ||
    '<table border="1" cellpadding="6"><thead><tr><th>Trait</th><th>Person value</th><th>Target band</th><th>Status</th></tr></thead><tbody>' ||
    v_trait_rows || '</tbody></table>' ||
    v_disclaimer ||
    '</body></html>';

  insert into public.placement_reports (org_id, requisition_id, person_id, fit_result_id, report_html, generated_by)
    values (v_req.org_id, p_requisition_id, p_person_id, v_fit.id, v_html, v_actor_id)
    returning id into v_report_id;

  return v_report_id;
end;
$$;

revoke execute on function public.placement_report_generate(uuid, uuid) from public;
grant  execute on function public.placement_report_generate(uuid, uuid) to authenticated, service_role;
comment on function public.placement_report_generate(uuid, uuid) is
  'Generates an HTML placement report from the latest fit_result for (requisition, person). Embeds the human-in-the-loop disclaimer. AuthZ: fit.read in org.';
