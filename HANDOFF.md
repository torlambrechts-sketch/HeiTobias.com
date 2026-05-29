# HANDOFF — Phase 4 expert seams that MUST be filled before live use

> **This list is the gate to production. Not the passing test suite.**
>
> Phase 4 ships the *infrastructure* (pipelines, registries, metric
> computation, audit assembly, monitoring) for HeiTobias to operate as
> a predictive-intelligence / bias-audit / Nordic-validation product.
> It does **not** ship validated science. Every row in every Phase 4
> table is `_dev_stub = true`. Every model/card/dataset is
> `validity_status = 'dev_stub'`. The seam that converts each of those
> to `validated` is an **explicit expert step** — gated by the
> `modeling.signoff` RBAC permission that is intentionally NOT granted
> to any seeded role.
>
> Until each item below is filled by the named expert and signed off,
> HeiTobias must operate on **synthetic data only**. Any attempt to use
> the platform on real candidate / employee data without these
> sign-offs is a deviation from the build contract.
>
> *Mobley v. Workday* establishes that an HR-software vendor can be
> pulled directly into employment-discrimination liability. Shipping
> fabricated fairness conclusions, fabricated norms, or unverified
> "compliant" attestations would manufacture exactly that exposure on
> behalf of every customer.

---

## Who owns each seam

| Role | Surface |
| ---- | ------- |
| **Credentialed I/O psychologist** (BPS / EFPA Test User – Work, equivalent) | All measurement / fit / validity / fairness / norm seams |
| **Legal / EU AI Act advisor** | All compliance-attestation, DPIA, FRIA, Annex IV sign-off seams |
| **Customer's people-leadership executive** | Pareto-point choice + lifecycle-decision sign-off |
| **Customer's DPO** | Consent-purpose oversight; revocation audits |

The expert seam is gated by RBAC, not by code-review trust. The
permission `modeling.signoff` is what unlocks the signoff functions
listed below; it is **NOT granted to any seeded role** in this
codebase. Granting it is an out-of-code administrative act, by an
authorized actor who has verified the expert's credentials.

---

## 0. Synthetic-only invariant

**Seam.** Every Phase 4 table has `_dev_stub boolean default true`.
Tests `17_phase4_step1_*` … `23_phase4_step7_*` each assert that no
row carries `_dev_stub=false` or `validity_status='validated'` after
the test run. This guard is what makes "synthetic only" a load-bearing
property rather than a slogan.

**Filled by.** N/A — this is the precondition. The moment any of the
items below is filled, the corresponding `_dev_stub` row gets flipped
and the synthetic guard naturally relaxes for that surface.

---

## 1. Feature pipeline — Step 1

### 1.1 `feature_compute_trait_range_fit` band-fit math
- **Function:** `public.feature_compute_trait_range_fit(person, org, role, fv, valid_at)`
- **Current state:** DEV STUB returns `band_fit = 0.5` per competency,
  with `_dev_stub=true` and `source_refs.method='trait_range_fit_dev_stub_v0'`.
- **Required from expert:** Validated band-fit formula (Pierce & Aguinis
  2013 inverted-U with the chosen instrument's band centre / lower /
  upper from `roles_catalog.definition_json.trait_targets[]`).
- **Filled by:** I/O psychologist.
- **How the system enforces.** When the expert plugs the real math, the
  `_dev_stub` flag on the returned `feature_rows.id` is what they
  flip; the value-level CHECK already exists for downstream tables
  that consume those rows.

### 1.2 Complexity-conditional cognitive features (`feature_kind = 'complexity_conditional_cognitive'`)
- **Surface:** `feature_views.feature_kind` allow-list permits this kind;
  no compute function ships in Phase 4.
- **Required from expert:** Validated cognitive-test scoring + the
  per-role complexity-conditioning function (SCIENCE-SPEC §1 — cognitive
  validity conditional on role complexity).
- **Filled by:** I/O psychologist.

### 1.3 Role-context features (`feature_kind = 'role_context_factor'`)
- **Surface:** Same as 1.2 — allow-listed kind, no compute.
- **Required from expert:** Mapping from `roles_catalog.definition_json.context_factors`
  to per-person features (Trait Activation Theory; SCIENCE-SPEC §3).
- **Filled by:** I/O psychologist.

### 1.4 Pulse-trend feature
- **Surface:** `feature_kind = 'pulse_trend'` — allow-listed.
- **Required from expert:** Validated transformation from
  `pulse_responses` time-series → feature value (SCIENCE-SPEC §6 — pulse
  is engagement, never performance).
- **Filled by:** I/O psychologist.

---

## 2. Model scaffolding — Step 2

### 2.1 Interpretable-baseline weights
- **Function:** `prediction_compute_baseline_interpretable(model, person, role)`
- **Current state:** Weights default to `target_weight` from the
  competency definition or `1`. `score_value` is the mean of
  `weight × band_fit`. `explanation_shap_json` is the per-feature
  contribution. All `_dev_stub=true`.
- **Required from expert:** Validated weights per competency in the
  role-conditioned composite (Sackett 2022 ranges; SCIENCE-SPEC §1).
  Per-feature contributions stay as SHAP-equivalent since the model is
  linear-additive by design — that's what makes the Art. 22 "logic
  involved" requirement structural.
- **Filled by:** I/O psychologist.
- **How the system enforces.** The `chk_predictions_shap_present`
  CHECK refuses any prediction without at least one explanation row.

### 2.2 Four-quadrant classifier (`family = 'four_quadrant_classifier_v0'`)
- **Surface:** Family allow-listed in `model_registry.family`; no compute
  function ships.
- **Required from expert:** Validated stable_fit / growth_gap /
  flight_risk / emerging_misfit boundary thresholds against the customer
  population (SCIENCE-SPEC §7).
- **Filled by:** I/O psychologist.

### 2.3 Flight-risk logistic + growth-gap projection + performance composite
- **Surface:** Families allow-listed; no compute functions ship.
- **Filled by:** I/O psychologist.

### 2.4 Model-card sign-off
- **Function:** `model_card_signoff(model_id)` — gated by
  `modeling.signoff`.
- **Required from expert:** Complete `intended_use`, `limits_json`,
  `data_lineage_json`, `features_json`, `weights_json`,
  `fairness_metrics_json`, `ethical_considerations`, then call signoff.
- **Filled by:** I/O psychologist (intended use, limits, features,
  weights, fairness summary) + legal advisor (ethical considerations,
  GDPR Art. 22 logic-disclosure language).
- **How the system enforces.** `chk_model_cards_validated_requires_fields`
  refuses any `validated` card without those structured fields +
  signer + timestamp.

---

## 3. Pareto curve — Step 3

### 3.1 Pareto-curve estimator
- **Function:** `pareto_curve_compute(org, fv, model, key, lambda)`
- **Current state:** Synthetic linear interaction — 21 points emitted at
  0.05 increments, with `predicted_validity = 0.30 + 0.30w` and
  `predicted_air = 0.95 - 0.40w`. Default point at w=0.5.
- **Required from expert:** Validated estimator (De Corte 2007; Song
  2017/2023) on the customer's real data. Regularization lambda mapped
  to a Bayesian-posterior shrinkage instead of the synthetic linear
  shrink.
- **Filled by:** I/O psychologist.

### 3.2 Pareto-point choice rationale
- **Function:** `pareto_weight_choose(curve_id, w, rationale, model_id)`
- **Current state:** Function requires authenticated person + >=20-char
  rationale at runtime.
- **Required from expert:** The actual choice — by the customer's
  people-leadership executive — with a rationale that survives an EU
  AI Act Art. 12 audit and a *Mobley v. Workday*-style discovery.
- **Filled by:** Customer's people-leadership executive.

---

## 4. Fairness audit — Step 4

### 4.1 Adverse-impact CIs + confirmatory tests
- **Function:** `fairness_metric_record(...)`
- **Current state:** CI computed as ±0.05 around AIR (DEV STUB).
  `four_fifths_inspection_triggered = (AIR < 0.80)`.
- **Required from expert:** Validated Wilson / bootstrap CIs + a
  confirmatory Fisher exact / chi-square / G-test, all computed in the
  external R / Python pipeline and ingested via this function.
- **Filled by:** I/O psychologist (CI + confirmatory test selection).

### 4.2 Differential prediction (Cleary slope/intercept by group)
- **Surface:** Columns `differential_prediction_slope` /
  `differential_prediction_intercept` exist on `fairness_metrics`.
- **Required from expert:** Computed slopes/intercepts per group from
  the external pipeline, ingested via `fairness_metric_record`.
- **Filled by:** I/O psychologist.

### 4.3 Fairness-metric interpretation
- **Function:** `fairness_metric_interpret(metric_id, interpretation)` —
  gated by `modeling.signoff`.
- **Current state:** `interpretation_by_expert` is NULL on insert. The
  function requires >=20 chars.
- **Required from expert:** A written interpretation per (characteristic
  × group) row that states whether the observed AIR / CI / slope is
  acceptable, by reference to the population, the test used, and the
  legal context. The system NEVER auto-asserts "unbiased".
- **Filled by:** I/O psychologist (statistical view) + legal advisor
  (compliance view).

### 4.4 Demographics → never a feature
- **Trigger:** `_guard_no_demographic_feature` on `feature_views`.
- **Current state:** Refuses any `feature_views.source_tables` containing
  `'demographics_voluntary'`. AI Act Art. 10(5) permits special-category
  processing for bias-detection only.
- **Filled by.** Structurally enforced; no expert seam — this rule is
  load-bearing as code.

---

## 5. Measurement invariance / DIF / Nordic norms — Step 5

### 5.1 Real Nordic norm collection
- **Surface:** `norm_samples` + `norm_percentiles`.
- **Current state:** `_dev_stub = true`;
  `chk_norm_samples_validated_requires_real` refuses `validated`
  unless `sample_n >= 100` AND `_dev_stub = false`.
- **Required from expert:** Real norm samples per (instrument × country
  × language × period), each backed by a sampling-design protocol with
  representativeness documentation (SCIENCE-SPEC §11; AI Act Art. 10
  representativeness).
- **Filled by:** I/O psychologist.

### 5.2 Invariance verdict
- **Function:** `invariance_verdict_record(result_id, verdict)` — gated
  by `modeling.signoff`.
- **Current state:** `invariance_results.invariance_verdict_by_expert`
  NULL on insert. The function requires >=20-char verdict.
- **Required from expert:** A per-(level, instrument, group-comparison)
  written verdict ("configural achieved" / "metric not achieved at
  ΔCFI=−0.012 — proceed with partial scalar comparisons only" / etc.).
  The system NEVER self-declares invariance.
- **Filled by:** I/O psychologist.

### 5.3 DIF item review
- **Surface:** `dif_items.expert_review_note` + `reviewed_by_person_id`.
- **Current state:** `flagged_for_review` is computed from
  `|effect_size| >= threshold`; the threshold default is 0.10
  (Mantel-Haenszel C starting point). Review note is NULL.
- **Required from expert:** Per-flagged-item review notes — keep / drop
  / revise — with reasoning.
- **Filled by:** I/O psychologist (note) + content owner (item authors).

---

## 6. EU AI Act compliance assembly — Step 6

### 6.1 Annex IV / DPIA / FRIA / validity-dossier sign-off
- **Function:** `compliance_artifact_signoff(artifact_id, attestation, status)`
- **Current state:** `payload_json.self_attestation` is NULL on assembly.
  `sign_off_status` defaults to 'draft'. Function gated by
  `modeling.signoff`; requires >=20-char attestation.
- **Required from expert:** A written attestation by the legal / AI Act
  advisor that the assembled artifact, when reviewed against the customer's
  deployment context, satisfies the cited regulation. The system NEVER
  self-attests.
- **Filled by:** Legal / AI Act advisor.

### 6.2 Compliance-rule timeline updates
- **Surface:** `compliance_rules` table — policy as data.
- **Current state:** Seeded with Annex IV (Aug 2026), Art. 27 FRIA (Aug
  2026), GDPR Art. 35 DPIA (May 2018), Omnibus deferral (Dec 2027, marked
  SCHEDULE MARGIN ONLY).
- **Required from expert:** Ongoing rule updates as the AI Act + GDPR +
  Workplace Act + Uniform Guidelines evolve.
- **Filled by:** Legal / AI Act advisor (with platform engineering
  applying the row changes via migration).

---

## 7. Monitoring — Step 7

### 7.1 Retrain-trigger thresholds
- **Surface:** `monitoring_runs.retrain_triggered` is whatever the caller
  passes in; no thresholds enforced at the DB.
- **Required from expert:** Per-model drift thresholds + the
  6-12-month retrain cadence requirement (SCIENCE-SPEC §10 mandatory bias
  re-audit on retrain).
- **Filled by:** I/O psychologist + ML-platform owner.

### 7.2 Alert acknowledgement + resolution
- **Functions:** `monitoring_alert_acknowledge` /
  `monitoring_alert_resolve`.
- **Current state:** Both human-attribution + note-required at function
  level. Status enum has NO `auto_remediated` value.
- **Required from expert:** Per-alert acknowledgement / resolution by
  the responsible human. This is the actual operating cost of the
  no-auto-remediation rule, and we want it visible.
- **Filled by:** Customer's modeling-permissioned operators.

### 7.3 Bias re-audit on retrain
- **Surface:** `monitoring_incidents.bias_reaudit_fairness_run_id`.
- **Current state:** Column is nullable — the UI + workflow loop will
  enforce its presence for people-affecting models.
- **Required from expert:** A `fairness_runs` row + interpreted
  `fairness_metrics` rows must accompany every retrain incident for a
  people model.
- **Filled by:** I/O psychologist + customer's modeling-permissioned
  operators.

---

## 8. RBAC — the `modeling.signoff` permission

The permission `modeling.signoff` exists in `rbac_permissions` but is
**not** granted to any seeded role. It is the gating mechanism for:

- `model_card_signoff`
- `fairness_metric_interpret`
- `invariance_verdict_record`
- `compliance_artifact_signoff`

**Granting it is an administrative act, NOT a code change.** When a
customer engages a credentialed expert, an authorized admin grants
`modeling.signoff` to the expert's RBAC role on the customer's org.
Audit trail of that grant lives in `audit_log`.

---

## 9. UI — Step 8

The `/modeling` admin page is a read-only inspector. It does not yet
expose sign-off forms; those will be added once the first expert is
engaged. The page does prominently surface, on every section:

- `_dev_stub` rows are marked with the StubBadge.
- HitlNotice repeats the "informs, never decides" framing.
- A copy block explicitly labels Phase 4 as "infrastructure, not
  validated science."

---

## 10. The deliverable

A passing Phase 4 test suite (suites 17–23) gives us the machinery:
consent-gated feature pipeline, interpretable baseline with SHAP, live
Pareto curve, fairness metric machinery, invariance/DIF harness,
compliance assembly, monitoring loop. Items 1–8 above are what convert
that machinery into a legitimately deployable product.

**Until items 1–8 are filled by the named experts, HeiTobias operates
on synthetic data only. No exceptions.**
