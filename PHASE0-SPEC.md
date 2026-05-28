# Phase 0 — Core Foundation: Technical Specification

> **Scope:** the platform substrate that every later phase depends on. Build this **thin but correct**. You do not need every integration on day one, but the entity model, multi-tenancy, RLS, consent ledger, and EU residency must be right from the first commit — they cannot be retrofitted without a painful rebuild.
>
> **Stack:** PostgreSQL (Supabase) · Row-Level Security · Edge Functions · React frontend · EU region hosting. Database-first, modular, template-driven.

---

## 0. Design principles for Phase 0

1. **Database-first.** The schema is the source of truth. Business rules live in the database (constraints, RLS, triggers, RPC functions) wherever they protect data integrity or security, not only in application code.
2. **Multi-tenant from row zero.** Every domain row carries a tenant boundary. Isolation is enforced at the database layer via RLS, never only in the UI or API.
3. **Modular.** Each capability is a self-contained module with its own tables, registered in a central registry. Adding a module must not require editing core tables.
4. **Template-driven.** Roles, layouts, assessments, notification content, and workflows are defined as data (templates), not hardcoded. Centrally defined, instance-overridable.
5. **Consent & audit are core, not features.** The consent ledger and immutable audit log exist before any personal data is written.
6. **Least privilege by default.** A new role sees nothing until explicitly granted. RLS default-deny.

---

## 1. Tenancy model

There are **two tenant types** that must coexist and exchange data in a controlled way:

| Tenant type | Who | Primary surfaces |
|---|---|---|
| `agency` | Recruitment agencies (acquisition channel) | Recruiter workspace: Define + Assess |
| `employer` | Hiring companies (retention layer) | Manager / Employee / People-ops: Manage + Re-fit + Grow |

- Every domain row has an `org_id` foreign key to `organizations`.
- RLS isolates rows so a member of org A can never read org B's data — **except** through an explicit, consent-gated, audited cross-org share (the placement hand-off, §7).
- A single human (a `person`) may relate to multiple orgs (e.g. a candidate assessed by an agency, later an employee at an employer). The **person identity is global**; their *memberships and visibility* are per-org and consent-scoped.

---

## 2. Core entities (logical model)

> Naming: `snake_case` tables, plural. Every table has `id uuid pk default gen_random_uuid()`, `created_at timestamptz`, `updated_at timestamptz`, and (for domain tables) `org_id uuid`. Soft-delete via `deleted_at timestamptz null` where retention requires it.

### 2.1 `organizations`
The tenant root.
- `id`, `name`, `type` (`agency` | `employer`), `country` (ISO, default `NO`), `locale_default` (`nb-NO` | `sv-SE` | `da-DK` | `en`), `data_region` (default `eu`), `status`, `settings_json`.
- Root of all RLS scoping.

### 2.2 `people`
The **universal person entity**. A candidate, employee, manager, recruiter are all `people` in different states/memberships.
- `id`, `primary_email` (unique, citext), `full_name`, `given_name`, `family_name`, `auth_user_id` (nullable — links to Supabase auth when the person has a login), `global_consent_state`.
- **Not** org-scoped at the root: a person can exist across the candidate→employee journey. Org relationships are expressed via `memberships` and `positions`.

### 2.3 `memberships`
Connects a `person` to an `organization` with a set of roles.
- `id`, `org_id`, `person_id`, `status` (`invited`|`active`|`suspended`|`removed`), `joined_at`.
- A person can have memberships in multiple orgs (agency recruiter; later employer employee).
- Roles are attached via `membership_roles` (§5).

### 2.4 `departments`
Hierarchical org structure (employer tenants primarily).
- `id`, `org_id`, `name`, `parent_department_id` (nullable, self-ref → tree).

### 2.5 `teams`
- `id`, `org_id`, `department_id` (nullable), `name`, `lead_person_id` (nullable).
- The unit the **team composition engine** and **team-based role definition** operate on.

### 2.6 `team_members`
- `id`, `org_id`, `team_id`, `person_id`, `role_in_team` (free/enum), `is_lead`.

### 2.7 `roles_catalog` (the Role Profile — Entity A)
**First-class, versioned record. `role ≠ position ≠ job title`.**
- `id`, `org_id` (nullable for global templates), `title`, `family`, `is_template` (bool), `template_source_id` (nullable → which template it was instantiated from), `version`, `status` (`draft`|`active`|`archived`), `definition_json` (weighted competencies, trait target ranges, cognitive demand, context factors, success criteria, evolution vector), `authored_by_json` (team-authoring attribution), `signed_off_by`, `signed_off_at`.
- Versioning: a new version creates a new row with incremented `version` and a `supersedes_id` pointer; old versions are retained for re-fit history and audit.

### 2.8 `positions`
An **instance of a role a specific person fills** inside an org.
- `id`, `org_id`, `role_id` (→ `roles_catalog`), `person_id` (nullable until filled), `team_id`, `manager_position_id` (nullable → reporting line), `status` (`open`|`filled`|`closed`), `start_date`, `end_date`.

### 2.9 `profiles` (Person Profile — Entity B)
- `id`, `person_id`, `org_id` (the org context the profile data is visible in), `source` (`assessment`|`refit`|`import`), `traits_json`, `cognitive_json`, `values_json`, `derived_json` (strengths/friction), `consent_id` (→ consent ledger), `valid_from`, `valid_to` (nullable — supports the re-fit time series).

### 2.10 `assessments`
The assessment instances that produce profiles.
- `id`, `org_id`, `person_id`, `type` (`cognitive`|`personality`|`values`|`composite`), `instrument_key`, `status` (`invited`|`in_progress`|`completed`|`expired`), `validity_flags_json`, `result_profile_id` (→ `profiles`), `completed_at`.

### 2.11 `requisitions`
The hiring transaction object (agency or employer initiated).
- `id`, `org_id` (owning org), `role_id`, `team_id`, `status` (`open`|`shortlisting`|`placed`|`closed`), `collaborating_org_id` (nullable — for Model 2 shared workspace), `created_by`.

### 2.12 `requisition_candidates`
- `id`, `org_id`, `requisition_id`, `person_id`, `stage`, `fit_score_json` (vs. role + team gap), `decision`.

### 2.13 `placements`
The **closed event that triggers the consent-gated hand-off**.
- `id`, `requisition_id`, `person_id`, `from_org_id` (agency), `to_org_id` (employer), `status` (`pending_consent`|`transferred`|`activated`|`revoked`), `consent_id`, `transferred_at`.
- Creates/links a `position` in the employer org and copies/links the candidate's `profile` under the consent grant.

### 2.14 Module & template registries (modularity backbone)
- `modules` — `id`, `key`, `name`, `version`, `status`, `config_schema_json`. Central registry; a capability is "switched on" per org via `org_modules`.
- `org_modules` — `id`, `org_id`, `module_key`, `enabled`, `config_json`.
- `templates` — `id`, `org_id` (nullable=global), `kind` (`role`|`assessment`|`layout`|`notification`|`workflow`), `key`, `version`, `body_json`. Centrally defined, instance-overridable.
- `component_registry` (UI/layout) — `id`, `key`, `kind`, `schema_json` — the central registry layouts reference (mirrors the LayoutAdmin/COMPONENT_REGISTRY pattern from prior work).

---

## 3. Entity-relationship summary

```
organizations (tenant: agency | employer)
  ├─< memberships >── people (global identity)
  │      └─< membership_roles >── rbac_roles
  ├─< departments (self-tree)
  │      └─< teams ──< team_members >── people
  ├─< roles_catalog (versioned; templates + instances)
  │      └─< positions >── people   (role instance a person fills)
  ├─< requisitions ── roles_catalog
  │      ├─< requisition_candidates >── people
  │      └─── placements ── people   (from_org agency → to_org employer)
  ├─< assessments >── people ──> profiles (Entity B, time-versioned)
  ├─< org_modules ── modules
  └─< templates / component_registry

consent_grants  ──referenced by──> profiles, placements, assessments
audit_log       ──records──> every consequential mutation
```

Key cardinalities:
- `roles_catalog (1) ──< (N) positions` — one role, many filled instances.
- `people (1) ──< (N) profiles` — one person, many profile versions over tenure (re-fit time series).
- `placements` is the **only** sanctioned cross-org data bridge.

---

## 4. Consent & data ownership (GDPR core)

### 4.1 `consent_grants`
- `id`, `person_id` (the data subject — owns the data), `granted_to_org_id`, `purpose` (enum: `hiring_decision`|`profile_portability`|`ongoing_management`|`research_anonymized`), `scope_json`, `legal_basis` (`consent`|`legitimate_interest`|`contract`), `status` (`active`|`revoked`|`expired`), `granted_at`, `revoked_at`, `expires_at`.
- **Purpose limitation enforced:** a profile transferred for `hiring_decision` cannot be used for `ongoing_management` without a separate grant.
- **Revocable:** revoking flips dependent visibility (enforced in RLS predicates that check an active grant).

### 4.2 Three-party hand-off rule
The candidate (`person`) is the data owner. The agency generated the profile; the employer receives it. Transfer requires an **active `consent_grant` with purpose `profile_portability`** from the candidate, naming the `to_org_id`. The transfer is recorded in `placements` and `audit_log`.

### 4.3 Data subject rights
- Export (portability), rectification, erasure (respecting legal-retention windows), and a consent dashboard — all queryable from `consent_grants` + `people` + `profiles`.

---

## 5. Access, rights & security

### 5.1 RBAC tables
- `rbac_roles` — `id`, `org_id` (nullable=system role), `key` (`recruiter`|`hiring_manager`|`people_ops_admin`|`manager`|`employee`|`org_admin`), `name`.
- `rbac_permissions` — `id`, `key` (e.g. `role.create`, `profile.read`, `placement.transfer`), `description`.
- `rbac_role_permissions` — `role_id`, `permission_id`.
- `membership_roles` — `membership_id`, `rbac_role_id`. (A membership can hold multiple roles.)

### 5.2 Scope model
Authorization = **role (what actions) × scope (which rows)**. Scope is derived from the org tree and reporting lines:
- `manager` → only `people`/`profiles`/`positions` where the target's `position.manager_position_id` chain resolves to the manager's position.
- `recruiter` → only `requisitions`/`requisition_candidates` in their agency org.
- `people_ops_admin` / `org_admin` → org-wide within their tenant.
- `employee` → only their own `person`/`profile` + consent dashboard.

### 5.3 Row-Level Security (enforced in Postgres, not just API)
Every domain table has RLS **enabled with default-deny**. Predicates use a security-definer helper that reads the JWT claims (`auth.uid()` → resolves to `person` → memberships → roles → permitted `org_id`s and scope).

Representative policy shape (illustrative, not final SQL):
```sql
-- profiles: a person can read profiles only if they own them,
-- OR they have profile.read in an org that has an active consent grant
-- covering that profile, AND the row is within their scope.
create policy profiles_read on profiles
for select using (
  is_self(person_id)
  or (
       has_permission(org_id, 'profile.read')
   and in_scope(org_id, person_id)
   and consent_active(consent_id)
  )
);
```
Helpers (`is_self`, `has_permission`, `in_scope`, `consent_active`) are `security definer` SQL functions. **No table is readable without an explicit policy.**

### 5.4 Identity
- Supabase Auth for credentials; **SSO** (Okta, Entra ID, Google Workspace) via SAML/OIDC; **SCIM** provisioning to sync employees/managers from the directory; **MFA** required for `*_admin` roles.

---

## 6. Settings & configuration (template-driven, per-tenant)

`organizations.settings_json` + `org_modules.config_json` hold:
- Branding (logo, colors — feeds DESIGN tokens), `locale_default` and enabled locales (`nb-NO`/`sv-SE`/`da-DK`/`en`).
- Assessment defaults (instrument selection, time limits).
- Re-fit cadence (e.g. every 6 months), pulse cadence.
- Notification rules and channels.
- Data-retention policy per record kind (drives `deleted_at` / hard-purge jobs).
- Module enablement (which capabilities are on for this org).

All configuration is **data, not code** — changing a cadence or enabling a module is a row update, not a deploy.

---

## 7. Integrations (Phase 0 = framework + 1 of each)

- **HRIS/ATS connectors** — `integration_connections` table (`org_id`, `provider`, `auth_ref`, `config_json`, `status`) + a sync worker. Phase 0 ships the framework and **one** HRIS (HiBob or Personio) read-sync for org/people structure; others added later.
- **Workflow** — outbound webhooks + an open REST API; Slack/Teams delivery adapters (Phase 3 activates content, Phase 0 ships the adapter interface).
- **Events/jobs** — an event bus + scheduler (`jobs`, `events` tables or Supabase scheduled functions) behind re-fit reminders, pulse cadences, onboarding milestones, digest delivery.

---

## 8. Audit & residency

- `audit_log` — `id`, `org_id`, `actor_person_id`, `action`, `entity_type`, `entity_id`, `before_json`, `after_json`, `at`, `request_id`. **Immutable** (insert-only; no update/delete policy). Written by triggers on consequential tables + explicit app events.
- All data in **EU region**; residency guarantees recorded at `organizations.data_region`.
- `audit_log` + `consent_grants` + `roles_catalog` versions are the substrate the EU AI Act technical documentation is generated from in Phase 4.

---

## 9. Phase 0 acceptance checklist

Phase 0 is "done" when:
- [ ] An `agency` org and an `employer` org can coexist with **provably isolated** data (RLS test: cross-org read returns zero rows).
- [ ] A `person` can hold memberships/profiles across both orgs with correct per-org visibility.
- [ ] RBAC roles × scope produce correct row visibility for manager / recruiter / employee / admin (tested).
- [ ] A `consent_grant` governs profile visibility; **revoking it removes access** (tested).
- [ ] A `roles_catalog` entry can be versioned; old versions are retained.
- [ ] A `placement` performs a consent-gated cross-org profile hand-off, fully audited.
- [ ] SSO login + one HRIS read-sync works end to end.
- [ ] Every consequential mutation lands in an immutable `audit_log`.
- [ ] Module + template registries allow enabling a capability per org **without core schema changes**.
- [ ] All hosting in EU region.

---

## 10. What Phase 0 deliberately excludes

- Assessment scoring logic, guidance composer, predictive models (Phases 1/3/4).
- Full set of HRIS/ATS connectors (framework + one only).
- Slack/Teams *content* (adapter interface only).
- Bias-audit automation (Phase 4).
- Proprietary instruments (Phase 4).

Build the core correct, then layer capability as modules on top.
