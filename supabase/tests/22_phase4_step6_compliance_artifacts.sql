-- 22_phase4_step6_compliance_artifacts — Phase 4 Step 6 acceptance.
-- Verifies SCIENCE-SPEC §12 + Phase 4 prompt §6:
--   * compliance_artifact_assemble produces a payload + at least one
--     compliance_artifact_sources row (assembled FROM real records)
--   * payload.self_attestation is NULL — the system NEVER auto-attests
--   * sign_off_status defaults to 'draft' on assembly
--   * compliance_artifact_signoff is gated by modeling.signoff (refused)
--   * chk_compliance_signed_requires_signoff refuses direct INSERT/UPDATE
--     of 'signed' without signer + timestamp + >=20-char attestation
--   * compliance_rules carries the AI Act / GDPR timeline as data
--   * Fabrication guard: no validated rows in any of the new tables

begin;
select plan(10);

reset role;
insert into public.rbac_role_permissions (role_id, permission_id)
  select r.id, p.id from public.rbac_roles r cross join public.rbac_permissions p
  where r.org_id is null and r.key = 'people_ops_admin'
    and p.key in ('modeling.read','modeling.write') on conflict do nothing;

-- Setup: register a model so the artifact has lineage to pull from.
do $$
declare employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002'; v_fv uuid; m_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  insert into public.feature_views (org_id, key, feature_kind, source_tables)
    values (employer_a, 'fv_p4s6_'||gen_random_uuid()::text, 'trait_range_fit', array['assessment_scores','roles_catalog'])
    returning id into v_fv;
  m_id := public.model_register(employer_a, 'm_p4s6_'||gen_random_uuid()::text, 'interpretable_baseline_v0', v_fv, null, 'DEV STUB', null);
  perform set_config('t.employer', employer_a::text, true);
  perform set_config('t.model', m_id::text, true);
end$$;

-- ============ [A] assemble ============
do $$
declare a_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','b1000000-0000-0000-0000-000000000003')::text, true);
  a_id := public.compliance_artifact_assemble(
    current_setting('t.employer')::uuid, 'annex_iv_technical_doc',
    'p4s6_annex_iv_'||gen_random_uuid()::text);
  perform set_config('t.artifact', a_id::text, true);
end$$;
select is(
  (select sign_off_status from public.compliance_artifacts where id = current_setting('t.artifact')::uuid),
  'draft',
  '[A1] artifact defaults sign_off_status=draft'
);
select ok(
  (select payload_json -> 'self_attestation' = 'null'::jsonb from public.compliance_artifacts where id = current_setting('t.artifact')::uuid),
  '[A2] payload.self_attestation is null (system NEVER auto-attests)'
);
select ok(
  (select payload_json ? 'models' and payload_json ? 'audit_summary' and payload_json ? 'consent_snapshot' and payload_json ? 'fairness_snapshot' from public.compliance_artifacts where id = current_setting('t.artifact')::uuid),
  '[A3] payload assembled with sections: models + audit + consent + fairness'
);
select ok(
  (select count(*) from public.compliance_artifact_sources where artifact_id = current_setting('t.artifact')::uuid) >= 1,
  '[A4] artifact has at least one source row (assembled FROM real records)'
);
select ok(
  (select count(*) from public.audit_log where action = 'compliance_artifact.assembled' and entity_id = current_setting('t.artifact')::uuid) >= 1,
  '[A5] compliance_artifact.assembled audit event written'
);

-- ============ [B] signoff seam ============
select throws_ok(
  format($q$select public.compliance_artifact_signoff(%L::uuid, 'DEV STUB attempted sign-off by non-expert — should refuse', 'signed')$q$, current_setting('t.artifact')),
  'P0001', NULL::text,
  '[B1] compliance_artifact_signoff refused — modeling.signoff is an expert seam'
);

-- ============ [C] direct UPDATE to signed refused without signoff fields ============
reset role;
select throws_ok(
  format($q$update public.compliance_artifacts set sign_off_status='signed' where id = %L::uuid$q$, current_setting('t.artifact')),
  '23514', NULL::text,
  '[C1] cannot UPDATE sign_off_status=signed without signer + timestamp + attestation (chk_compliance_signed_requires_signoff)'
);

-- ============ [D] compliance_rules ============
select ok(
  (select count(*) from public.compliance_rules where regulation='eu_ai_act') >= 2,
  '[D1] EU AI Act rules seeded as data (policy = data)'
);
select ok(
  (select count(*) from public.compliance_rules where key = 'ai_act_omnibus_standalone_deferral_2027_12') = 1,
  '[D2] Omnibus deferral row exists (SCHEDULE MARGIN ONLY)'
);

-- ============ [E] fabrication guard ============
select is(
  (select count(*) from public.compliance_artifacts where _dev_stub = false)
  + (select count(*) from public.compliance_artifact_sources where _dev_stub = false),
  0::bigint,
  '[E1] no non-stub rows in Phase 4 Step 6 tables (synthetic-only)'
);

select * from finish();
rollback;
