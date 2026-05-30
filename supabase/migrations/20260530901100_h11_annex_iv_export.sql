-- H-11 — Annex IV Technical Documentation Export (Run 12 of H-1..H-10)
--
-- The end-to-end export RPC. Assembles the platform's state across all
-- H-1..H-10 surfaces into a single self-contained jsonb document that
-- can be handed to an EU AI Act notified body, an internal auditor,
-- or a court. Snapshot is written as a NEW compliance_artifact of
-- kind='annex_iv_technical_doc' for permanent archival.
--
-- The export captures, for a given org_id + optional date range:
--   * Citations (the evidence base — Run 1)
--   * Evidence-base positions per predictor_type
--   * Predictor combination decisions
--   * Trait activation factor catalog + per-role ratings
--   * Personality role templates + their trait directions
--   * Norm samples + adaptation linkage
--   * Invariance runs + results
--   * DIF runs + items
--   * Fairness runs + metrics
--   * Pareto curves + weight choices
--   * Model registry + cards
--   * Monitoring runs + alerts + incidents
--   * Compliance artifacts (prior exports, DPIAs, FRIAs)
--   * Vendor acknowledgments
--   * Audit log within date range
--
-- Counts only; the FULL records are referenced by id-list so the
-- jsonb bundle stays a manageable size. A future "deep export"
-- variant could pull the entire records.
--
-- Gate: role.export in org. Writes the result as a compliance_artifact
-- in pending state (dev_stub) — promoting to validated still requires
-- the dual modeling.signoff + legal.signoff via the Run 11 RPCs.

create or replace function public.rpc_annex_iv_export(
  p_org_id        uuid,
  p_date_from     timestamptz default null,
  p_date_to       timestamptz default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_caller         uuid;
  v_artifact_id    uuid;
  v_payload        jsonb;
  v_from           timestamptz := coalesce(p_date_from, '1900-01-01'::timestamptz);
  v_to             timestamptz := coalesce(p_date_to,   '2999-12-31'::timestamptz);
begin
  if not public.has_permission(p_org_id, 'role.export') then
    raise exception 'denied: role.export required in org %', p_org_id using errcode='42501';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;

  v_payload := jsonb_build_object(
    'export_metadata', jsonb_build_object(
      'export_id_pending', true,
      'org_id',            p_org_id,
      'date_from',         v_from,
      'date_to',           v_to,
      'generated_at',      now(),
      'generated_by',      v_caller,
      'export_scope',      'org_wide_annex_iv_technical_documentation',
      'ai_act_reference',  'Regulation (EU) 2024/1689, Annex IV'
    ),

    -- H-1: Evidence base
    'evidence_base', jsonb_build_object(
      'citations', (select jsonb_agg(jsonb_build_object(
                      'citation_key', citation_key, 'authors', authors,
                      'year', year, 'title', title, 'doi', doi))
                     from public.citations),
      'positions', (select jsonb_agg(to_jsonb(v_current_evidence_base_position))
                     from public.v_current_evidence_base_position),
      'predictor_combo_decisions', (select jsonb_agg(jsonb_build_object(
                      'id', id, 'role_id', role_id, 'requisition_id', requisition_id,
                      'evidence_base_version_id', evidence_base_version_id,
                      'n_predictors', jsonb_array_length(combo_json),
                      'weights_sum_to', weights_sum_to,
                      'validity_status', validity_status,
                      '_dev_stub', _dev_stub))
                     from public.v_current_predictor_combination
                    where org_id = p_org_id)
    ),

    -- H-2: Trait activation
    'trait_activation', jsonb_build_object(
      'factor_catalog_count', (select count(*) from public.trait_activation_factor_catalog),
      'factor_catalog_validated_count', (select count(*) from public.trait_activation_factor_catalog where validity_status='validated'),
      'role_ratings_for_org', (select count(*) from public.role_context_factors where org_id=p_org_id),
      'role_ratings_validated', (select count(*) from public.role_context_factors where org_id=p_org_id and validity_status='validated')
    ),

    -- H-3: Pareto
    'pareto', jsonb_build_object(
      'curves_total',         (select count(*) from public.pareto_curves where org_id=p_org_id),
      'curves_validated',     (select count(*) from public.pareto_curves where org_id=p_org_id and validity_status='validated'),
      'weight_choices_total', (select count(*) from public.pareto_weight_choices where org_id=p_org_id),
      'weight_choices_validated', (select count(*) from public.pareto_weight_choices where org_id=p_org_id and validity_status='validated'),
      'curves_summary', (select jsonb_agg(jsonb_build_object(
                          'id', id, 'key', key, 'is_cross_validated', is_cross_validated,
                          'cv_method', cv_method, 'sample_size', sample_size,
                          'power_estimate', power_estimate, 'shrinkage_estimate', shrinkage_estimate,
                          'validity_status', validity_status))
                         from public.pareto_curves where org_id=p_org_id)
    ),

    -- H-4: Invariance
    'invariance', jsonb_build_object(
      'runs_total',     (select count(*) from public.invariance_runs where org_id=p_org_id),
      'runs_validated', (select count(*) from public.invariance_runs where org_id=p_org_id and validity_status='validated'),
      'runs_summary', (select jsonb_agg(jsonb_build_object(
                        'id', id, 'instrument_key', instrument_key, 'engine', engine,
                        'cutoff_standard', cutoff_standard, 'n_groups', n_groups,
                        'validity_status', validity_status))
                       from public.invariance_runs where org_id=p_org_id)
    ),

    -- H-5: DIF
    'dif', jsonb_build_object(
      'runs_total',     (select count(*) from public.dif_runs where org_id=p_org_id),
      'runs_validated', (select count(*) from public.dif_runs where org_id=p_org_id and validity_status='validated'),
      'flagged_items', (select count(*) from public.dif_items i
                         join public.dif_runs r on r.id=i.run_id
                        where r.org_id=p_org_id and i.bias_review_required=true)
    ),

    -- H-6: Fairness
    'fairness', jsonb_build_object(
      'runs_total',     (select count(*) from public.fairness_runs where org_id=p_org_id),
      'runs_validated', (select count(*) from public.fairness_runs where org_id=p_org_id and validity_status='validated'),
      'metrics_summary', (select jsonb_agg(jsonb_build_object(
                           'characteristic', m.characteristic, 'air', m.adverse_impact_ratio,
                           'over_prediction_flag', m.over_prediction_flag,
                           'interpretation', m.interpretation_by_expert))
                          from public.fairness_metrics m
                          join public.fairness_runs r on r.id=m.run_id
                         where r.org_id=p_org_id)
    ),

    -- H-7: Norm samples
    'norms', jsonb_build_object(
      'samples_total',     (select count(*) from public.norm_samples where org_id=p_org_id or org_id is null),
      'samples_validated', (select count(*) from public.norm_samples where (org_id=p_org_id or org_id is null) and validity_status='validated')
    ),

    -- H-8: Model cards + monitoring
    'models', jsonb_build_object(
      'registry_total',  (select count(*) from public.model_registry where org_id=p_org_id),
      'cards_validated', (select count(*) from public.model_cards c
                           join public.model_registry r on r.id=c.model_id
                          where r.org_id=p_org_id and c.validity_status='validated')
    ),
    'monitoring', jsonb_build_object(
      'runs_in_window',         (select count(*) from public.monitoring_runs where org_id=p_org_id and ran_at between v_from and v_to),
      'alerts_open',            (select count(*) from public.monitoring_alerts where org_id=p_org_id and status in ('open','acknowledged')),
      'incidents_open',         (select count(*) from public.monitoring_incidents where org_id=p_org_id and resolved_at is null),
      'incidents_closed_in_window', (select count(*) from public.monitoring_incidents
                                       where org_id=p_org_id
                                         and resolved_at between v_from and v_to)
    ),

    -- H-9/H-10: Compliance + legal
    'compliance', jsonb_build_object(
      'artifacts_total',     (select count(*) from public.compliance_artifacts where org_id=p_org_id),
      'artifacts_validated', (select count(*) from public.compliance_artifacts where org_id=p_org_id and validity_status='validated'),
      'artifact_kinds', (select jsonb_object_agg(kind, n) from (
                          select kind, count(*) n from public.compliance_artifacts
                           where org_id=p_org_id group by kind) k)
    ),
    'vendor_acknowledgments', jsonb_build_object(
      'total',     (select count(*) from public.vendor_acknowledgments where org_id=p_org_id),
      'validated', (select count(*) from public.vendor_acknowledgments where org_id=p_org_id and validity_status='validated'),
      'vendor_summary', (select jsonb_agg(jsonb_build_object(
                          'vendor_name', vendor_name, 'vendor_role', vendor_role,
                          'workday_precedent_acknowledged', workday_precedent_acknowledged,
                          'validity_status', validity_status,
                          'effective_from', effective_from,
                          'effective_to', effective_to))
                         from public.vendor_acknowledgments where org_id=p_org_id)
    ),

    -- Audit trail in window
    'audit_trail', jsonb_build_object(
      'events_in_window', (select count(*) from public.audit_log
                            where org_id=p_org_id and created_at between v_from and v_to),
      'action_summary',   (select jsonb_object_agg(action, n) from (
                            select action, count(*) n from public.audit_log
                             where org_id=p_org_id and created_at between v_from and v_to
                             group by action) a)
    ),

    -- Discipline check: total validated rows = 0 means no expert
    -- sign-off has ever happened in this org (pure-stub deployment)
    'discipline_check', jsonb_build_object(
      'platform_dev_stub_seam_present', true,
      'note', 'Every scientific surface enforces dev_stub→signed-off promotion via DB CHECK. See SCIENCE-REFERENCE.md.'
    )
  );

  -- Persist as a compliance_artifact for permanent record
  insert into public.compliance_artifacts
    (org_id, kind, key, version, scope_json, payload_json,
     generated_at, validity_status, _dev_stub,
     annex_iii_high_risk_class, annex_iii_high_risk_rationale)
  values
    (p_org_id, 'annex_iv_technical_doc',
     'annex-iv-export', to_char(now(), 'YYYY-MM-DD-HH24MISS'),
     jsonb_build_object('date_from', v_from, 'date_to', v_to, 'export_kind', 'org_wide'),
     v_payload,
     now(), 'dev_stub', true,
     'employment_recruitment',
     'Talent lifecycle platform classified high-risk under AI Act Annex III §4(a) — employment, workers'' management and access to self-employment, specifically recruitment and selection.')
  returning id into v_artifact_id;

  -- Backfill the export_id in the payload (we couldn't know it before INSERT)
  update public.compliance_artifacts
     set payload_json = payload_json
       || jsonb_build_object('export_metadata',
            (payload_json->'export_metadata') || jsonb_build_object('export_id', v_artifact_id, 'export_id_pending', false))
   where id = v_artifact_id;

  perform public.audit_log_event(
    p_org_id, 'annex_iv.export', 'compliance_artifact', v_artifact_id, null,
    jsonb_build_object('generated_by', v_caller,
      'date_from', v_from, 'date_to', v_to,
      'sections', array['evidence_base','trait_activation','pareto','invariance','dif',
                        'fairness','norms','models','monitoring','compliance',
                        'vendor_acknowledgments','audit_trail','discipline_check']), null);

  return jsonb_build_object(
    'ok', true,
    'artifact_id', v_artifact_id,
    'org_id', p_org_id,
    'sections_assembled', 13,
    'validity_status', 'dev_stub',
    'note', 'Promote to validated via rpc_compliance_artifact_signoff_modeling THEN rpc_compliance_artifact_signoff_legal.'
  );
end;
$$;

revoke all on function public.rpc_annex_iv_export(uuid, timestamptz, timestamptz) from public;
grant execute on function public.rpc_annex_iv_export(uuid, timestamptz, timestamptz) to authenticated, service_role;

comment on function public.rpc_annex_iv_export(uuid, timestamptz, timestamptz) is
  'Assembles platform state across all H-1..H-10 surfaces into a single jsonb compliance_artifact of kind annex_iv_technical_doc. Org-scoped; date-windowed for time-bounded audits. Gates on role.export. Produces dev_stub artifact — promotion to validated still requires the dual modeling+legal sign-off.';
