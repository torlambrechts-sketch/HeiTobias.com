# Phase 1 — Recruiter OS: Technical Specification

> **Scope:** the standalone agency-facing product. Phase 1 makes placements
> rigorous and defensible, and every placement seeds the data spine
> (role + person profile) that Phase 2 will activate inside an employer.
>
> Phase 1 builds on Phase 0 — see `PHASE0-SPEC.md`. Every capability registers
> as a **module** in `public.modules` / `public.org_modules`; nothing is
> hardcoded that the registry should configure. Phase 0 core tables are read
> and extended via new module tables; they are **not edited**.

---

## 0. Design principles (inherits Phase 0)

1. **Database-first, modular, template-driven** (Phase 0 §0).
2. **RLS DEFAULT-DENY** on every new module table. Personal-data visibility gated by `consent_active()` — see `PHASE0-SPEC.md` §4.4: **membership ≠ profile visibility**.
3. **Atomic RPCs** for any multi-table mutation that must be policy-checked.
4. **Audit everything consequential** through the existing `_audit_row` triggers.
5. **Human-in-the-loop**, always (CLAUDE.md). Every fit / recommendation surface records the human decision + any override.
6. **Validated science is pluggable, never invented** — see §4 of this document and the *Validated science & DEV STUBs* section in `CLAUDE.md`.

---

## 1. Capability modules

Each capability registers a row in `public.modules` and is enabled per agency via `public.org_modules`. The five modules:

| key                    | name                          | provides                                                                |
|------------------------|-------------------------------|-------------------------------------------------------------------------|
| `role_architecture`    | Role Architecture Engine      | Role templates, weighted competencies, trait target ranges (bands)      |
| `team_definition`      | Team-based Role Definition    | Independent ratings, surfaced divergence, reconciled signed-off version |
| `assessment_engine`    | Assessment Engine             | Instruments, items, invites, responses, scoring pipeline (pluggable)    |
| `fit_scoring`          | Fit Scoring & Placement Report| Multi-dimensional fit, placement reports, hiring decision capture       |
| `candidate_experience` | Candidate Experience          | No-login mobile flow, token-gated invites, consent-first responses      |

---

## 2. New module tables (logical sketch)

Naming: `snake_case`, plural. Standard columns (`id`, `created_at`, `updated_at`, `org_id` for tenant-scoped, `deleted_at` where retention requires) per Phase 0 conventions.

### 2.1 Role Architecture

- `competency_frameworks` — global (`org_id IS NULL`) or org-scoped competency dictionaries. Versioned (`supersedes_id`). `body_json` validated by `pg_jsonschema` against a fixed shape `{competencies: [{key, label, family, definition}]}`.
- Role templates: stored in `public.templates(kind='role')` (Phase 0). Tighten the per-kind body shape to require:
  ```
  { competencies: [{key, weight}], trait_targets: [{trait, min, max}],
    cognitive_demand: {...|null}, context_factors: [...|null],
    success_criteria: [...|null], evolution_vector: {...|null} }
  ```
  Trait targets are **ranges** (`min`/`max`) — never single thresholds.
- `roles_catalog.definition_json` (Phase 0) gets the same tightened shape; existing `role_version_create` RPC continues to drive versioning.

### 2.2 Team-based Role Definition

- `role_definition_evaluations` — one row per evaluator per criterion per requisition. Carries `submitted_at` and a **write-lock**: an evaluator cannot read other evaluators' rows until their own `submitted_at` is non-null (enforced in RLS). No update after submit; corrections create a new row.
- `role_definition_reconciliations` — the divergence calculation + reconciled output. References the evaluation rows it consumed. Produces a new `roles_catalog` row via `role_version_create` with full `authored_by_json` attribution.
- **Hard ban**: no table that captures peers' ratings of each other's personalities exists. Team-composition derivations operate on members' **own validated profiles** only.

### 2.3 Assessment Engine

- `assessment_instruments` — the catalog. Carries `vendor`, `licensed_by`, **`validity_status enum`** (`dev_stub | licensed | validated`), `version`.
- `assessment_items` — items within an instrument. May carry `_dev_stub boolean`.
- `assessment_responses` — a candidate's responses to items in a specific assessment. Consent-scoped (FK to `consent_grants`, enforced in RLS).
- `assessment_scores` — derived scores. Carries `validity_status`, `_dev_stub`, and the DB-enforced check from CLAUDE.md *Validated science & DEV STUBs*.
- A `dev_stub_score(...)` SECURITY DEFINER function returning placeholder values + setting `validity_flags_json.dev_stub = true`. The scoring **interface** is clean enough that a licensed instrument's scoring drops in as a single function-pointer / module config change.

### 2.4 Fit Scoring & Placement Report

- `fit_results` — multi-dimensional fit per finalist per requisition. JSONB schema:
  ```
  { per_competency: [{key, person_value, target_weight, fit_score}],
    trait_ranges:   [{trait, person_value, band:{min,max}, status:"in"|"below"|"above"}],
    cognitive_demand: {person, role, fit},
    context_fit:    {...},
    overall_summary: {...}  // multi-axis, never a single number }
  ```
  pg_jsonschema-validated. The fit RPC reads role bands + person scores and writes this row.
- `placement_reports` — org-branded export (HTML/PDF generation in app code), linked to the `fit_results` row.
- `hiring_decisions` — the human decision (`decision enum: advance/reject/hire/withdraw`), free-text rationale, `overrode_recommendation boolean`, `decided_by uuid → people`. **Required before `placement_execute` can transfer.**

### 2.5 Candidate Experience

- `assessment_invites` — one-time token, `expires_at`, `consent_required boolean`, `consent_recorded_id uuid → consent_grants` (nullable until captured). Token-gated RLS: a token-bearer (anon role with a header) can write `assessment_responses` for exactly their invite.
- The candidate is represented as a `people` row + an `invited`-status `memberships` row in the agency org (per `PHASE0-SPEC.md` §5.5). The membership enables pipeline visibility; the consent grant enables data visibility.

---

## 3. Cross-module behaviour

### 3.1 The placement flow is consent-gated and atomic

The existing `placement_execute` RPC (Phase 0) is extended — not replaced — to:
1. Require a `hiring_decisions` row for the (requisition, candidate) pair with `decision = 'hire'`.
2. Set the candidate's agency-pipeline membership `status = 'removed'` atomically with the hand-off (per `PHASE0-SPEC.md` §5.5).
3. Continue to require an active `profile_portability` consent for the cross-org profile copy.

No new cross-org data paths are introduced. The placement RPC remains the **only** sanctioned bridge.

### 3.2 Audit

Every new table is attached to `_audit_row` (the Phase 0 generic trigger). The `hiring_decisions` UPDATE/INSERT writes through `audit_log_event` for richer entity-typing (`'hiring.decision'`) and to record the rationale text in `before_json`/`after_json`.

---

## 4. The I/O-psychology boundary

We do not have a credentialed I/O psychologist, and validated instruments will be **licensed, not invented**. The product engineering contract:

**We build**: the assessment engine, instrument + item data model, pluggable scoring pipeline, validity-check framework, norms / bands data model, fit computation that reads role bands + person scores, candidate-experience flow, recruiter UI.

**We do not build**: psychometric items, real trait/cognitive scoring formulas, fabricated norm tables, asserted validity coefficients. Where real instrument content or scoring is required, the engine carries a **labeled stub** + an obviously-fake sample dataset:

- `validity_status = 'dev_stub'` on the instrument row.
- `_dev_stub = true` on any value-carrying row.
- TS comment `// DEV STUB — replace with licensed instrument + I/O-validated scoring` at every stub use site.
- UI badge wherever stub data is rendered (so reviewers see immediately what is and isn't real).
- DB check constraint making `validity_status = 'validated'` impossible without real values (see CLAUDE.md *Validated science & DEV STUBs*).
- pgTAP guard test asserting **no** `validity_status = 'validated'` rows exist in any seed/fixture.

The goal is a fully working pipeline with a **clean seam** where validated science plugs in — never science we faked.

---

## 5. Candidate experience: consent before data

The candidate-experience module must:

1. **Capture consent up front**, before any response is stored. The consent grant is a `consent_grants` row with `purpose = 'hiring_decision'` granted to the agency org by the candidate. No grant → no response row may be created (enforced by an INSERT policy that requires a matching active grant referenced through the invite).
2. **Use the invited-membership pattern** for pipeline visibility (`PHASE0-SPEC.md` §5.5) — never add the candidate's profile/assessment data to a recruiter's reach simply because the membership exists.
3. **Token-scope writes**: the anon client carries an invite-token header; RLS on `assessment_responses` admits writes for exactly that invite's rows.
4. **Mobile-first**, branded from `organizations.settings_json`, single-page flow under `/take/[token]`.

---

## 6. What Phase 1 deliberately excludes

- No ongoing-lifecycle / manager features (90-day plan, manager guidance, pulse, re-fit) — Phase 2/3.
- No predictive models or bias-audit automation — Phase 4.
- No real psychometric content or scoring — see §4.
- No peer-personality rating — `CLAUDE.md` hard "never" list.
- No new cross-org data paths — the consent-gated `placement_execute` RPC stays the only bridge.

---

## 7. Phase 1 acceptance checklist

Phase 1 is "done" when:

- [ ] All five modules are registered in `public.modules` and can be enabled per agency via `public.org_modules` with valid `config_json`.
- [ ] A role profile can be instantiated from a `templates(kind='role')` row, tuned, and versioned via `role_version_create`. Trait bands store `min`/`max` correctly; pg_jsonschema rejects single-threshold shapes.
- [ ] Team-based definition captures **independent** evaluator ratings (RLS blocks cross-reads until submitted), surfaces divergence per criterion, and produces a reconciled signed-off role version with full attribution. **No peer-personality-rating table exists.**
- [ ] Assessment pipeline runs end-to-end on stub data: invite → consent capture → response → stub scoring → profile row. Every output is clearly labeled (`validity_status='dev_stub'`, `_dev_stub=true`, UI badge).
- [ ] DB check on score-bearing tables refuses `validity_status='validated'` rows that carry stub values. Guard test asserts seed/fixtures contain zero `'validated'` rows.
- [ ] Fit computation produces multi-dimensional `fit_results` — per-competency, trait-range (in/below/above), cognitive-demand, context. **Never** collapses to a single verdict number. Override is recorded to `hiring_decisions` and audited.
- [ ] **Acceptance — membership ≠ profile visibility** (per `PHASE0-SPEC.md` §4.4): a candidate has an active `invited` agency membership; with consent revoked, the recruiter `select * from people` returns the candidate row; the recruiter `select * from profiles where person_id = …` returns zero. Pipeline-entry visible; data invisible.
- [ ] **Acceptance — post-placement lifecycle** (per `PHASE0-SPEC.md` §5.5): after `placement_execute`, the candidate's agency-pipeline `memberships.status = 'removed'`; the requisition's candidate row shows `stage = 'placed'`; the recruiter no longer sees the person as an active agency member.
- [ ] Candidate-experience flow: token-gated writes only, consent captured before any response stored, mobile-first per DESIGN.md.
- [ ] End-to-end seed scenario: agency defines a team-rated role (divergence surfaced + reconciled) → 3 finalists assessed (stub) → multi-dim fit → placement report → recorded human decision → `placement_execute` hands off to an employer org via the Phase 0 consent-gated RPC. **Proves Phase 1 seeds the spine for Phase 2.**

---

## 8. Reference

- `CLAUDE.md` — engineering rules; *Validated science & DEV STUBs* is the home of the I/O seam discipline.
- `PHASE0-SPEC.md` — the substrate Phase 1 builds on. §4.4 and §5.5 are load-bearing for this phase.
- `DESIGN.md` — UI system. All recruiter-facing surfaces conform.
