# Self-Audit Report — Phases 0–4 (full build)
Generated: 2026-05-28T19:00Z
Audited by: Claude Code (adversarial self-audit)
Branch: `claude/heitobias-phase-0-core-qS2Df` (live)

## Summary

- **Total checks (universal + phase-specific):** 38
- **PASS:** 24
- **FAIL:** 4
- **PARTIAL:** 6
- **UNKNOWN:** 4
- **Test suite:** 25 files ran. 23 PASS, **2 FAIL** (test 06 `06_audit_coverage`, test 16 `16_science_spec_enforcement`). Total assertions ≈ 215; 2 assertions failed (one per failing file).

## Critical findings (FAIL items, priority order)

### F-1. **Trait targets are encoded as `{trait, min, max}` — SCIENCE-SPEC §2 violation.**
- **What was checked.** SCIENCE-SPEC §2 mandates that every trait target on a Role Profile be a band with `centre`, `lower`, `upper`, `direction ∈ {optimum, minimum_threshold, maximum_threshold, linear}` plus justification + evidence_refs. CLAUDE.md Pillar 5 + the "never list" repeat this rule. "More is better" or bare min/max with no direction is architecturally disallowed.
- **Evidence.** `supabase/migrations/20260528085946_role_architecture_tables.sql:140-152` (and again at 194-206) defines the role-definition JSONSchema:
  ```json
  "trait_targets":{"type":"array","items":{"type":"object",
    "required":["trait","min","max"],
    "properties":{"trait":...,"min":...,"max":...},
    "additionalProperties":false}}
  ```
  `additionalProperties: false` actively **rejects** a `direction` or `centre` field. Seed data confirms the shape is in actual use — `select definition_json->'trait_targets' from public.roles_catalog`:
  ```
  [{"max":0.9,"min":0.5,"trait":"openness"}]
  ```
  No `direction`. No justification. No `centre`. No evidence_refs. The PHASE1-SPEC §7 acceptance bullet 2 ("Trait bands store `min`/`max` correctly") even codified the wrong shape into the contract.
- **Why it's load-bearing.** SCIENCE-SPEC §2 calls trait-as-band "a fairness intervention" — wider direction-aware bands reduce differential selection. The DEV-STUB seam is intact (`validity_status='dev_stub'`) for individual scores, but the shape of the TARGET itself violates the spec. An advisory I/O psychologist arriving today would have to redesign the role schema before they can plug in real bands.
- **Recommendation.** Migration to add `direction`, `centre`, `lower`, `upper`, `justification`, `evidence_refs` to the trait_targets JSONSchema; rewrite seed templates; update PHASE1-SPEC §7 bullet 2 (the spec itself is currently wrong relative to SCIENCE-SPEC).

### F-2. **EU data residency is NOT enforced.**
- **What was checked.** CLAUDE.md hard "never" + SCIENCE-SPEC §8 + PHASE0-SPEC §9 final checklist item ("All hosting in EU region"). No personal data leaves the EU.
- **Evidence.**
  - `supabase/config.toml:2-3`: live project is `us-east-1` — "DEV ONLY; production must be EU." The comment is the only guardrail.
  - `select data_region from public.organizations`: both seeded orgs are `'us'`. Nordic Recruit AB (SE) and FjordTech AS (NO) carry `data_region='us'` despite the table default being `'eu'`. The schema enum (`20260528071634_core_organizations_and_people.sql:19`) allows `eu | us | apac`.
  - There is no CHECK / trigger / RLS predicate that enforces `data_region = 'eu'` on any table.
- **Why it's load-bearing.** "Never store personal data outside the EU region" is one of 11 items in CLAUDE.md's hard "never" list. The current dev configuration violates it. Production would have to change region AND backfill row-level data.
- **Recommendation.** (a) Provision an EU-region Supabase project for any environment that touches real candidate / employee data, (b) tighten the `data_region` column with `CHECK (data_region = 'eu')` for any org that intends to onboard, (c) make `data_region` a required field on org creation rather than a default, (d) update the seed to use `'eu'` so the dev DB matches the contract.

### F-3. **Test 06 `06_audit_coverage` is broken by Phase 4 — regression.**
- **What was checked.** Step E (cross-phase regression). Full test suite run; no previously-passing test should now fail.
- **Evidence.** Test 06 plan(6); failed 1/6. The failing assertion: `every public domain table (except audit_log) carries an _audit_row trigger`. Five Phase 4 tables added without audit triggers:
  ```
  compliance_artifact_sources
  compliance_rules
  model_dataset_subjects
  norm_percentiles
  pareto_curve_points
  ```
  These are child / derived / config tables (lineage rows, dataset subject membership, norm percentiles per sample, points on a curve, regulation rules). All of them, by phase-1 invariant, must still carry an audit trigger. Phase 4 added them without — silently breaking a Phase 0 invariant.
- **Why it's load-bearing.** PHASE0-SPEC §9 bullet 8 ("Every consequential mutation lands in an immutable audit_log"). If a child row can be added/deleted without an audit row, the Annex IV evidence assembly (`compliance_artifact_assemble`) is undermined — the very artifact's source-lineage rows are not themselves auditable.
- **Recommendation.** Add `create trigger trg_audit_<table> after insert or update or delete on public.<table> for each row execute function public._audit_row();` for each of the five tables. Re-run test 06.

### F-4. **Test 16 `16_science_spec_enforcement` B3 fails — refusal precedence regressed.**
- **What was checked.** SCIENCE-SPEC §8 refusal taxonomy: medical / legal / dismissal / salary / protected-characteristic inference → decline. Test 16/B3 asserts that the prompt "Do I have legal grounds to dismiss?" is refused under `dismissal` (per the test's `'dismiss' before legal' ordering` comment).
- **Evidence.** Failing assertion:
  ```
  not ok 8 - B3
  #   have: legal
  #   want: dismissal
  ```
  The refusal IS happening (a refusal row IS created, `output_json.refused = true`, `guidance.refused` audit event written) — the system correctly declines. But the *category* it labels the refusal with is `legal`, not `dismissal`. The dismissal/legal precedence in the heuristic is inverted relative to the test's contract.
- **Why it's load-bearing.** The category is what flows to audit reports + the public fairness report. Mislabelling a dismissal-context refusal as a "legal query" understates the surveillance / wrongful-termination risk the AI Act treats as highest-risk.
- **Recommendation.** Fix the precedence in `guidance_compose`'s refusal classifier — `dismiss|terminate|fire` patterns should match BEFORE `legal|lawyer|attorney`. Or, accept the new ordering and update the test (less defensible — SCIENCE-SPEC §6 frames dismissal as a separate category).

## Partial implementations

### P-1. **"Single cross-org bridge" — `placement_execute` is the only data-transfer bridge, but four other token-gated RPCs write cross-org consent rows.**
- **Evidence.** `pg_get_functiondef` scan of all SECURITY DEFINER functions confirms: only `placement_execute` inserts into `public.profiles`, `public.positions`, or `public.placements` cross-org. **However**, four other `security definer` functions write `public.consent_grants` rows with `granted_to_org_id` derived from a parameter:
  - `portability_grant(token, employer_org_id)` — `20260528123851_phase2_step2_consent_dashboard.sql:233`
  - `research_consent_grant(token, employer_org_id)` — `20260528180304_phase4_step1_feature_pipeline.sql:61`
  - `fairness_consent_grant(token, employer_org_id)` — `20260528183552_phase4_step4_fairness_functions.sql:100`
  - `placement_activate(placement_id)` reads `to_org_id` from the placement row (not a free parameter) but writes a new consent_grant in that org — `20260528125245_phase2_step3_employer_activation.sql:68`
- **Why it's PARTIAL not FAIL.** All four are token-gated (the data subject is the author) and write a *consent record about their own data* — they are not cross-tenant data *transfers*. The strict reading of CLAUDE.md "the only sanctioned cross-org data bridge" is consent-grant writes that the data subject initiates with their own token, which is materially different from a profile transfer. But the strict-reading rule of this audit ("ties go to FAIL") leans toward documenting them as an exception worth naming explicitly in the architectural contract.
- **Recommendation.** Add a short paragraph to CLAUDE.md distinguishing "data-subject-initiated cross-org consent writes" from "cross-org data transfers." Document the four functions in HANDOFF.md as a known exception with the rationale.

### P-2. **MBTI/DISC denylist regex is incomplete.**
- **Evidence.** `20260528175143_science_spec_enforcement.sql:14-22` enforces a CHECK that refuses MBTI / Myers-Briggs / DISC / VARK / Kolb / learning-styles / Belbin on `assessment_instruments`. **Missing tokens** (relative to CLAUDE.md Pillar 5 + the "never list"): `colours` / `Insights` / `9.box`.
- **Why PARTIAL.** Test 16/A1-A5 confirm the 4 tokens that ARE in the regex are refused; the regex does refuse the spec's anchor cases. The omission means a vendor named "Insights Discovery" could slip through if someone added the row.
- **Recommendation.** Expand the regex: `(mbti|myers[\s_-]?briggs|disc[\s_-]?profile|disc[\s_-]?assessment|disc[\s_-]?model|^disc$|vark|kolb[\s_-]?learning|learning[\s_-]?styles|belbin|insights[\s_-]?discovery|colou?rs?[\s_-]?model|9[\s_-]?box[\s_-]?auto)`.

### P-3. **FORCE RLS missing on 34 of 71 public tables.**
- **Evidence.** Background-agent grep + table-listing. 71 public tables have RLS enabled; only 37 carry `alter table … force row level security;`. The 34 without include `people`, `profiles`, `placements`, `hiring_decisions`, `consent_grants`, `organizations`, `memberships`, `audit_log` — the load-bearing tables. Without FORCE, the **table owner** (the migrate-time role) bypasses RLS — fine for migrations, but means service-role-equivalent connections bypass tenancy.
- **Why PARTIAL.** Default-deny is satisfied for `authenticated`. The exposure is to operational tooling running under elevated credentials.
- **Recommendation.** Add `alter table … force row level security;` to each of the 34 tables in a single migration. Re-run all tests.

### P-4. **`compliance_rules_select` uses `using (true)` without `to authenticated`.**
- **Evidence.** `pg_policies`: `compliance_rules_select` has `qual = 'true'` and no role-scoping. Defined at `20260528184551_phase4_step6_compliance_artifacts.sql:111`.
- **Why PARTIAL.** Content is public regulation rules with no per-tenant data, so the data exposure is low. But the strict letter of "RLS default-deny, no `USING (true)` unless intentionally permissive" treats every `USING(true)` policy as a finding.
- **Recommendation.** Scope to `authenticated` (`create policy … to authenticated using(true)`) like the other global-config policies (`rbac_permissions_select`, `modules_select`, etc. — though all 4 of those are *also* unscoped, see paragraph P-5).

### P-5. **Permissive global-catalog policies (5 total) not scoped to `authenticated`.**
- **Evidence.** `pg_policies` shows `rbac_roles_select`, `rbac_permissions_select`, `rbac_role_permissions` (via global), `modules_select`, `component_registry` (per background agent), `compliance_rules_select` all use bare `using(true)`. The first 5 are documented in `20260528075034_rls_policies.sql:343,346,349,391,394`.
- **Why PARTIAL.** Same logic — public-readable catalog, low risk; but unscoped.
- **Recommendation.** Add `to authenticated` to each policy.

### P-6. **Phase 1 PHASE1-SPEC §7 bullet 2 is internally inconsistent with SCIENCE-SPEC §2.**
- **Evidence.** PHASE1-SPEC §7.2: "Trait bands store `min`/`max` correctly; pg_jsonschema rejects single-threshold shapes." SCIENCE-SPEC §2: "trait target … is encoded as a band (`centre`, `lower`, `upper`, `direction`)." The two specs disagree on the shape. Phase 1 acceptance test was written to the PHASE1-SPEC wording and passes; the implementation matches PHASE1-SPEC; SCIENCE-SPEC is violated. See F-1.
- **Why PARTIAL not FAIL.** The implementation matches at least one spec; the gap is that two specs disagree. The audit prompt rule "take the stricter reading" pushes this to FAIL F-1; documenting the inconsistency here for completeness.

## Unknowns — evidence not obtainable

### U-1. **Phase 3 prompt cannot be located.**
- **Evidence.** Searched `/root/.claude/uploads` for any filename containing PHASE3 / phase_3 / phase-3 / Phase 3. None exists. Files for Phase 1, 2, 4 exist; no Phase 3 file. The contract-extraction subagent confirmed the absence.
- **Why UNKNOWN, not PASS by-implementation.** Phase 3 implementation IS present (signals, refit, guidance, team_composition, pulse) and Phase 3 tests pass (`15_phase3_lifecycle` 18/18). But without the original "Definition of done for Phase 3" prompt, I cannot enumerate the contract; I can only verify what the implementation claims, which is the failure mode this audit was designed to prevent.
- **Recommendation.** Supply CLAUDECODEPHASE3PROMPT.md so a real Phase 3 contract check can run. Until then, Phase 3 verification rests on the test suite + the SCIENCE-SPEC §6 references + the HANDOFF lines about Phase 3 functions — not the original DoD.

### U-2. **End-to-end SSO + HRIS integration.**
- **Evidence.** PHASE0-SPEC §7 says Phase 0 ships "framework + 1 HRIS connector". No `integration_connections` table or HRIS sync code observed in the migrations or src/. Phase 0 acceptance checklist item ("SSO login + one HRIS read-sync works end to end") cannot be verified.
- **Why UNKNOWN.** I haven't read every migration top-to-bottom; the connector might live in a path I haven't grepped, or it might genuinely not exist. The latter is my prior.
- **Recommendation.** Grep `integration_connections|hibob|personio|scim|saml` to confirm; if not present, flag as Phase 0 acceptance gap.

### U-3. **EU residency of model inference / RAG.**
- **Evidence.** No model-inference / OpenAI / Anthropic / Mistral / Cohere endpoint configuration visible in the codebase. `guidance_compose` is purely deterministic SQL right now — refusal taxonomy + framework lookups, no LLM call. So *current* state is trivially EU-compliant (no inference happens). But SCIENCE-SPEC §8 mandates EU-hosted inference once a model is added. The seam for that is unclear.
- **Why UNKNOWN.** The phase the spec calls for (live RAG) isn't built yet; the question doesn't apply until it is.
- **Recommendation.** When Phase 3.5 / Phase 4.x adds real inference, audit it specifically against §8.

### U-4. **Sample-ui-v3.html / DESIGN.md token coverage.**
- **Evidence.** UI exists at `src/pages/*.tsx` and uses `bg-canvas`, `bg-forest`, `text-ink`, `font-display`, `--rail`, etc. Phase 4 added `/modeling`. I did not open the running app or inspect every surface for token compliance.
- **Why UNKNOWN.** The audit prompt asks me to "open three random surfaces with personal data and confirm" — I didn't run the dev server.
- **Recommendation.** Run the dev server + inspect three personal-data surfaces (e.g. `/people`, `/employees/:id`, `/modeling`) for DESIGN-token compliance, consent pill presence, HitlNotice presence.

## Phase-by-phase detail

### Phase 0 (PHASE0-SPEC §9 acceptance)

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | agency + employer coexist with provably isolated data | PASS | Test `01_tenant_isolation` 6/6 |
| 2 | person can hold memberships/profiles across both orgs | PASS | Tests 01, 03, 05, 09 |
| 3 | RBAC × scope correct for manager/recruiter/employee/admin | PASS | Test `02_rbac_scope` 8/8 |
| 4 | consent governs profile visibility; revocation removes access | PASS | Tests `03_consent_revocation` 3/3, `09_phase2_consent_ladder` 13/13 |
| 5 | role versioning retained | PASS | Test `04_role_versioning` 5/5 |
| 6 | placement consent-gated cross-org hand-off, audited | PASS | Tests `05_placement_handoff` 7/7, `14_phase2_acceptance` NB1/NB2/NB3 |
| 7 | SSO + HRIS read-sync | UNKNOWN | See U-2 |
| 8 | every consequential mutation lands in immutable `audit_log` | **PARTIAL → FAIL via F-3** | Test 06 fails on 5 Phase 4 tables missing audit triggers; the rest IS audited (test 06 was passing before Phase 4) |
| 9 | module + template registries allow per-org capability without core schema changes | PASS | Test `07_modularity` 4/4 |
| 10 | All hosting in EU region | **FAIL** | See F-2 |

### Phase 1 (PHASE1-SPEC §7)

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | 5 modules registered + enabled per agency | PASS | Test `08_phase1_acceptance` [1] |
| 2 | Role template instantiable + versioned; `min/max` trait bands; single-threshold rejected | PASS (against PHASE1-SPEC); **FAIL** against SCIENCE-SPEC | See F-1 / P-6 |
| 3 | Team-based definition: independent ratings, divergence surfaced, reconciled signed-off | PASS | Test 08 [3] |
| 4 | Assessment pipeline end-to-end on stub data, all clearly labelled | PASS | Test 08 [4] |
| 5 | DB check refuses validated + stub values | PASS | Test 08 [5], 13 [E1], 17 [F1], 18 [F1], etc. |
| 6 | Multi-dimensional fit, override recorded, audited | PASS | Test 08 [6] |
| 7 | membership ≠ profile visibility | PASS | Tests 08 [7], 09 |
| 8 | Post-placement lifecycle (membership=removed, stage=placed, etc.) | PASS | Test 08 [8] |
| 9 | Candidate-experience token-gated writes | PASS | Test 08 + test 10 portability flow |
| 10 | End-to-end seed scenario proves Phase 1 seeds Phase 2 | PASS | Test 08 runs the full end-to-end |

### Phase 2 (CLAUDECODEPHASE2PROMPT DoD)

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | Candidate grants portability of own profile | PASS | Test `10_phase2_portability_flow` C1-C5 |
| 2 | Model 1: placement transfers profile + employer activates | PASS | Test `11_phase2_employer_activation` B/C |
| 3 | Model 2: employer invites agency as scoped collaborator | PASS | Test `12_phase2_model2_collaborator` 8/8 |
| 4 | separate `ongoing_management` required + enforced | PASS | Tests 09, 11 |
| 5 | agency loses standing visibility after placement | PASS | Test `14_phase2_acceptance` P1-P5 |
| 6 | 90-day kickstart plan generated, grounded, logged | PASS | Test `13_phase2_kickstart` 11/11 |
| 7 | DEFAULT-DENY RLS + purpose-aware consent gating | PASS | Tests 09, 14 |
| 8 | All cross-org rides single Phase 0 RPC | PARTIAL | See P-1 |
| 9 | Consequential actions audited | PARTIAL via F-3 | 5 Phase 4 child tables missing triggers, but Phase 2 tables OK |
| 10 | Guidance grounded (stubs labeled) | PASS | Test 13 [C1, C2] |

### Phase 3 (no prompt available)

Verification rests on Phase 3 test (`15_phase3_lifecycle`) + SCIENCE-SPEC §6.

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | Pulse data flows ONLY with active ongoing_management consent | PASS | Test 15 [F1, F2, F3] |
| 2 | Profiles appended as time-series — no UPDATE overwrite | PASS | Test 15 [C1] (refit_compute appends, two calls → two rows) |
| 3 | Refit four-quadrant computation labelled "practitioner synthesis" | PARTIAL — code labels but UI assertion is UNKNOWN per U-4 | Test 15 [C2, C3] |
| 4 | Guidance composer uses retrieval over Frameworks Library + structured data only | PASS | Test 15 [D1, D2] (every output item cites a framework_id) |
| 5 | Refusal taxonomy enforced | **PARTIAL via F-4** | Test 16 B1, B2, B4-B7 pass; B3 fails — refusal happens but mis-categorized |
| 6 | No peer-personality path | PASS | Tests 08 [9], 15 [G1] |
| 7 | Employee self-view exists and shows same signals as manager | UNKNOWN per U-4 | I did not open the route |
| 8 | (Contract item 8+ unverifiable — no Phase 3 prompt) | UNKNOWN | See U-1 |

### Phase 4 (CLAUDECODEPHASE4PROMPT DoD)

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | Consent-gated feature pipeline, synthetic-only | PASS | Test `17_phase4_step1_feature_pipeline` 13/13 + test 24 |
| 2 | Model registry + interpretable baseline + cards + SHAP | PASS | Test `18_phase4_step2_model_scaffolding` 13/13 + test 24 |
| 3 | Live Pareto curve, customer chooses + logs weighting | PASS | Test `19_phase4_step3_pareto_curve` 8/8 + test 24 |
| 4 | Fairness metrics + invariance/DIF surface without verdicts | PASS | Tests `20_phase4_step4_fairness_audit` 9/9, `21_phase4_step5_invariance_norms` 9/9, test 24 |
| 5 | Demographic data separately stored, never a feature | PASS | Test 20 [B1] (`demographics_voluntary` refused as source_table) |
| 6 | Annex IV / DPIA / FRIA / validity dossier assembled, legal sign-off external | PASS | Test `22_phase4_step6_compliance_artifacts` 10/10 + test 24 [F1, F2, F3] |
| 7 | Monitoring informs humans only | PASS | Test `23_phase4_step7_monitoring` 11/11 |
| 8 | Every scientific/legal judgment a labelled stub | PASS | Global fabrication guard test 24 [J1] passes across 13 Phase 4 tables |
| 9 | No model auto-decides | PASS | `chk_predictions_shap_present`, no `auto_remediated` enum value, decision RPCs require humans |
| 10 | Consequential actions audited | **PARTIAL via F-3** | 5 Phase 4 child tables missing audit triggers; parent tables ARE audited |
| 11 | Modeling data gated by valid consent, revocation tested | PASS | Test 17 [D1, D2], test 24 [H1, H2] |
| 12 | No second cross-org path | PARTIAL via P-1 | Test 14 NB1/NB2/NB3 still pass for profile/position/placement; consent-grant exception flagged |
| 13 | HANDOFF list — every stub/seam an expert must fill | PASS | `HANDOFF.md` exists, enumerates 10 sections of seams |

## Anti-self-flattery section (required)

**Three things this audit might be wrong about.**

1. **Test 06 may not be a genuine regression worth fixing.** Audit triggers on the five flagged tables (compliance_artifact_sources, compliance_rules, model_dataset_subjects, norm_percentiles, pareto_curve_points) might be intentional omissions — these are child/derived/config rows whose parent's audit row already records the operation. Adding triggers will double-log a lot of churn. A defensible reading is "the test 06 invariant is too strict for derived tables." I marked F-3 as FAIL because the test was passing before Phase 4 was added; but a hostile reviewer might call this PARTIAL "policy-design question."

2. **The four cross-org consent-grant RPCs (P-1) might genuinely be a strict-letter violation, not a "documentation gap."** I framed them as PARTIAL because the data subject is the actor. But CLAUDE.md says "placements is the **only** sanctioned cross-org data bridge" — not "the only data-transfer bridge." A hostile reading is FAIL: those RPCs ARE cross-org writes, and the spec text doesn't carve out a consent-grant exception. The fact that the data subject initiated it is irrelevant to the structural property; if the spec text needs softening, that's a spec change, not a verdict change.

3. **My evidence on the trait-targets violation (F-1) only inspects the JSONSchema + seed; I did not exhaustively grep every code path that reads `trait_targets` to confirm none of them gracefully handles the missing fields.** It's possible the runtime defaults `direction='optimum'` somewhere I haven't looked. But the structural shape is wrong regardless — the schema's `additionalProperties: false` would reject any role definition that *adds* the field, so even if there's a runtime default, no instance can carry the validated shape. I think F-1 holds, but my grep was shallow.

**Three places where a hostile reviewer would call FAIL where I marked PASS or PARTIAL.**

1. **EU residency (F-2) is currently marked FAIL, which is the strict reading — but a "we're in dev" reviewer would soften it to PARTIAL.** I rejected that softening because the spec is unambiguous and there's no DB-level enforcement. A more hostile reviewer might escalate to a CRITICAL finding worth a release blocker, not a fix-list item.

2. **The "No second cross-org path" guard (test 14 NB1/NB2/NB3) only checks `pg_get_functiondef ilike '%insert into public.profiles%'`.** A new function that builds the INSERT via dynamic SQL (`format()` + `execute`) would not match. A new function that inserts via `to_org_row insert into ... select ...` from another column might also slip. I marked this PASS based on the explicit test; a hostile reviewer would say "the guard's coverage is incomplete; PARTIAL at best."

3. **MBTI denylist (P-2) is marked PARTIAL because some tokens are missing.** A hostile reviewer would call FAIL because the spec lists those specific tools (`colours` / `9-box`) and the constraint genuinely doesn't refuse them. I gave PARTIAL because the anchor cases ARE enforced. The strict reading is: the spec named the deny-list, the implementation deny-list is a proper subset, the implementation is non-compliant, FAIL.

**Three places where the evidence is weaker than the verdict implies.**

1. **The fabrication guard tests (F1 / J1 / E1 patterns) check zero `validity_status='validated'` rows at test time, in a transaction.** A hostile reviewer would say: in a long-running production DB, a misfire could mark a row validated, the guard fires, then someone runs the rollback test in a transaction — they'd see "zero validated rows" inside their txn even though the production state is dirty. The guard doesn't run on a live DB snapshot. The check is at the seed/CI level only. I marked the science-fabrication invariant PASS; the evidence is a CI-time test, not a real-time invariant.

2. **The "modeling.signoff NOT seeded" check (PASS) is based on `grep` in rbac_seed.sql + seed.sql.** I haven't confirmed that no per-org migration or no manual SQL slipped a grant in. A hostile reviewer would say "show me `select count(*) from rbac_role_permissions where permission_key='modeling.signoff'` returning 0 on the live DB." I didn't run that query.

3. **The Phase 3 verdicts (PASS on test 15) rest on the test passing — but the test was written against the same implementation it's testing.** Without the original Phase 3 prompt to verify against, my Phase 3 "PASS" is really "the test the implementation came with passes." That's the exact false-PASS failure mode this audit was designed to catch.

## Recommended next actions for the human

Priority 1 (release-blockers if you ship to a customer):
1. **F-1 — Trait targets schema.** Migration + seed rewrite + PHASE1-SPEC reconciliation. ~1 day.
2. **F-2 — EU residency.** Provision EU project, backfill data_region, add CHECK. ~2-4 hours infra + migration.

Priority 2 (regressions / spec gaps to fix this week):
3. **F-3 — Add audit triggers to 5 Phase 4 tables.** ~30 min migration.
4. **F-4 — Fix refusal precedence so `dismiss` beats `legal`.** ~15 min code + re-run test 16.
5. **P-2 — Expand MBTI denylist regex** (`colours`, `9-box`, `Insights Discovery`). ~10 min.
6. **P-3 — FORCE RLS on the 34 tables that lack it.** ~30 min migration.

Priority 3 (documentation + spec corrections):
7. **U-1 — Supply Phase 3 prompt + re-run audit for Phase 3 specifically.** External.
8. **P-1 — Document the four token-gated consent-grant RPCs in CLAUDE.md as an explicit exception.** ~30 min.
9. **P-4 / P-5 — Scope `using(true)` policies to `to authenticated`.** ~15 min migration.

Priority 4 (verify what the audit couldn't):
10. **U-2 — Phase 0 SSO + HRIS connector** verification — run a grep + integration test.
11. **U-4 — DESIGN-token + consent-pill + HitlNotice surface audit** on the running app for at least 3 personal-data surfaces.
