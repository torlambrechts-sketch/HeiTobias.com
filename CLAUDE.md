# CLAUDE.md — Engineering & Architecture Guide

> This file instructs Claude Code (and human developers) how to build in this repository. It encodes the non-negotiable architectural principles. **Read this before writing any code.** When a request conflicts with these principles, follow the principles and flag the conflict.

---

## Project summary

A **talent lifecycle platform**: candidate → hire → high-performing employee, on one continuous data spine. Two co-equal entities — **Role Profile** (the target) and **Person Profile** (what's measured) — and a **recruiter-channel land-and-expand** motion (agencies seed profiles; employers inherit them and activate the lifecycle layer).

**Stack:** PostgreSQL (Supabase) · Row-Level Security · Edge/Serverless Functions · React + TypeScript · Tailwind + shadcn/ui (see `DESIGN.md`) · EU-region hosting.

---

## The four pillars (do not violate)

### 1. Database-first
- **The schema is the source of truth.** Model the data before writing UI or endpoints.
- Integrity and security rules live **in the database** (constraints, foreign keys, `check`s, RLS, triggers, `security definer` RPCs) wherever they protect data — not only in application code. App code may add UX validation, but must never be the *only* line of defense.
- Prefer **RPC functions** (Postgres functions exposed via Supabase) for multi-step writes that must be atomic and policy-checked. Avoid orchestrating critical multi-table writes purely in client code.
- Migrations are the unit of change. Every schema change is a reviewed, versioned migration. No ad-hoc schema edits.
- Generate TypeScript types **from** the database schema; never hand-maintain types that the DB already defines.

### 2. Modular
- Every capability is a **self-contained module** with its own tables, registered in the `modules` registry and enabled per-org via `org_modules`.
- **Adding a module must not require editing core tables.** Core (organizations, people, teams, roles_catalog, positions, profiles, consent, rbac, audit) is stable; capabilities compose on top.
- Cross-module interaction goes through **defined interfaces / events**, not direct table reach-ins. E.g. a vernerunde-style "finding" auto-creating a "task" is an event-driven workflow, not a hardcoded join. (This mirrors the prior Conscia modular pattern: configurable modules, cross-module workflow automation, central registries.)
- A module declares its config schema (`modules.config_schema_json`); per-org config lives in `org_modules.config_json`. Behavior is configured by **data**, not branching code.

### 3. Template-driven
- Roles, assessments, layouts, notification content, and workflows are **defined as data (templates)**, not hardcoded.
- Templates are **centrally defined and instance-overridable**: a global template (`templates.org_id is null`) can be instantiated and tuned per org. Role profiles especially ship as advisor-validated templates that teams tune — never blank forms.
- UI layouts reference a central `component_registry` (the `COMPONENT_REGISTRY` pattern): a layout is data that maps registered components to slots, so pages are composed/configured rather than bespoke-coded each time.
- When adding a new "kind" of configurable thing, extend the template system — do not introduce a parallel hardcoded path.

### 4. Security & privacy by construction
- **Multi-tenant from row zero.** Every domain row has `org_id`. Isolation is enforced by **RLS at the database layer**, never only in the API or UI.
- **RLS default-deny.** A table with no policy is unreadable. A new role sees nothing until explicitly granted. Authorization = **role (actions) × scope (rows)**.
- **Consent is core.** Personal data visibility is gated by active `consent_grants` with enforced **purpose limitation**. The data subject (the `person`) owns their data. Revoking consent must remove access (enforced in RLS predicates).
- **The placement hand-off is the only sanctioned cross-org data bridge** — consent-gated and fully audited. No other path may move data between tenants.
- **Everything consequential is audited** into an **immutable, insert-only** `audit_log`.
- **EU data residency** is mandatory. No personal data leaves the EU region. Third-party processors must be EU-compliant.
- **Human-in-the-loop for high-risk decisions.** Hiring is high-risk under the EU AI Act: any fit score or model output **informs** a human decision and must never auto-decide. Preserve overrides and log them.
- **LLM guidance is grounded, never freeform.** The guidance composer must generate from the frameworks library via retrieval (RAG) + structured profile/role data. Never emit freeform advice about a named person from model priors alone. Log inputs/outputs for auditability.

---

## Entity model (the vocabulary — use these names)

- `organizations` — tenant root; `type` is `agency` or `employer`.
- `people` — **global** person identity (candidate/employee/manager/recruiter are states, not separate tables).
- `memberships` / `membership_roles` — person↔org link + RBAC roles.
- `departments` (self-tree) → `teams` → `team_members`.
- `roles_catalog` — the **Role Profile**, versioned, template-or-instance. **`role ≠ position ≠ job title`.**
- `positions` — an instance of a role a specific person fills; carries reporting lines.
- `profiles` — the **Person Profile**, time-versioned (re-fit time series), consent-scoped.
- `assessments` — instances that produce profiles.
- `requisitions` / `requisition_candidates` / `placements` — the hiring transaction; `placements` triggers the hand-off.
- `consent_grants` — the consent ledger (data subject = owner; purpose-limited; revocable).
- `rbac_roles` / `rbac_permissions` / `rbac_role_permissions` — RBAC.
- `modules` / `org_modules` / `templates` / `component_registry` — modularity & template backbone.
- `audit_log` — immutable.

See `PHASE0-SPEC.md` for full field-level definitions and the ER summary.

---

## Conventions

- **SQL:** `snake_case`, plural tables. Every table: `id uuid pk default gen_random_uuid()`, `created_at`, `updated_at` (trigger-maintained); domain tables add `org_id`; add `deleted_at` for soft-delete where retention requires.
- **RLS helpers:** `is_self()`, `has_permission(org_id, key)`, `in_scope(org_id, person_id)`, `consent_active(consent_id)` — `security definer`. Reuse these in policies; don't inline auth logic.
- **TypeScript:** strict mode. Types generated from the DB. No `any` on domain models.
- **Frontend:** React + TypeScript, Tailwind + shadcn/ui per `DESIGN.md`. No browser storage (`localStorage`/`sessionStorage`) for sensitive data. Components consume the component registry where pages are layout-driven.
- **Writes:** critical multi-table mutations go through atomic, policy-checked RPC functions.
- **i18n:** all user-facing strings localizable (nb-NO / sv-SE / da-DK / en). No hardcoded copy.

---

## Validated science & DEV STUBs

Anywhere the product reads or produces values that depend on validated psychometric science — assessment items, scoring formulas, norm tables, fit weights, validity coefficients — the **engine and pipeline are ours to build; the content must be pluggable**. We do not invent science.

The seam is enforced at the database layer, not by convention alone:

- **Provenance enum** — every "scientific" surface carries a `validity_status` enum: `dev_stub | licensed | validated`. Defined once, used everywhere a value of that kind originates. `dev_stub` = our placeholder; `licensed` = a real instrument's content is plugged in; `validated` = the instrument + scoring are I/O-validated against our population.
- **Per-value fabrication flag** — rows that carry a stub numeric value (score / norm / threshold) also carry a `_dev_stub boolean` column. The two columns describe different scopes: `validity_status` is *instrument-level provenance*; `_dev_stub` is *value-level fabrication*. Both exist; neither alone is sufficient.
- **DB-enforced check** — every table holding a score-like value carries
  ```sql
  CHECK (
    validity_status <> 'validated'
    OR (relevant_value IS NOT NULL AND COALESCE(_dev_stub, false) = false)
  )
  ```
  A `dev_stub` row cannot be silently promoted to `validated` without real values present. This is what makes the seam load-bearing rather than aspirational.
- **Seed / fixture guard** — automated tests assert that the count of `validity_status = 'validated'` rows in any seed or fixture file is **zero**. No stub ever ships looking real.

Stubs must also be **visible at the use site**: `// DEV STUB — replace with licensed instrument + I/O-validated scoring` comments on TS code; clearly-fake sample values (e.g. `0.42`, `"placeholder_competency"`) in seed; UI badges where stub data is rendered.

The seam matters because we cannot fabricate science. We can fabricate a clearly-labeled engine; we cannot fabricate a labeled-as-validated number.

---

## When building a new feature — checklist

1. **Model first.** Add/extend tables via migration. Is it core or a module? (Default: module.)
2. **RLS.** Write default-deny policies before exposing the table. Add a cross-org isolation test.
3. **Consent.** Does this touch personal data? Gate visibility on an active, correctly-purposed `consent_grant`.
4. **Scope.** Define role × scope visibility; reuse RBAC helpers.
5. **Audit.** Ensure consequential mutations write to `audit_log`.
6. **Template/config.** If it's configurable, make it a template + per-org config — not branching code.
7. **Human-in-the-loop.** If it produces a recommendation about a person, ensure a human decides and the override is logged.
8. **Types & tests.** Regenerate DB types; test RLS isolation and consent-revocation behavior.
9. **i18n & design.** Localizable strings; UI via shadcn/ui + design tokens.

---

## Hard "never" list

- ❌ Never enforce tenant isolation or authorization in the UI/API only — it must hold at the DB (RLS).
- ❌ Never move data between orgs except via a consent-gated, audited `placement`.
- ❌ Never let any gate other than `consent_active()` serve as the visibility check for personal data (profiles/assessments). Memberships, RBAC permissions, and scope checks govern *existence and operations*; consent governs *data*. (See `PHASE0-SPEC.md` §4.4.)
- ❌ Never let a model/score auto-make a hiring or performance decision — human-in-the-loop, always. (GDPR Art. 22 + EU AI Act Art. 14; see `SCIENCE-SPEC.md` §5.)
- ❌ Never emit freeform LLM advice about a named person from priors — ground it (RAG + structured data) and log it. The guidance composer must REFUSE medical / legal / dismissal / compensation queries (see `SCIENCE-SPEC.md` §6).
- ❌ Never store personal data outside the EU region.
- ❌ Never add a hardcoded path for something the template/module system should configure.
- ❌ Never implement peer-rates-peer personality evaluation — team composition is built from members' **own** validated profiles only.
- ❌ Never ship a row with `validity_status = 'validated'` that carries fabricated values; the DB enforces this (see the *Validated science & DEV STUBs* section).
- ❌ Never ingest MBTI, DISC, learning-styles, or Belbin as scored instruments — `SCIENCE-SPEC.md` §3.2 deny-list, enforced by DB CHECK on `assessment_instruments`.
- ❌ Never model a trait target as a single threshold or "more is better" — trait targets are bands with direction + justification (`SCIENCE-SPEC.md` §2).
- ❌ Never hand-maintain types the database already defines.

---

## Reference docs in this repo

- `PHASE0-SPEC.md` — full Phase 0 data model, RLS approach, consent, acceptance checklist.
- `SCIENCE-SPEC.md` — I/O psychology + EU AI Act / GDPR compliance: instrument allow/deny list, trait-band rules, decision architecture, guidance refusal categories, fairness practices. **Load-bearing for anything touching measurement, fit, fairness, or post-hire decision support.**
- `DESIGN.md` — UI system: shadcn/ui base + the project's distinctive visual style and tokens.
- (Project brief / architecture / build-plan documents describe the product strategy and phasing.)
