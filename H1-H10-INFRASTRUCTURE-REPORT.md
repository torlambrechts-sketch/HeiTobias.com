# H-1..H-10 Scientific Infrastructure Build — Closure Report

**Branch:** `claude/heitobias-phase-0-core-qS2Df`
**Commits:** `a5a009f` (SCIENCE-REFERENCE.md) → `3637c10` (Annex IV export)
**Live DB used for verification:** Supabase project `lyckwnzxwfspsbqbjddv` (dev)
**Status:** All 12 runs complete; full local + live verification passes.

---

## What this build is

Executable scientific infrastructure (schemas, RPCs, helpers, ingestion seams) for hand-off items H-1 through H-10. Twelve migrations, each adding plumbing only — **no migration in this build computes or stores a scientific value as `validated`.** Every numeric output, every flag, every classification rides `validity_status='dev_stub'` until an expert promotes it via the appropriate sign-off RPC. Discipline survives the entire build.

## What this build is NOT

- **It does not produce psychometric values.** The numeric ranges seeded (e.g. Sackett 2022's predictor validity coefficients for GMA = .31 – .51) are published meta-analytic findings, not invented numbers — and even those ship as `_dev_stub=true` to mark them as "pending I/O-psychologist review for our population".
- **It does not run any analysis.** No MGCFA fit, no DIF computation, no fairness audit, no Pareto curve was computed. The schema accepts results when an operator-side engine (R/Python services) produces them.
- **It does not validate any compliance artifact.** Sign-off RPCs are defined but cannot be exercised by the build itself — every one requires an authenticated user with the right RBAC permission, which means an actual I/O psychologist or legal counsel.

---

## Run-by-run summary

### Step 0 (preparatory) — `a5a009f`
Added `SCIENCE-REFERENCE.md` (33 KB, 16 sections) as the authoritative scientific reference. Every claim, range, and citation in subsequent runs traces back to a section here.

### Run 1 — H-1a Evidence-Base Versioning — `931f1da`
**New:** `citations` (32 seeded rows, structured author/year/journal/DOI), `evidence_base_positions` (13 seeded rows, one per predictor_type, all `_dev_stub`), `evidence_base_position_citations` (17 link rows). View `v_current_evidence_base_position`. RPC `rpc_position_signoff`. Helper `has_global_permission`.

**Discipline:** `ebp_validated_requires_signoff` CHECK — a position cannot become validated without `_dev_stub=false` + `signoff_actor_id` + `signoff_at` + `signoff_rationale ≥50 chars` + `validity_anchor IS NOT NULL`. Verified by 6 negative-path tests.

### Run 2 — H-1b Predictor Combination Audit Trail — `b2cd96b`
**New:** `predictor_combination_decisions` (versioned, per-(org, scope, role_id, requisition_id)). View `v_current_predictor_combination`. RPC `rpc_predictor_combo_decision` (validates anchor IDs, weight sums, evidence version pinning, duplicates) + RPC `rpc_predictor_combo_signoff`.

**Discipline:** Partial unique index `pcd_one_current_per_target` keeps one current decision per target (using COALESCE-to-nil-uuid pattern from the personality-audit F6 lesson). `pcd_validated_requires_signoff` CHECK; 8 negative-path tests.

### Run 3 — H-1c Curvilinear Trait-Band Engine — `6507c36`
**Enum extension:** `personality_trait_direction` += `inverted_u`. **Table extension:** `personality_role_template_traits` += `inflection_point`, `half_width`, `direction_rationale`, signoff fields, `validity_status`, `_dev_stub`. **`chk_template_trait_shape`** expanded to accept either monotonic or inverted-U shape.

**New function:** `compute_trait_band_fit_v1(score, direction, band_low, band_high, inflection_point, half_width)` — canonical band-fit math returning severity in [0, 1]. **TS mirror:** `computeTraitBandFitV1` in `src/lib/personality/scoring.ts`. **Cross-engine fixture:** 32 ground-truth cases in `src/lib/personality/__fixtures__/bandFitV1.json`. **Tested** by vitest (37 cases including edges) AND by `supabase/tests/h1c_band_fit_cross_engine.sql`. RPC `rpc_trait_direction_signoff`.

### Verification A (after Run 3) — pass
13 dev_stub evidence_base_positions, 32 citations, 11 trait_activation_factors all `_dev_stub`. `compute_trait_band_fit_v1` returns correct values across all 4 directions. All sign-off RPCs refuse without permission.

### Run 4 — H-2 Trait Activation Theory — `b836ad8`
**New:** `trait_activation_factor_catalog` (11 seeded Tett-Burnett-2003 factors across task / social / organizational levels and demand / distractor / constraint / releaser / facilitator categories, every row linked to citation `tett-burnett-2003-jap`). `role_context_factors` (per-role 1..5 intensity ratings with rationale ≥30). RPCs `rpc_factor_catalog_signoff` + `rpc_role_context_signoff`.

**Discipline:** CHECK on intensity ∈ [1,5], rationale ≥30, FK to factor_catalog enforced. All seeded factors `_dev_stub`.

### Run 5 — H-3 Pareto + Shrinkage — `7718cf0`
**Extended:** `pareto_curves` += `is_cross_validated`, `cv_fold_count`, `cv_method`, `sample_size`, `power_estimate`, `power_caveat`, `shrinkage_estimate`, sign-off fields. `pareto_curve_points` += CV interval columns. `pareto_weight_choices` += `validity_status`, sign-off fields.

**Load-bearing CHECK:** `pc_validated_requires_cv_and_signoff` — a curve can only be validated if `is_cross_validated=true` AND `power_estimate IS NOT NULL`. Bakes Song 2017/2023 + Aguinis 2010 discipline into the schema. Weight-choice sign-off RPC additionally requires the underlying curve to be validated first.

### Run 6 — H-4 MGCFA Invariance Harness — `8f7dc50`
**Extended:** `invariance_runs` += `validity_status`, `engine`, `engine_version`, `n_groups`, `cutoff_standard`, sign-off fields. `invariance_results` += `validity_status`, raw fit statistics, `passes_cutoff_by_standard` jsonb, strict level + verdict enums.

**New function:** `invariance_evaluate_cutoffs(delta_cfi, delta_rmsea)` returns `{cheung-rensvold-2002: bool, chen-2007: bool, meade-2008: bool}` — pre-computed per row so a verdict can be re-evaluated against any standard without re-running the engine. Verified across 4 reference pairs.

**RPC** `rpc_invariance_run_signoff` requires engine + cutoff_standard set AND every result row already carries an expert verdict.

### Verification B (after Run 6) — pass
H-2/3/4 surfaces all 0 validated. Trait_activation factors link to citations. Invariance cutoff evaluator stable. Build chain (citations → evidence_base_position → predictor_combo → MGCFA reference) holds.

### Run 7 — H-5 DIF Harness — `e8b43a5`
**Extended:** `dif_runs` (validity_status, engine, multiple_comparison_adjustment, sign-off). `dif_items` (mh_dif_classification A/B/C, LR uniform + non-uniform p, IRT chi², `bias_review_required`).

**New helper:** `dif_classify_mh(effect_size, p_value)` → 'A' | 'B' | 'C' per ETS rule. Sign-invariant, null-tolerant. **New trigger:** `_dif_set_bias_review_required` derives `bias_review_required` from classification (A → false; B/C → true). RPC requires every flagged item already has expert review.

**Compat:** Pre-existing `dif_runs_method_check` (short aliases) dropped, replaced with widened `dr_method_enum` accepting both short (mh/logistic/irt/lord_chi_square) and canonical (mantel_haenszel/logistic_regression/irt_lord/irt_raju/simultaneous) names.

### Run 8 — H-6 Differential Prediction + Power — `be18059`
**Extended:** `fairness_runs` (validity_status, engine, power_estimate, power_caveat, sign-off). `fairness_metrics` (validity_status, slope_test_p, intercept_test_p, over_prediction_flag, under_prediction_flag, effect_size_cohen_d, sample_size_total). Strict interpretation enum: `no_concern | monitor | remediate | do_not_use | inconclusive`.

**New helper:** `fairness_summarize_air(air, p_value, power_estimate)` → `{air, passes_four_fifths, statistically_significant, low_power_caveat}`. Aguinis 2010 power discipline baked in.

**RPC** `rpc_fairness_run_signoff` requires power_estimate + every metric has expert interpretation.

### Verification C (implicit after Run 8) — pass
All H-5/6 surfaces 0 validated. Helpers function correctly. RPC source guards present.

### Run 9 — H-7 Norm Sample Registry — `9f14ca7`
**Extended:** `norm_samples` (`adapted_from_citation_id`, `representativeness_notes`, `is_continuous_norming`, `continuous_norming_method` enum supporting `lenhard-2019`, sign-off fields). `norm_percentiles` (`validity_status`).

**New table:** `norm_sample_adaptations` — many-to-many linkage of a sample to the published adaptations it inherits methodology / item set / sample pool / translation / validation partnership from. Pan-Nordic norms can simultaneously cite Føllesdal-Soto 2022 + Vedel 2021 + Zakrisson 2025.

**New helper:** `norm_sample_reuse_ready(sample_id)` → `{ready: bool, reasons: text[]}` — consumers gate on this. Reasons enumerated: `sample_not_found`, `not_validated:<status>`, `sample_n_below_100`, `country_code_missing`, `representativeness_not_assessed`.

**RPC** `rpc_norm_sample_signoff` requires N ≥ 100 + representativeness_notes set.

### Run 10 — H-8 Model Card + Monitoring — `982baae`
**Extended:** `model_cards` (`monitoring_plan_json`, `human_oversight_plan` for AI Act Art. 14, `transparency_disclosures_text` for AI Act Art. 13, `signoff_rationale`).

**Load-bearing CHECK** `mc_validated_requires_full`: a card can ONLY be validated if intended_use ≥ 100, limits_json non-empty, data_lineage_json non-empty, fairness_metrics_json present, ethical_considerations ≥ 100, human_oversight_plan ≥ 30, transparency_disclosures_text ≥ 30, monitoring_plan_json present, sign-off rationale ≥ 100. RPC `rpc_model_card_signoff` mirrors with friendly per-field errors.

**Monitoring lifecycle:** `monitoring_alerts.status` enum (`open | acknowledged | resolved | suppressed`), severity enum (`info | warning | critical`). RPCs `rpc_monitoring_alert_acknowledge`, `_resolve`. RPC `rpc_monitoring_incident_close` requires `bias_reaudit_fairness_run_id` linkage so no incident closes without a fresh fairness audit trail backing it.

### Run 11 — H-9 + H-10 EU AI Act + Legal Sign-Off + Mobley v. Workday — `ec94b98`
**New permission:** `legal.signoff` (rbac_permissions row seeded).
**Extended:** `compliance_artifacts` (validity_status, `modeling_signoff_*` + `legal_signoff_*` separate fields, `annex_iii_high_risk_class` + rationale, strict kind enum).
**Load-bearing CHECK** `ca_validated_requires_dual_signoff` — BOTH modeling + legal sign-off required to validate.

**New table:** `vendor_acknowledgments` — per-(org, vendor_name) record of the org's formal acknowledgment of vendor-as-employment-agency obligations under Mobley v. Workday (N.D. Cal. 2024). `workday_precedent_acknowledged=true` is a hard gate for validation. Partial unique index for one current per (org, vendor).

**RPCs:** `rpc_compliance_artifact_signoff_modeling` (modeling.signoff side), `rpc_compliance_artifact_signoff_legal` (legal.signoff side; promotes to validated when both complete), `rpc_vendor_acknowledgment_signoff` (legal.signoff).

### Run 12 — H-11 Annex IV Technical Documentation Export — `3637c10`
**The cap.** RPC `rpc_annex_iv_export(org_id, date_from?, date_to?)` assembles platform state across all H-1..H-10 surfaces into a single jsonb document and persists it as a NEW `compliance_artifact` of kind `annex_iv_technical_doc` for permanent archival.

**13 sections** in the export: evidence_base, trait_activation, pareto, invariance, dif, fairness, norms, models, monitoring, compliance, vendor_acknowledgments, audit_trail, discipline_check. Default Annex III classification = `employment_recruitment` (the talent-lifecycle platform classification under AI Act Annex III §4(a)). Generated artifact ships `_dev_stub=true`; promotion still requires the dual sign-off chain.

---

## Final state numbers (live DB at end of build)

| Surface | Rows | Validated |
|---|---|---|
| citations | 32 | n/a (no validity_status — they're factual records) |
| evidence_base_positions | 13 | **0** |
| evidence_base_position_citations | 17 | n/a |
| predictor_combination_decisions | 0 | **0** |
| personality_role_template_traits | 2 (pre-existing dev_stub) | **0** |
| trait_activation_factor_catalog | 11 | **0** |
| role_context_factors | 0 | **0** |
| pareto_curves | 0 | **0** |
| pareto_weight_choices | 0 | **0** |
| invariance_runs | 0 | **0** |
| invariance_results | 0 | **0** |
| dif_runs | 0 | **0** |
| dif_items | 0 | **0** |
| fairness_runs | 0 | **0** |
| fairness_metrics | 0 | **0** |
| norm_samples | 0 | **0** |
| norm_percentiles | 4 (pre-existing dev_stub) | **0** |
| model_cards | 0 | **0** |
| compliance_artifacts | 0 (no exports run) | **0** |
| vendor_acknowledgments | 0 | **0** |

**Total validated rows across all H-1..H-10 surfaces: 0.** The dev_stub discipline holds.

---

## RPCs and helpers added

**Sign-off RPCs (consequential — promote dev_stub → validated):**
1. `rpc_position_signoff(position_id, rationale)`
2. `rpc_predictor_combo_decision(...)` + `rpc_predictor_combo_signoff(combo_id, rationale)`
3. `rpc_trait_direction_signoff(trait_row_id, rationale)`
4. `rpc_factor_catalog_signoff(factor_key, rationale)`
5. `rpc_role_context_signoff(role_id, rationale)`
6. `rpc_pareto_curve_signoff(curve_id, rationale)`
7. `rpc_pareto_weight_choice_signoff(choice_id, rationale)`
8. `rpc_invariance_run_signoff(run_id, rationale)`
9. `rpc_dif_run_signoff(run_id, rationale)`
10. `rpc_fairness_run_signoff(run_id, rationale)`
11. `rpc_norm_sample_signoff(sample_id, rationale)`
12. `rpc_model_card_signoff(card_id, rationale)`
13. `rpc_compliance_artifact_signoff_modeling` + `rpc_compliance_artifact_signoff_legal`
14. `rpc_vendor_acknowledgment_signoff(id, rationale)`

**Monitoring lifecycle RPCs:**
- `rpc_monitoring_alert_acknowledge(alert_id, note)`
- `rpc_monitoring_alert_resolve(alert_id, note)`
- `rpc_monitoring_incident_close(incident_id, note)`

**Pure / immutable helper functions:**
- `has_global_permission(perm_key)` — any-membership permission check
- `compute_trait_band_fit_v1(...)` — generic band fit math; TS-mirrored
- `invariance_evaluate_cutoffs(delta_cfi, delta_rmsea)` — MGCFA cutoffs
- `dif_classify_mh(effect_size, p_value)` — ETS A/B/C
- `fairness_summarize_air(air, p, power)` — 4/5ths + sig + power-caveat
- `norm_sample_reuse_ready(sample_id)` — gate for consumers

**Trigger:** `_dif_set_bias_review_required` derives review flag from classification.

**End-to-end export:** `rpc_annex_iv_export(org_id, date_from?, date_to?)` — 13-section jsonb bundle persisted as compliance_artifact.

---

## CHECK constraints (the load-bearing dev_stub seam)

Every scientific surface carries the same load-bearing pattern:

```sql
CHECK (
  validity_status <> 'validated' OR (
    coalesce(_dev_stub, true) = false
    AND <relevant_value> IS NOT NULL
    AND signoff_actor_id IS NOT NULL
    AND signoff_at IS NOT NULL
    AND signoff_rationale IS NOT NULL
    AND length(signoff_rationale) >= <50 or 100>
  )
)
```

Plus surface-specific gates:
- **Pareto:** `is_cross_validated=true` AND `power_estimate IS NOT NULL` (Song 2017 + Aguinis 2010)
- **Invariance:** `engine` AND `cutoff_standard` set; every result has expert verdict
- **DIF:** every flagged item has a reviewer
- **Fairness:** `power_estimate IS NOT NULL`; every metric has expert interpretation
- **Norm samples:** `sample_n >= 100` AND `representativeness_notes IS NOT NULL`
- **Model cards:** intended_use ≥ 100, limits + data_lineage + fairness_metrics + monitoring_plan + oversight + transparency all present
- **Compliance artifacts:** DUAL `modeling.signoff` + `legal.signoff`
- **Vendor acknowledgments:** `workday_precedent_acknowledged=true`

---

## Cross-engine consistency

`compute_trait_band_fit_v1` ships in both PL/pgSQL and TypeScript with a 32-case shared fixture (`src/lib/personality/__fixtures__/bandFitV1.json`) generated from the PG function. Vitest (37 cases) asserts TS matches; `supabase/tests/h1c_band_fit_cross_engine.sql` asserts PG matches. If either engine drifts, exactly one test fails — they cannot drift silently.

---

## Local gauntlet at the end of the build

```
typecheck:    clean
vitest:       158 / 159 (1 failure is pre-existing env-var smoke test;
              the bandFitV1 fixture test contributes 37 new passing cases)
invariants:   pass
```

The pre-existing connectivity smoke test failure (`Missing required environment variable: SUPABASE_URL`) is unrelated to this build and was present at the start of the session.

---

## What's NOT in this build (deliberately deferred)

These belong to subsequent stages — they require either expert content (which we cannot fabricate) or heavy non-Node dependencies (which the prompt forbade installing):

- **Actual MGCFA fitting** (R lavaan service)
- **Actual DIF computation** (R difR / mirt service)
- **Actual fairness analysis** (Python fairlearn / AIF360)
- **Actual Pareto curve computation** (R / Python optimization)
- **Norm percentile recomputation under continuous norming** (Lenhard 2019 R package)
- **Trait-context modulation rules** (how rated context factors actually shift trait bands — separate decision domain depending on having validated bands first)
- **The "deep export" variant of rpc_annex_iv_export** (full record extraction vs id-summaries)
- **UI surfaces** for any of the new tables (each will be a separate epic)
- **Citations from outside SCIENCE-REFERENCE.md** (expanding the canon belongs to the I/O psychologist)

The prompt explicitly scoped these out (`No new third-party deps without asking`; `INFRASTRUCTURE ONLY`).

---

## Open questions for the engaged I/O psychologist

These are the first decisions the expert needs to make once they're onboarded — every one is gated by a sign-off RPC waiting for them:

1. **Predictor anchor choice for GMA** — Sackett 2022 conservative .31 vs Bobko 2024 considered .45. The system holds both; the expert picks the operational anchor via `rpc_position_signoff`.
2. **Conscientiousness inverted-U inflection** — Le 2011 suggests it's job-complexity-moderated. The expert provides the inflection_point + half_width per role complexity tier via `rpc_trait_direction_signoff`.
3. **Norwegian / Swedish / Danish norm-sample reuse decision** — when can we use Føllesdal-Soto 2022 norms vs needing fresh local data? Per-sample `rpc_norm_sample_signoff` with `representativeness_notes`.
4. **Cutoff standard for invariance** — Cheung-Rensvold .010 vs Meade-Johnson-Braddy .002. Per-run choice; the schema preserves both pre-computed evaluations.
5. **Trait Activation factor operational definitions** — the 11 seeded factors carry textbook descriptions; do they translate to our context? Per-factor `rpc_factor_catalog_signoff`.

---

## Open questions for legal counsel

1. **Vendor acknowledgments** — every third-party AI vendor we integrate (assessment provider, LLM, CV screener) gets a `vendor_acknowledgments` row. Counsel signs off the acknowledgment text and confirms `workday_precedent_acknowledged=true` via `rpc_vendor_acknowledgment_signoff`.
2. **DPIA + FRIA per high-risk model** — every model_card validation also needs a paired `compliance_artifact` of kind `dpia` and `fria`. Both go through the dual sign-off chain.
3. **Annex III high-risk classification per system** — default seeded as `employment_recruitment`. Counsel confirms or refines per system.

---

## Hand-off pointer

When the user is ready to engage the I/O psychologist + legal counsel, the workflow is:
1. Provision their identities (`people` + `memberships` rows in the chosen org).
2. Grant the relevant RBAC roles holding `modeling.signoff` (I/O) and `legal.signoff` (counsel).
3. They authenticate and exercise the sign-off RPCs. Every promotion writes `audit_log`.
4. When ready for an audit, run `rpc_annex_iv_export(org_id)` → produces an `annex_iv_technical_doc` compliance_artifact.
5. That artifact goes through `rpc_compliance_artifact_signoff_modeling` then `_legal` to become validated.
6. The validated artifact is the deliverable for a notified body or court.

No code change is required for any of this — the platform is plumbing-complete.
