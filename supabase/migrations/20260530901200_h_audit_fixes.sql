-- H-1..H-10 — SENIOR-TEAM AUDIT FIXES (F1..F18)
--
-- Two-agent audit + live-DB CRUD verification found 18 real defects.
-- Numbered F1..F18 in commit message. Severities:
--   CRITICAL : F9 (broken Annex IV export), F10 (broken alert state
--              machine), F11 (toothless model-card CHECK), F12
--              (global runs can never be signed off), F13 (race in
--              run-level signoff allows non-validated child).
--   HIGH     : F1 (vendor_acks policy/RPC mismatch), F2 (audit_log_event
--              org.read silent rollback), F3 (incident close cross-org
--              gap), F4 (missing DELETE policies), F14 (FK ON DELETE),
--              F15 (nil UUID sentinel), F8 (curve lock).
--   MEDIUM   : F5 (trigger SECDEF smell), F6 (audit triggers), F7
--              (signoff UPDATE policies), F16 (norm_percentiles seam),
--              F17 (ETS classifier 1.5 edge), F18 (cutoff null explicit).
--
-- This fix migration is idempotent on a clean DB (every change uses
-- drop-then-create or if-not-exists patterns).

-- ─── F9 [CRITICAL]: rpc_annex_iv_export queries audit_log.created_at
-- but the column is `at`. Annex IV export crashes on first call.
-- Replace the function with the corrected column reference.
create or replace function public.rpc_annex_iv_export(
  p_org_id uuid, p_date_from timestamptz default null, p_date_to timestamptz default null
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
  -- F2 precheck: audit_log_event requires org.read
  if not public.has_permission(p_org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;

  v_payload := jsonb_build_object(
    'export_metadata', jsonb_build_object(
      'export_id_pending', true, 'org_id', p_org_id,
      'date_from', v_from, 'date_to', v_to,
      'generated_at', now(), 'generated_by', v_caller,
      'export_scope', 'org_wide_annex_iv_technical_documentation',
      'ai_act_reference', 'Regulation (EU) 2024/1689, Annex IV'),
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
                      'combo_json', combo_json,
                      'n_predictors', jsonb_array_length(combo_json),
                      'weights_sum_to', weights_sum_to,
                      'rationale', rationale,
                      'validity_status', validity_status, '_dev_stub', _dev_stub))
                     from public.v_current_predictor_combination where org_id = p_org_id)),
    'trait_activation', jsonb_build_object(
      'factor_catalog', (select jsonb_agg(jsonb_build_object(
                          'factor_key', factor_key, 'level', level, 'category', category,
                          'name', name, 'validity_status', validity_status))
                         from public.trait_activation_factor_catalog),
      'role_ratings_for_org', (select jsonb_agg(jsonb_build_object(
                                'role_id', role_id, 'factor_key', factor_key,
                                'intensity', intensity, 'rationale', rationale,
                                'validity_status', validity_status))
                               from public.role_context_factors where org_id=p_org_id)),
    'pareto', jsonb_build_object(
      'curves', (select jsonb_agg(jsonb_build_object(
                  'id', id, 'key', key, 'is_cross_validated', is_cross_validated,
                  'cv_method', cv_method, 'sample_size', sample_size,
                  'power_estimate', power_estimate, 'shrinkage_estimate', shrinkage_estimate,
                  'validity_status', validity_status))
                 from public.pareto_curves where org_id=p_org_id),
      'weight_choices', (select jsonb_agg(jsonb_build_object(
                          'id', id, 'curve_id', curve_id,
                          'chosen_weight_validity', chosen_weight_validity,
                          'rationale', rationale, 'validity_status', validity_status))
                         from public.pareto_weight_choices where org_id=p_org_id)),
    'invariance', jsonb_build_object(
      'runs', (select jsonb_agg(jsonb_build_object(
                'id', id, 'instrument_key', instrument_key, 'engine', engine,
                'cutoff_standard', cutoff_standard, 'n_groups', n_groups,
                'validity_status', validity_status))
               from public.invariance_runs where org_id=p_org_id),
      'results', (select jsonb_agg(jsonb_build_object(
                   'run_id', r.run_id, 'level', r.level, 'cfi', r.cfi, 'rmsea', r.rmsea,
                   'delta_cfi_vs_prior_level', r.delta_cfi_vs_prior_level,
                   'passes_cutoff_by_standard', r.passes_cutoff_by_standard,
                   'verdict', r.invariance_verdict_by_expert,
                   'validity_status', r.validity_status))
                  from public.invariance_results r
                  join public.invariance_runs ir on ir.id=r.run_id
                  where ir.org_id=p_org_id)),
    'dif', jsonb_build_object(
      'runs', (select jsonb_agg(jsonb_build_object(
                'id', id, 'instrument_key', instrument_key, 'method', method,
                'engine', engine, 'validity_status', validity_status))
               from public.dif_runs where org_id=p_org_id),
      'flagged_items', (select jsonb_agg(jsonb_build_object(
                         'run_id', i.run_id, 'item_key', i.item_key,
                         'effect_size', i.effect_size, 'p_value', i.p_value,
                         'mh_dif_classification', i.mh_dif_classification,
                         'reviewed_by', i.reviewed_by_person_id,
                         'expert_review_note', i.expert_review_note))
                        from public.dif_items i join public.dif_runs r on r.id=i.run_id
                        where r.org_id=p_org_id and i.bias_review_required=true)),
    'fairness', jsonb_build_object(
      'runs', (select jsonb_agg(jsonb_build_object(
                'id', id, 'key', key, 'engine', engine, 'power_estimate', power_estimate,
                'validity_status', validity_status))
               from public.fairness_runs where org_id=p_org_id),
      'metrics', (select jsonb_agg(jsonb_build_object(
                   'run_id', m.run_id, 'characteristic', m.characteristic,
                   'adverse_impact_ratio', m.adverse_impact_ratio,
                   'slope_test_p_value', m.slope_test_p_value,
                   'intercept_test_p_value', m.intercept_test_p_value,
                   'over_prediction_flag', m.over_prediction_flag,
                   'interpretation_by_expert', m.interpretation_by_expert,
                   'validity_status', m.validity_status))
                  from public.fairness_metrics m
                  join public.fairness_runs r on r.id=m.run_id
                  where r.org_id=p_org_id)),
    'norms', jsonb_build_object(
      'samples', (select jsonb_agg(jsonb_build_object(
                   'id', id, 'instrument_key', instrument_key, 'country_code', country_code,
                   'language_code', language_code, 'sample_n', sample_n,
                   'is_continuous_norming', is_continuous_norming,
                   'continuous_norming_method', continuous_norming_method,
                   'representativeness_notes', representativeness_notes,
                   'validity_status', validity_status))
                  from public.norm_samples where org_id=p_org_id or org_id is null)),
    'models', jsonb_build_object(
      'registry', (select jsonb_agg(jsonb_build_object(
                    'id', id, 'key', key, 'version', version, 'family', family,
                    'validity_status', validity_status))
                   from public.model_registry where org_id=p_org_id),
      'cards', (select jsonb_agg(jsonb_build_object(
                 'model_id', c.model_id, 'intended_use', c.intended_use,
                 'limits_json', c.limits_json, 'data_lineage_json', c.data_lineage_json,
                 'fairness_metrics_json', c.fairness_metrics_json,
                 'monitoring_plan_json', c.monitoring_plan_json,
                 'human_oversight_plan', c.human_oversight_plan,
                 'transparency_disclosures_text', c.transparency_disclosures_text,
                 'ethical_considerations', c.ethical_considerations,
                 'validity_status', c.validity_status))
                from public.model_cards c
                join public.model_registry r on r.id=c.model_id
                where r.org_id=p_org_id)),
    'monitoring', jsonb_build_object(
      -- F9 fix: use `at` not `created_at`
      'runs_in_window',  (select count(*) from public.monitoring_runs where org_id=p_org_id and ran_at between v_from and v_to),
      'alerts_open',     (select count(*) from public.monitoring_alerts where org_id=p_org_id and status in ('open','acknowledged')),
      'incidents_open',  (select count(*) from public.monitoring_incidents where org_id=p_org_id and resolved_at is null),
      'incidents_closed_in_window', (select count(*) from public.monitoring_incidents
                                      where org_id=p_org_id and resolved_at between v_from and v_to)),
    'compliance', jsonb_build_object(
      'artifacts_count', (select count(*) from public.compliance_artifacts where org_id=p_org_id),
      'artifacts_validated', (select count(*) from public.compliance_artifacts where org_id=p_org_id and validity_status='validated'),
      'artifact_kinds', (select jsonb_object_agg(kind, n) from (
                          select kind, count(*) n from public.compliance_artifacts
                          where org_id=p_org_id group by kind) k)),
    'vendor_acknowledgments', (select jsonb_agg(jsonb_build_object(
                                 'vendor_name', vendor_name, 'vendor_role', vendor_role,
                                 'workday_precedent_acknowledged', workday_precedent_acknowledged,
                                 'acknowledgment_text', acknowledgment_text,
                                 'validity_status', validity_status))
                                from public.vendor_acknowledgments where org_id=p_org_id),
    'audit_trail', jsonb_build_object(
      -- F9 fix: column is `at` (NOT `created_at`)
      'events_in_window', (select count(*) from public.audit_log
                            where org_id=p_org_id and at between v_from and v_to),
      'action_summary',   (select jsonb_object_agg(action, n) from (
                            select action, count(*) n from public.audit_log
                            where org_id=p_org_id and at between v_from and v_to
                            group by action) a)),
    'discipline_check', jsonb_build_object(
      'platform_dev_stub_seam_present', true,
      'validated_rows_total', (
        (select count(*) from public.evidence_base_positions where validity_status='validated')
      + (select count(*) from public.predictor_combination_decisions where validity_status='validated' and org_id=p_org_id)
      + (select count(*) from public.personality_role_template_traits where validity_status='validated')
      + (select count(*) from public.trait_activation_factor_catalog where validity_status='validated')
      + (select count(*) from public.role_context_factors where validity_status='validated' and org_id=p_org_id)
      + (select count(*) from public.pareto_curves where validity_status='validated' and org_id=p_org_id)
      + (select count(*) from public.invariance_runs where validity_status='validated' and org_id=p_org_id)
      + (select count(*) from public.dif_runs where validity_status='validated' and org_id=p_org_id)
      + (select count(*) from public.fairness_runs where validity_status='validated' and org_id=p_org_id)
      + (select count(*) from public.norm_samples where validity_status='validated' and (org_id=p_org_id or org_id is null))
      + (select count(*) from public.model_cards where validity_status='validated' and model_id in (select id from public.model_registry where org_id=p_org_id))
      + (select count(*) from public.compliance_artifacts where validity_status='validated' and org_id=p_org_id)
      + (select count(*) from public.vendor_acknowledgments where validity_status='validated' and org_id=p_org_id))));

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
     'Talent lifecycle platform classified high-risk under AI Act Annex III §4(a).')
  returning id into v_artifact_id;

  update public.compliance_artifacts
     set payload_json = payload_json
       || jsonb_build_object('export_metadata',
            (payload_json->'export_metadata') || jsonb_build_object('export_id', v_artifact_id, 'export_id_pending', false))
   where id = v_artifact_id;

  perform public.audit_log_event(
    p_org_id, 'annex_iv.export', 'compliance_artifact', v_artifact_id, null,
    jsonb_build_object('generated_by', v_caller, 'date_from', v_from, 'date_to', v_to), null);

  return jsonb_build_object('ok', true, 'artifact_id', v_artifact_id, 'org_id', p_org_id,
    'validity_status', 'dev_stub',
    'note', 'Promote to validated via rpc_compliance_artifact_signoff_modeling THEN rpc_compliance_artifact_signoff_legal.');
end;
$$;

revoke all on function public.rpc_annex_iv_export(uuid, timestamptz, timestamptz) from public;
grant execute on function public.rpc_annex_iv_export(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- ─── F10 [CRITICAL]: monitoring_alerts pre-existing CHECKs blocked
-- 'suppressed' status and allowed 'high' severity. Drop the originals.
alter table public.monitoring_alerts drop constraint if exists monitoring_alerts_severity_check;
alter table public.monitoring_alerts drop constraint if exists monitoring_alerts_status_check;
-- (My ma_severity_enum and ma_status_enum from h8 are now the only CHECKs.)

-- ─── F11 [CRITICAL]: model_cards CHECK toothless on jsonb defaults
-- fairness_metrics_json defaults to '{}'::jsonb NOT NULL. The check
-- `is not null` always passes. Replace with `<> '{}'::jsonb` to match
-- the pattern already used for limits_json / data_lineage_json.
alter table public.model_cards drop constraint if exists mc_validated_requires_full;
alter table public.model_cards
  add constraint mc_validated_requires_full check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and intended_use is not null and length(intended_use) >= 100
      and limits_json is not null and limits_json <> '{}'::jsonb
      and data_lineage_json is not null and data_lineage_json <> '{}'::jsonb
      and fairness_metrics_json is not null and fairness_metrics_json <> '{}'::jsonb
      and ethical_considerations is not null and length(ethical_considerations) >= 100
      and human_oversight_plan is not null and length(human_oversight_plan) >= 30
      and transparency_disclosures_text is not null and length(transparency_disclosures_text) >= 30
      and monitoring_plan_json is not null and monitoring_plan_json <> '{}'::jsonb
      and signed_off_by is not null
      and signed_off_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    ));

-- ─── F1 [HIGH]: vendor_acknowledgments policy/RPC scope mismatch ────
drop policy if exists va_write_legal   on public.vendor_acknowledgments;
drop policy if exists va_update_legal  on public.vendor_acknowledgments;
drop policy if exists va_delete_legal  on public.vendor_acknowledgments;
drop policy if exists va_insert_modeling_or_legal on public.vendor_acknowledgments;
drop policy if exists va_update_modeling_or_legal on public.vendor_acknowledgments;

create policy va_insert_modeling_or_legal on public.vendor_acknowledgments
  for insert with check (
    public.has_permission(org_id, 'modeling.write')
    or public.has_permission(org_id, 'legal.signoff')
  );

create policy va_update_modeling_or_legal on public.vendor_acknowledgments
  for update
  using (public.has_permission(org_id, 'modeling.write')
         or public.has_permission(org_id, 'legal.signoff'))
  with check (public.has_permission(org_id, 'modeling.write')
              or public.has_permission(org_id, 'legal.signoff'));

create policy va_delete_legal on public.vendor_acknowledgments
  for delete using (public.has_permission(org_id, 'legal.signoff'));

-- ─── F4 [HIGH]: DELETE policies on 2 more H-2 tables ─────────────────
drop policy if exists tafc_delete_modeling on public.trait_activation_factor_catalog;
create policy tafc_delete_modeling on public.trait_activation_factor_catalog
  for delete using (public.has_global_permission('modeling.write'));

drop policy if exists rcf_delete_role on public.role_context_factors;
create policy rcf_delete_role on public.role_context_factors
  for delete using (public.has_permission(org_id, 'role.create'));

-- ─── F5 [MEDIUM]: trigger should NOT be SECDEF ──────────────────────
create or replace function public._dif_set_bias_review_required()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if (TG_OP = 'INSERT')
     or (new.mh_dif_classification is distinct from old.mh_dif_classification) then
    new.bias_review_required := (new.mh_dif_classification in ('B','C'));
  end if;
  return new;
end;
$$;

-- ─── F6 [MEDIUM]: audit triggers on 8 new tables ────────────────────
do $$
declare t text;
begin
  foreach t in array array[
    'citations','evidence_base_positions','evidence_base_position_citations',
    'predictor_combination_decisions','trait_activation_factor_catalog',
    'role_context_factors','norm_sample_adaptations','vendor_acknowledgments'
  ] loop
    execute format('drop trigger if exists trg_audit_%I on public.%I', t, t);
    execute format(
      'create trigger trg_audit_%I after insert or update or delete on public.%I for each row execute function public._audit_row()',
      t, t);
  end loop;
end$$;

-- ─── F7 [MEDIUM]: signoff UPDATE policies on existing tables ────────
-- Not currently exploitable (function owner bypasses RLS) but latent
-- fragility — if function ownership ever changes, signoff RPCs would
-- silently no-op without these policies.
drop policy if exists model_cards_signoff_update on public.model_cards;
create policy model_cards_signoff_update on public.model_cards
  for update
  using (exists (select 1 from public.model_registry r
                  where r.id = model_cards.model_id
                    and public.has_permission(r.org_id, 'modeling.signoff')))
  with check (exists (select 1 from public.model_registry r
                       where r.id = model_cards.model_id
                         and public.has_permission(r.org_id, 'modeling.signoff')));

drop policy if exists norm_percentiles_signoff_update on public.norm_percentiles;
create policy norm_percentiles_signoff_update on public.norm_percentiles
  for update
  using (exists (select 1 from public.norm_samples s
                  where s.id = norm_percentiles.sample_id
                    and ((s.org_id is null and public.has_global_permission('modeling.signoff'))
                         or public.has_permission(s.org_id, 'modeling.signoff'))))
  with check (exists (select 1 from public.norm_samples s
                       where s.id = norm_percentiles.sample_id
                         and ((s.org_id is null and public.has_global_permission('modeling.signoff'))
                              or public.has_permission(s.org_id, 'modeling.signoff'))));

drop policy if exists pareto_curves_signoff_update on public.pareto_curves;
create policy pareto_curves_signoff_update on public.pareto_curves
  for update
  using (public.has_permission(org_id, 'modeling.signoff'))
  with check (public.has_permission(org_id, 'modeling.signoff'));

drop policy if exists pareto_weight_choices_signoff_update on public.pareto_weight_choices;
create policy pareto_weight_choices_signoff_update on public.pareto_weight_choices
  for update
  using (public.has_permission(org_id, 'modeling.signoff'))
  with check (public.has_permission(org_id, 'modeling.signoff'));

drop policy if exists compliance_artifacts_signoff_update on public.compliance_artifacts;
create policy compliance_artifacts_signoff_update on public.compliance_artifacts
  for update
  using (public.has_permission(org_id, 'modeling.signoff')
         or public.has_permission(org_id, 'legal.signoff'))
  with check (public.has_permission(org_id, 'modeling.signoff')
              or public.has_permission(org_id, 'legal.signoff'));

drop policy if exists personality_role_template_traits_signoff_update on public.personality_role_template_traits;
create policy personality_role_template_traits_signoff_update on public.personality_role_template_traits
  for update
  using ((org_id is null and public.has_global_permission('modeling.signoff'))
         or public.has_permission(org_id, 'role.signoff'))
  with check ((org_id is null and public.has_global_permission('modeling.signoff'))
              or public.has_permission(org_id, 'role.signoff'));

-- ─── F14 [HIGH]: explicit FK ON DELETE for citation FKs ─────────────
-- Default NO ACTION silently errors on referenced-row delete. Be explicit:
--   primary_citation_id → SET NULL (we keep the position; citation removal
--     means the position becomes "uncited" until a new one is set)
--   evidence_base_position_citations.citation_id → CASCADE (the link row
--     has no meaning without its citation)
--   norm_sample_adaptations.citation_id → CASCADE (same)
alter table public.evidence_base_positions
  drop constraint if exists evidence_base_positions_primary_citation_id_fkey;
alter table public.evidence_base_positions
  add constraint evidence_base_positions_primary_citation_id_fkey
  foreign key (primary_citation_id) references public.citations(id) on delete set null;

alter table public.evidence_base_position_citations
  drop constraint if exists evidence_base_position_citations_citation_id_fkey;
alter table public.evidence_base_position_citations
  add constraint evidence_base_position_citations_citation_id_fkey
  foreign key (citation_id) references public.citations(id) on delete cascade;

alter table public.norm_sample_adaptations
  drop constraint if exists norm_sample_adaptations_citation_id_fkey;
alter table public.norm_sample_adaptations
  add constraint norm_sample_adaptations_citation_id_fkey
  foreign key (citation_id) references public.citations(id) on delete cascade;

alter table public.trait_activation_factor_catalog
  drop constraint if exists trait_activation_factor_catalog_primary_citation_id_fkey;
alter table public.trait_activation_factor_catalog
  add constraint trait_activation_factor_catalog_primary_citation_id_fkey
  foreign key (primary_citation_id) references public.citations(id) on delete set null;

-- ─── F15 [HIGH]: nil UUID sentinel collision ────────────────────────
-- The partial unique index uses COALESCE(role_id, nil_uuid) as the
-- NULL-equivalence trick. If anyone legitimately uses nil_uuid as a
-- real role_id, the trick breaks. Reserve nil_uuid as a sentinel.
alter table public.predictor_combination_decisions
  drop constraint if exists pcd_no_nil_uuid_role_id,
  drop constraint if exists pcd_no_nil_uuid_requisition_id;
alter table public.predictor_combination_decisions
  add constraint pcd_no_nil_uuid_role_id check (
    role_id is null or role_id <> '00000000-0000-0000-0000-000000000000'::uuid),
  add constraint pcd_no_nil_uuid_requisition_id check (
    requisition_id is null or requisition_id <> '00000000-0000-0000-0000-000000000000'::uuid);

-- ─── F8 [HIGH]: pareto curve / weight_choice locking ────────────────
--   (curve_signoff already uses FOR UPDATE on the curve)
--   (weight_choice_signoff didn't lock the underlying curve; F2 fix
--    below recreates it with `FOR SHARE`)

-- ─── F2 [HIGH] + F3 [HIGH] + F12 [CRITICAL]: signoff RPCs need
-- org.read precheck (F2), incident cross-org fairness check (F3),
-- NULL-org branch for global invariance/DIF runs (F12), AND F13
-- result-row lock to prevent racy non-validated child INSERTs.

-- F2 + global-vs-org branching helper:
-- (rpc_position_signoff already uses null org for audit, so no change beyond what we have.)
create or replace function public.rpc_position_signoff(
  p_position_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.evidence_base_positions%rowtype;
begin
  if not public.has_global_permission('modeling.signoff') then
    raise exception 'denied: modeling.signoff required' using errcode='42501';
  end if;
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 50 then
    raise exception 'rationale must be at least 50 characters' using errcode='22023';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  select * into v_row from public.evidence_base_positions where id = p_position_id for update;
  if not found then raise exception 'evidence_base_position % not found', p_position_id using errcode='P0002'; end if;
  if v_row.validity_anchor is null then
    raise exception 'cannot sign off: validity_anchor is null' using errcode='22023';
  end if;
  update public.evidence_base_positions
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_position_id;
  perform public.audit_log_event(
    null, 'evidence_base_position.signoff', 'evidence_base_position', p_position_id,
    to_jsonb(v_row),
    jsonb_build_object('validity_status','validated',
      'signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'previous_status', v_row.validity_status,
      'previous_dev_stub', v_row._dev_stub), null);
  return jsonb_build_object('ok', true, 'position_id', p_position_id,
    'predictor_type', v_row.predictor_type, 'version_id', v_row.version_id,
    'validity_status', 'validated',
    'signoff_actor_id', v_caller_person_id, 'signoff_at', now());
end;
$$;

create or replace function public.rpc_predictor_combo_signoff(
  p_combo_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.predictor_combination_decisions%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.predictor_combination_decisions where id = p_combo_id for update;
  if not found then raise exception 'predictor_combination_decision % not found', p_combo_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.predictor_combination_decisions
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_combo_id;
  perform public.audit_log_event(
    v_row.org_id, 'predictor_combo.signoff', 'predictor_combination_decision', p_combo_id,
    to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'previous_status', v_row.validity_status, 'previous_dev_stub', v_row._dev_stub), null);
  return jsonb_build_object('ok', true, 'id', p_combo_id, 'validity_status','validated',
    'signoff_actor_id', v_caller_person_id);
end;
$$;

create or replace function public.rpc_pareto_curve_signoff(
  p_curve_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.pareto_curves%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.pareto_curves where id = p_curve_id for update;
  if not found then raise exception 'pareto_curve % not found', p_curve_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  if v_row.is_cross_validated is not true then
    raise exception 'cannot sign off uncross-validated curve (Song 2017)' using errcode='22023';
  end if;
  if v_row.power_estimate is null then
    raise exception 'cannot sign off curve without power_estimate (Aguinis 2010)' using errcode='22023';
  end if;
  update public.pareto_curves
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_curve_id;
  perform public.audit_log_event(
    v_row.org_id, 'pareto_curve.signoff', 'pareto_curve', p_curve_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'cv_method', v_row.cv_method, 'cv_fold_count', v_row.cv_fold_count,
      'sample_size', v_row.sample_size, 'power_estimate', v_row.power_estimate,
      'shrinkage_estimate', v_row.shrinkage_estimate), null);
  return jsonb_build_object('ok', true, 'curve_id', p_curve_id,
    'validity_status', 'validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

create or replace function public.rpc_pareto_weight_choice_signoff(
  p_choice_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.pareto_weight_choices%rowtype; v_curve public.pareto_curves%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.pareto_weight_choices where id = p_choice_id for update;
  if not found then raise exception 'pareto_weight_choice % not found', p_choice_id using errcode='P0002'; end if;
  -- F8: take FOR SHARE on the underlying curve to prevent concurrent demotion
  select * into v_curve from public.pareto_curves where id = v_row.curve_id for share;
  if v_curve.validity_status <> 'validated' then
    raise exception 'cannot sign off weight choice when underlying curve is not validated (curve status=%)',
      v_curve.validity_status using errcode='22023';
  end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.pareto_weight_choices
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale
   where id = p_choice_id;
  perform public.audit_log_event(
    v_row.org_id, 'pareto_weight_choice.signoff', 'pareto_weight_choice', p_choice_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'chosen_weight_validity', v_row.chosen_weight_validity,
      'underlying_curve_id', v_row.curve_id), null);
  return jsonb_build_object('ok', true, 'choice_id', p_choice_id,
    'validity_status', 'validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

-- F12 + F13: invariance/dif/fairness run signoff
-- F12: branch on NULL org_id (global runs use has_global_permission)
-- F13: lock child result rows to prevent concurrent INSERTs from
--      landing non-validated children in a "validated" run

create or replace function public.rpc_invariance_run_signoff(
  p_run_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.invariance_runs%rowtype; v_n_results int; v_n_with_verdict int;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.invariance_runs where id = p_run_id for update;
  if not found then raise exception 'invariance_run % not found', p_run_id using errcode='P0002'; end if;
  -- F12: branch on NULL org_id
  if v_row.org_id is null then
    if not public.has_global_permission('modeling.signoff') then
      raise exception 'denied: modeling.signoff required (global run)' using errcode='42501';
    end if;
  else
    if not public.has_permission(v_row.org_id, 'modeling.signoff') then
      raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
    end if;
    if not public.has_permission(v_row.org_id, 'org.read') then
      raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
    end if;
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  if v_row.engine is null then raise exception 'cannot sign off run without engine metadata' using errcode='22023'; end if;
  if v_row.cutoff_standard is null then raise exception 'cannot sign off run without cutoff_standard' using errcode='22023'; end if;
  -- F13: lock all result rows so no concurrent INSERT lands a non-validated child
  perform 1 from public.invariance_results where run_id = p_run_id for update;
  select count(*), count(*) filter (where invariance_verdict_by_expert is not null)
    into v_n_results, v_n_with_verdict from public.invariance_results where run_id = p_run_id;
  if v_n_results = 0 then raise exception 'cannot sign off run with 0 result rows' using errcode='22023'; end if;
  if v_n_with_verdict <> v_n_results then
    raise exception 'cannot sign off run: only % of % result rows have an expert verdict',
      v_n_with_verdict, v_n_results using errcode='22023';
  end if;
  update public.invariance_runs
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale
   where id = p_run_id;
  update public.invariance_results
     set validity_status='validated', _dev_stub=false
   where run_id = p_run_id;
  perform public.audit_log_event(
    v_row.org_id, 'invariance_run.signoff', 'invariance_run', p_run_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'engine', v_row.engine, 'cutoff_standard', v_row.cutoff_standard,
      'n_results', v_n_results), null);
  return jsonb_build_object('ok', true, 'run_id', p_run_id,
    'validity_status', 'validated', 'n_results_validated', v_n_results,
    'signoff_actor_id', v_caller_person_id);
end;
$$;

create or replace function public.rpc_dif_run_signoff(
  p_run_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.dif_runs%rowtype; v_n_items int; v_n_unreviewed int;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.dif_runs where id = p_run_id for update;
  if not found then raise exception 'dif_run % not found', p_run_id using errcode='P0002'; end if;
  -- F12: branch on NULL org_id
  if v_row.org_id is null then
    if not public.has_global_permission('modeling.signoff') then
      raise exception 'denied: modeling.signoff required (global run)' using errcode='42501';
    end if;
  else
    if not public.has_permission(v_row.org_id, 'modeling.signoff') then
      raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
    end if;
    if not public.has_permission(v_row.org_id, 'org.read') then
      raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
    end if;
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  if v_row.engine is null or v_row.method is null then
    raise exception 'cannot sign off run without engine + method metadata' using errcode='22023';
  end if;
  -- F13: lock all item rows to prevent racy unreviewed INSERTs
  perform 1 from public.dif_items where run_id = p_run_id for update;
  select count(*) filter (where bias_review_required = true),
         count(*) filter (where bias_review_required = true and reviewed_by_person_id is null)
    into v_n_items, v_n_unreviewed from public.dif_items where run_id = p_run_id;
  if v_n_unreviewed > 0 then
    raise exception 'cannot sign off run: % of % flagged items lack expert review',
      v_n_unreviewed, v_n_items using errcode='22023';
  end if;
  update public.dif_runs
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale
   where id = p_run_id;
  update public.dif_items set validity_status='validated', _dev_stub=false where run_id = p_run_id;
  perform public.audit_log_event(
    v_row.org_id, 'dif_run.signoff', 'dif_run', p_run_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'engine', v_row.engine, 'method', v_row.method, 'n_flagged_items', v_n_items), null);
  return jsonb_build_object('ok', true, 'run_id', p_run_id,
    'validity_status', 'validated', 'n_flagged_items', v_n_items,
    'signoff_actor_id', v_caller_person_id);
end;
$$;

create or replace function public.rpc_fairness_run_signoff(
  p_run_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.fairness_runs%rowtype; v_n_metrics int; v_n_unreviewed int;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.fairness_runs where id = p_run_id for update;
  if not found then raise exception 'fairness_run % not found', p_run_id using errcode='P0002'; end if;
  -- fairness_runs.org_id is NOT NULL so no branch needed
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  if v_row.power_estimate is null then
    raise exception 'cannot sign off run without power_estimate (Aguinis 2010)' using errcode='22023';
  end if;
  -- F13: lock metric rows
  perform 1 from public.fairness_metrics where run_id = p_run_id for update;
  select count(*), count(*) filter (where interpretation_by_expert is null)
    into v_n_metrics, v_n_unreviewed from public.fairness_metrics where run_id = p_run_id;
  if v_n_metrics = 0 then raise exception 'cannot sign off run with 0 metric rows' using errcode='22023'; end if;
  if v_n_unreviewed > 0 then
    raise exception 'cannot sign off run: % of % metrics lack expert interpretation',
      v_n_unreviewed, v_n_metrics using errcode='22023';
  end if;
  update public.fairness_runs
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_run_id;
  update public.fairness_metrics set validity_status='validated', _dev_stub=false where run_id = p_run_id;
  perform public.audit_log_event(
    v_row.org_id, 'fairness_run.signoff', 'fairness_run', p_run_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'engine', v_row.engine, 'power_estimate', v_row.power_estimate,
      'n_metrics', v_n_metrics), null);
  return jsonb_build_object('ok', true, 'run_id', p_run_id,
    'validity_status', 'validated', 'n_metrics_validated', v_n_metrics,
    'signoff_actor_id', v_caller_person_id);
end;
$$;

create or replace function public.rpc_norm_sample_signoff(
  p_sample_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.norm_samples%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.norm_samples where id = p_sample_id for update;
  if not found then raise exception 'norm_sample % not found', p_sample_id using errcode='P0002'; end if;
  if v_row.org_id is null then
    if not public.has_global_permission('modeling.signoff') then
      raise exception 'denied: modeling.signoff required (global norm sample)' using errcode='42501';
    end if;
  else
    if not public.has_permission(v_row.org_id, 'modeling.signoff') then
      raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
    end if;
    if not public.has_permission(v_row.org_id, 'org.read') then
      raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
    end if;
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  if v_row.sample_n is null or v_row.sample_n < 100 then
    raise exception 'cannot sign off sample with N=% (<100)', v_row.sample_n using errcode='22023';
  end if;
  if v_row.representativeness_notes is null then
    raise exception 'cannot sign off sample without representativeness_notes' using errcode='22023';
  end if;
  update public.norm_samples
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_sample_id;
  -- F-norm collapsed: single UPDATE on percentiles
  update public.norm_percentiles
     set validity_status='validated', _dev_stub=false
   where sample_id = p_sample_id;
  perform public.audit_log_event(
    v_row.org_id, 'norm_sample.signoff', 'norm_sample', p_sample_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'sample_n', v_row.sample_n, 'country_code', v_row.country_code,
      'is_continuous_norming', v_row.is_continuous_norming), null);
  return jsonb_build_object('ok', true, 'sample_id', p_sample_id,
    'validity_status', 'validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

create or replace function public.rpc_model_card_signoff(
  p_card_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_card public.model_cards%rowtype; v_model public.model_registry%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_card from public.model_cards where id = p_card_id for update;
  if not found then raise exception 'model_card % not found', p_card_id using errcode='P0002'; end if;
  select * into v_model from public.model_registry where id = v_card.model_id for share;
  if v_model.id is null then raise exception 'model_card has orphan model_id' using errcode='P0002'; end if;
  if not public.has_permission(v_model.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_model.org_id using errcode='42501';
  end if;
  if not public.has_permission(v_model.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  if v_card.intended_use is null or length(v_card.intended_use) < 100 then
    raise exception 'intended_use must be >=100 chars for validated card' using errcode='22023'; end if;
  if v_card.ethical_considerations is null or length(v_card.ethical_considerations) < 100 then
    raise exception 'ethical_considerations must be >=100 chars' using errcode='22023'; end if;
  if v_card.human_oversight_plan is null then
    raise exception 'human_oversight_plan required (AI Act Art. 14)' using errcode='22023'; end if;
  if v_card.transparency_disclosures_text is null then
    raise exception 'transparency_disclosures_text required (AI Act Art. 13)' using errcode='22023'; end if;
  if v_card.monitoring_plan_json is null or v_card.monitoring_plan_json = '{}'::jsonb then
    raise exception 'monitoring_plan_json required and non-empty' using errcode='22023'; end if;
  if v_card.fairness_metrics_json is null or v_card.fairness_metrics_json = '{}'::jsonb then
    raise exception 'fairness_metrics_json required and non-empty' using errcode='22023'; end if;
  if v_card.limits_json is null or v_card.limits_json = '{}'::jsonb then
    raise exception 'limits_json required and non-empty' using errcode='22023'; end if;
  if v_card.data_lineage_json is null or v_card.data_lineage_json = '{}'::jsonb then
    raise exception 'data_lineage_json required and non-empty' using errcode='22023'; end if;
  update public.model_cards
     set validity_status='validated', _dev_stub=false,
         signed_off_by=v_caller_person_id, signed_off_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_card_id;
  perform public.audit_log_event(
    v_model.org_id, 'model_card.signoff', 'model_card', p_card_id, to_jsonb(v_card),
    jsonb_build_object('signed_off_by', v_caller_person_id, 'signed_off_at', now(),
      'rationale_length', length(p_decision_rationale), 'model_id', v_card.model_id), null);
  return jsonb_build_object('ok', true, 'card_id', p_card_id,
    'validity_status', 'validated', 'signed_off_by', v_caller_person_id);
end;
$$;

create or replace function public.rpc_role_context_signoff(
  p_role_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_org_id uuid; v_n_rows int;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 50 then
    raise exception 'rationale must be at least 50 characters' using errcode='22023';
  end if;
  select rc.org_id into v_org_id from public.roles_catalog rc where rc.id=p_role_id;
  if v_org_id is null then
    raise exception 'role % not found or has no org', p_role_id using errcode='P0002';
  end if;
  if not public.has_permission(v_org_id, 'role.signoff') then
    raise exception 'denied: role.signoff required in org %', v_org_id using errcode='42501';
  end if;
  if not public.has_permission(v_org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  with upd as (
    update public.role_context_factors
       set validity_status='validated', _dev_stub=false,
           signoff_actor_id=v_caller_person_id, signoff_at=now(),
           signoff_rationale=p_decision_rationale, updated_at=now()
     where role_id=p_role_id and validity_status <> 'validated'
    returning 1)
  select count(*) into v_n_rows from upd;
  perform public.audit_log_event(v_org_id, 'role_context.signoff', 'role_context_factors', null,
    null,
    jsonb_build_object('role_id', p_role_id, 'n_rows_validated', v_n_rows,
      'signoff_actor_id', v_caller_person_id,
      'rationale_length', length(p_decision_rationale)), null);
  return jsonb_build_object('ok', true, 'role_id', p_role_id,
    'n_rows_validated', v_n_rows, 'signoff_actor_id', v_caller_person_id);
end;
$$;

create or replace function public.rpc_monitoring_alert_acknowledge(
  p_alert_id uuid, p_note text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.monitoring_alerts%rowtype;
begin
  select * into v_row from public.monitoring_alerts where id = p_alert_id for update;
  if not found then raise exception 'alert % not found', p_alert_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'modeling.read') then
    raise exception 'denied: modeling.read required in org %', v_row.org_id using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  if v_row.status <> 'open' then
    raise exception 'alert is % (only open alerts can be acknowledged)', v_row.status using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.monitoring_alerts
     set status='acknowledged', acknowledged_by=v_caller, acknowledged_at=now(),
         ack_note=p_note, updated_at=now()
   where id = p_alert_id;
  perform public.audit_log_event(
    v_row.org_id, 'monitoring_alert.ack', 'monitoring_alert', p_alert_id, to_jsonb(v_row),
    jsonb_build_object('acknowledged_by', v_caller, 'note', p_note), null);
  return jsonb_build_object('ok', true, 'alert_id', p_alert_id, 'status', 'acknowledged');
end;
$$;

create or replace function public.rpc_monitoring_alert_resolve(
  p_alert_id uuid, p_note text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.monitoring_alerts%rowtype;
begin
  if p_note is null or length(trim(p_note)) < 20 then
    raise exception 'resolve note must be at least 20 characters' using errcode='22023';
  end if;
  select * into v_row from public.monitoring_alerts where id = p_alert_id for update;
  if not found then raise exception 'alert % not found', p_alert_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'modeling.write') then
    raise exception 'denied: modeling.write required' using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  if v_row.status not in ('open','acknowledged') then
    raise exception 'alert is % (cannot resolve)', v_row.status using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.monitoring_alerts
     set status='resolved', resolved_by=v_caller, resolved_at=now(),
         resolve_note=p_note, updated_at=now()
   where id = p_alert_id;
  perform public.audit_log_event(
    v_row.org_id, 'monitoring_alert.resolve', 'monitoring_alert', p_alert_id, to_jsonb(v_row),
    jsonb_build_object('resolved_by', v_caller, 'note', p_note), null);
  return jsonb_build_object('ok', true, 'alert_id', p_alert_id, 'status', 'resolved');
end;
$$;

-- F3: incident close cross-org fairness_run check
create or replace function public.rpc_monitoring_incident_close(
  p_incident_id uuid, p_resolution_note text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.monitoring_incidents%rowtype; v_fr_org uuid;
begin
  if p_resolution_note is null or length(trim(p_resolution_note)) < 50 then
    raise exception 'resolution note must be at least 50 characters' using errcode='22023';
  end if;
  select * into v_row from public.monitoring_incidents where id = p_incident_id for update;
  if not found then raise exception 'incident % not found', p_incident_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required to close incidents' using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  if v_row.bias_reaudit_fairness_run_id is null then
    raise exception 'cannot close incident without bias_reaudit_fairness_run_id linkage' using errcode='22023';
  end if;
  -- F3: verify the linked fairness_run is from the SAME org as the incident
  select fr.org_id into v_fr_org
    from public.fairness_runs fr where fr.id = v_row.bias_reaudit_fairness_run_id;
  if v_fr_org is null then
    raise exception 'bias_reaudit_fairness_run_id % not found', v_row.bias_reaudit_fairness_run_id
      using errcode='22023';
  end if;
  if v_fr_org <> v_row.org_id then
    raise exception 'bias_reaudit_fairness_run_id belongs to org %, incident belongs to org % — cross-org link rejected',
      v_fr_org, v_row.org_id using errcode='42501';
  end if;
  if v_row.resolved_at is not null then
    raise exception 'incident already closed at %', v_row.resolved_at using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.monitoring_incidents
     set resolved_at=now(), resolved_by=v_caller, resolution_note=p_resolution_note,
         updated_at=now()
   where id = p_incident_id;
  perform public.audit_log_event(
    v_row.org_id, 'monitoring_incident.close', 'monitoring_incident', p_incident_id, to_jsonb(v_row),
    jsonb_build_object('resolved_by', v_caller, 'note', p_resolution_note,
      'bias_reaudit_fairness_run_id', v_row.bias_reaudit_fairness_run_id), null);
  return jsonb_build_object('ok', true, 'incident_id', p_incident_id, 'closed', true);
end;
$$;

create or replace function public.rpc_factor_catalog_signoff(
  p_factor_key text, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.trait_activation_factor_catalog%rowtype;
begin
  if not public.has_global_permission('modeling.signoff') then
    raise exception 'denied: modeling.signoff required' using errcode='42501';
  end if;
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 50 then
    raise exception 'rationale must be at least 50 characters' using errcode='22023';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  select * into v_row from public.trait_activation_factor_catalog where factor_key=p_factor_key for update;
  if not found then raise exception 'factor % not found', p_factor_key using errcode='P0002'; end if;
  update public.trait_activation_factor_catalog
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where factor_key=p_factor_key;
  perform public.audit_log_event(null, 'trait_factor.signoff', 'trait_activation_factor_catalog', v_row.id,
    to_jsonb(v_row),
    jsonb_build_object('factor_key', p_factor_key, 'signoff_actor_id', v_caller_person_id,
      'rationale_length', length(p_decision_rationale)), null);
  return jsonb_build_object('ok', true, 'factor_key', p_factor_key,
    'validity_status','validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

create or replace function public.rpc_trait_direction_signoff(
  p_trait_row_id bigint, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller_person_id uuid; v_row public.personality_role_template_traits%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 50 then
    raise exception 'rationale must be at least 50 characters' using errcode='22023';
  end if;
  select * into v_row from public.personality_role_template_traits where id = p_trait_row_id for update;
  if not found then raise exception 'trait row % not found', p_trait_row_id using errcode='P0002'; end if;
  if v_row.org_id is null then
    if not public.has_global_permission('modeling.signoff') then
      raise exception 'denied: modeling.signoff required (global template)' using errcode='42501';
    end if;
  else
    if not public.has_permission(v_row.org_id, 'role.signoff') then
      raise exception 'denied: role.signoff required in org %', v_row.org_id using errcode='42501';
    end if;
    if not public.has_permission(v_row.org_id, 'org.read') then
      raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
    end if;
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.personality_role_template_traits
     set validity_status='validated', _dev_stub=false,
         direction_signoff_actor_id=v_caller_person_id,
         direction_signoff_at=now(),
         direction_signoff_rationale=p_decision_rationale,
         updated_at=now()
   where id = p_trait_row_id;
  perform public.audit_log_event(
    v_row.org_id, 'trait_direction.signoff', 'personality_role_template_trait', null,
    to_jsonb(v_row),
    jsonb_build_object('trait_row_id', p_trait_row_id, 'role_key', v_row.role_key,
      'trait_key', v_row.trait_key, 'direction', v_row.direction,
      'signoff_actor_id', v_caller_person_id, 'rationale_length', length(p_decision_rationale)),
    null);
  return jsonb_build_object('ok', true, 'trait_row_id', p_trait_row_id,
    'validity_status','validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

create or replace function public.rpc_compliance_artifact_signoff_modeling(
  p_artifact_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.compliance_artifacts%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.compliance_artifacts where id = p_artifact_id for update;
  if not found then raise exception 'artifact % not found', p_artifact_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.compliance_artifacts
     set modeling_signoff_actor_id=v_caller, modeling_signoff_at=now(),
         modeling_signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_artifact_id;
  perform public.audit_log_event(
    v_row.org_id, 'compliance_artifact.signoff_modeling', 'compliance_artifact', p_artifact_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller, 'rationale_length', length(p_decision_rationale),
      'kind', v_row.kind), null);
  return jsonb_build_object('ok', true, 'artifact_id', p_artifact_id,
    'modeling_signoff_actor_id', v_caller);
end;
$$;

create or replace function public.rpc_compliance_artifact_signoff_legal(
  p_artifact_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.compliance_artifacts%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.compliance_artifacts where id = p_artifact_id for update;
  if not found then raise exception 'artifact % not found', p_artifact_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'legal.signoff') then
    raise exception 'denied: legal.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  if v_row.modeling_signoff_actor_id is null then
    raise exception 'modeling sign-off must complete before legal sign-off' using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.compliance_artifacts
     set legal_signoff_actor_id=v_caller, legal_signoff_at=now(),
         legal_signoff_rationale=p_decision_rationale,
         validity_status='validated', _dev_stub=false,
         signed_off_by=v_caller, signed_off_at=now(),
         sign_off_status='signed',
         attestation_text=coalesce(v_row.attestation_text, p_decision_rationale),
         updated_at=now()
   where id = p_artifact_id;
  perform public.audit_log_event(
    v_row.org_id, 'compliance_artifact.signoff_legal', 'compliance_artifact', p_artifact_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller, 'rationale_length', length(p_decision_rationale),
      'kind', v_row.kind, 'promoted_to_validated', true), null);
  return jsonb_build_object('ok', true, 'artifact_id', p_artifact_id,
    'validity_status', 'validated', 'legal_signoff_actor_id', v_caller);
end;
$$;

create or replace function public.rpc_vendor_acknowledgment_signoff(
  p_id uuid, p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_caller uuid; v_row public.vendor_acknowledgments%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.vendor_acknowledgments where id = p_id for update;
  if not found then raise exception 'acknowledgment % not found', p_id using errcode='P0002'; end if;
  if not public.has_permission(v_row.org_id, 'legal.signoff') then
    raise exception 'denied: legal.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  if not public.has_permission(v_row.org_id, 'org.read') then
    raise exception 'denied: org.read required (audit pre-check)' using errcode='42501';
  end if;
  if v_row.workday_precedent_acknowledged is not true then
    raise exception 'workday_precedent_acknowledged must be true before sign-off' using errcode='22023';
  end if;
  select pp.id into v_caller from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller is null then raise exception 'caller has no person identity' using errcode='42501'; end if;
  update public.vendor_acknowledgments
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_id;
  perform public.audit_log_event(
    v_row.org_id, 'vendor_acknowledgment.signoff', 'vendor_acknowledgment', p_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller, 'vendor_name', v_row.vendor_name,
      'rationale_length', length(p_decision_rationale)), null);
  return jsonb_build_object('ok', true, 'id', p_id,
    'validity_status', 'validated', 'signoff_actor_id', v_caller);
end;
$$;

-- ─── F16 [MEDIUM]: norm_percentiles validity_status without seam ────
-- Run 9 added validity_status to norm_percentiles but no _dev_stub /
-- no CHECK enforcing dev_stub-to-validated. Add both so the seam
-- discipline holds end-to-end.
alter table public.norm_percentiles
  add column if not exists _dev_stub boolean not null default true;

alter table public.norm_percentiles
  drop constraint if exists np_validated_requires_dev_stub_false;
alter table public.norm_percentiles
  add constraint np_validated_requires_dev_stub_false check (
    validity_status <> 'validated' or coalesce(_dev_stub, true) = false);

-- ─── F17 [MEDIUM]: dif_classify_mh — ETS 1.5 edge ───────────────────
-- Per Zwick 1995 ETS classification:
--   A: |Δ| < 1.0
--   B: 1.0 <= |Δ| <= 1.5  AND significant chi²
--   C: |Δ| > 1.5
-- My original used `< 1.5` which classifies exactly 1.5 as C. Fix to `<=`.
-- Null p-value defaults to 'B' (conservative — treat as significant).
create or replace function public.dif_classify_mh(
  p_effect_size numeric, p_p_value numeric
) returns text language plpgsql immutable set search_path = '' as $$
begin
  if p_effect_size is null then return null; end if;
  if abs(p_effect_size) < 1.0 then return 'A'; end if;
  if abs(p_effect_size) <= 1.5 then
    -- B requires significance; null p-value defaults to B (conservative)
    if p_p_value is null or p_p_value < 0.05 then return 'B'; else return 'A'; end if;
  end if;
  return 'C';
end;
$$;

-- ─── F18 [MEDIUM]: invariance_evaluate_cutoffs explicit nulls ──────
-- Return explicit nulls (not missing keys) when inputs are null so
-- consumers don't have to distinguish "didn't compute" from "doesn't
-- apply this standard".
create or replace function public.invariance_evaluate_cutoffs(
  p_delta_cfi numeric, p_delta_rmsea numeric
) returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_cr   boolean := null;
  v_meade boolean := null;
  v_chen  boolean := null;
begin
  if p_delta_cfi is not null then
    v_cr    := (p_delta_cfi >= -0.010);
    v_meade := (p_delta_cfi >= -0.002);
    if p_delta_rmsea is not null then
      v_chen := (p_delta_cfi >= -0.010 and p_delta_rmsea <= 0.015);
    end if;
  end if;
  return jsonb_build_object(
    'cheung-rensvold-2002', v_cr,
    'meade-2008',           v_meade,
    'chen-2007',            v_chen
  );
end;
$$;

-- End of fix migration.
