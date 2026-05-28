-- phase4_step1_feature_functions — compute + freeze RPCs that operate on
-- the Phase 4 feature pipeline tables. Split out from the structural
-- migration so the table types/enums exist before the functions
-- reference them.

-- ============ feature computation: trait_range_fit ============
-- For a person + role, computes one value per competency: how the
-- person's latest trait/cognitive score falls relative to the role's
-- target band. This is the SCIENCE-SPEC §2 trait-range fit feature.
-- DEV STUB: returns a 0.5 mid-band fit value per competency. Real math
-- lands when the I/O psychologist plugs validated scoring.
create or replace function public.feature_compute_trait_range_fit(
  p_person_id      uuid,
  p_org_id         uuid,
  p_role_id        uuid,
  p_feature_view_id uuid,
  p_valid_at       timestamptz default now()
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller    uuid := (select auth.uid());
  v_consent   uuid;
  v_role      public.roles_catalog%rowtype;
  v_competency jsonb;
  v_per_comp  jsonb := '[]'::jsonb;
  v_source    jsonb;
  v_id        uuid;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'feature_compute_trait_range_fit: caller lacks modeling.write';
  end if;
  -- Modeling consent is research_anonymized, not ongoing_management.
  select id into v_consent from public.consent_grants
    where person_id = p_person_id and granted_to_org_id = p_org_id
      and purpose = 'research_anonymized' and status = 'active'
      and revoked_at is null and (expires_at is null or expires_at > now())
    limit 1;
  if v_consent is null then
    raise exception 'feature_compute_trait_range_fit: no active research_anonymized consent — modeling pipeline is consent-gated';
  end if;

  select * into v_role from public.roles_catalog where id = p_role_id;
  if not found then raise exception 'feature_compute_trait_range_fit: role not found'; end if;

  -- DEV STUB: every per-competency fit = 0.5 (mid-band). Real math
  -- requires validated scoring from the I/O psychologist.
  for v_competency in
    select value from jsonb_array_elements(coalesce(v_role.definition_json->'competencies','[]'::jsonb))
  loop
    v_per_comp := v_per_comp || jsonb_build_array(jsonb_build_object(
      'competency_key', v_competency->>'key',
      'target_weight', (v_competency->>'weight')::numeric,
      'band_fit',      0.5,    -- DEV STUB — replace with validated trait-range fit math
      '_dev_stub',     true
    ));
  end loop;

  v_source := jsonb_build_object(
    'role_id',      p_role_id,
    'role_version', v_role.version,
    'consent_id',   v_consent,
    'method',       'trait_range_fit_dev_stub_v0',
    '_dev_stub',    true
  );

  insert into public.feature_rows (
    org_id, feature_view_id, person_id, consent_id, valid_at,
    value_json, source_refs, _dev_stub, computed_at
  ) values (
    p_org_id, p_feature_view_id, p_person_id, v_consent, p_valid_at,
    jsonb_build_object('per_competency', v_per_comp, '_dev_stub', true),
    v_source, true, now()
  )
  returning id into v_id;

  return v_id;
end;
$$;
revoke execute on function public.feature_compute_trait_range_fit(uuid, uuid, uuid, uuid, timestamptz) from public;
grant  execute on function public.feature_compute_trait_range_fit(uuid, uuid, uuid, uuid, timestamptz) to authenticated, service_role;

-- ============ model_dataset_freeze ============
-- Walk every (person × feature_view) pair where the person has active
-- research_anonymized for the org; snapshot them into model_dataset_subjects.
-- Subjects who later revoke consent are STILL recorded as having been
-- in this historical dataset (compliance answer to "what did this model
-- see?") but won't appear in any FUTURE freeze.
create or replace function public.model_dataset_freeze(
  p_org_id          uuid,
  p_feature_view_id uuid,
  p_dataset_key     text,
  p_notes           text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller    uuid := (select auth.uid());
  v_dataset_id uuid;
  v_count int := 0;
  v_subj record;
begin
  if v_caller is not null and not public.has_permission(p_org_id, 'modeling.write') then
    raise exception 'model_dataset_freeze: caller lacks modeling.write';
  end if;

  insert into public.model_datasets (org_id, key, version, feature_view_id, frozen_at, source, notes, validity_status, _dev_stub)
    values (p_org_id, p_dataset_key, '0.0.1-dev', p_feature_view_id, now(), 'synthetic', p_notes, 'dev_stub', true)
    returning id into v_dataset_id;

  -- Subjects with active research_anonymized for this org, whose latest
  -- feature_row in this view has been computed under that consent.
  for v_subj in
    with eligible as (
      select cg.person_id, cg.id as consent_id
      from public.consent_grants cg
      where cg.granted_to_org_id = p_org_id
        and cg.purpose = 'research_anonymized'
        and cg.status = 'active' and cg.revoked_at is null
        and (cg.expires_at is null or cg.expires_at > now())
    )
    select e.person_id, e.consent_id,
           array_remove(array_agg(fr.id order by fr.valid_at desc), null) as feature_row_ids
    from eligible e
    left join public.feature_rows fr
      on fr.person_id = e.person_id
      and fr.org_id = p_org_id
      and fr.feature_view_id = p_feature_view_id
      and fr.consent_id = e.consent_id
    group by e.person_id, e.consent_id
  loop
    insert into public.model_dataset_subjects (dataset_id, person_id, consent_id, feature_row_ids)
      values (v_dataset_id, v_subj.person_id, v_subj.consent_id, coalesce(v_subj.feature_row_ids, '{}'::uuid[]));
    v_count := v_count + 1;
  end loop;

  update public.model_datasets set subject_count = v_count, updated_at = now() where id = v_dataset_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, (select id from public.people where auth_user_id = v_caller limit 1),
      'model_dataset.frozen', 'model_datasets', v_dataset_id,
      jsonb_build_object('feature_view_id', p_feature_view_id, 'subject_count', v_count,
                         'source', 'synthetic', '_dev_stub', true));

  return v_dataset_id;
end;
$$;
revoke execute on function public.model_dataset_freeze(uuid, uuid, text, text) from public;
grant  execute on function public.model_dataset_freeze(uuid, uuid, text, text) to authenticated, service_role;
comment on function public.model_dataset_freeze(uuid, uuid, text, text) is
  'Freezes a model dataset from the feature store at this instant. Only subjects with active research_anonymized at freeze-time are included. Synthetic-only marker is enforced via CHECK on source until validated.';
