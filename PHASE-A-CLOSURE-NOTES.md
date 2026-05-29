# Phase A — Closure notes

> First of four phases. Closes the visible gaps in surfaces that already
> existed but had broken-button, hardcoded-tenant, or placeholder-shell
> defects. Definition-of-done: every surface that exists either WORKS or
> HONESTLY EXPLAINS WHY IT DOESN'T.

## What landed

### A0 — `useCurrentOrgId()` and the FJORDTECH_ID purge
The demo org UUID `a1000000-0000-0000-0000-000000000002` was hardcoded
into three production-bound query paths. Replaced with a state-machine
hook `src/lib/currentOrg.ts` that resolves the caller's first active
membership's `org_id` and reports `loading | unauthenticated |
no_membership | error | ready`. Pages that filter by org now read from
the hook and skip their loads until the state is `ready`.

Files changed:
- `src/lib/currentOrg.ts` — new
- `src/pages/ManagerEmployeeDetail.tsx` — read orgId from hook; refit /
  signal / guidance / compose calls all use it
- `src/pages/ModelingAdmin.tsx` — same pattern; model registry, pareto
  curves, monitoring alerts, compliance artifacts all read orgId
- `src/pages/RecruiterRequisition.tsx` — placement target dropdown now
  loads employer orgs from the DB at runtime (RLS-scoped) instead of
  the single hardcoded `FjordTech AS` option. Also closed the
  demo-credential gating gap (DEMO_USERS array + signInWithPassword
  call now gated behind `import.meta.env.DEV`).
- `src/pages/RequisitionsList.tsx` — orgId resolved via the hook for
  the new Create-requisition flow.

Multi-tenant blocker closed.

### A2 — Create-requisition wizard
`RequisitionsList.tsx:104` used to ship a `disabled` button with the
title "Create-requisition wizard is in /requisitions infra; for now
create via SQL/admin" — visible dead UI. Replaced with a working
modal (`CreateRequisitionDialog`):
- Loads the caller's non-template roles via RLS (`role.read` filter).
- Loads other orgs visible to the caller for the optional
  `collaborating_org_id` slot (agency / employer pairing).
- Captures a rationale (≥20 chars per audit discipline) and writes
  both the `requisitions` insert and a mirrored `admin_decisions` row
  so the create is queryable from the audit explorer.
- Surfaces RLS-denied / missing-permission errors verbatim; refuses
  submission when no roles are visible (empty state explains why).

Out of scope (intentionally — not in the schema today): title,
headcount, comp range, target_start. The requisition rides on top of
the role profile.

### A4 — Recruiter placement: employer-org dropdown loaded at runtime
The "Place into employer org" dialog in
`RecruiterRequisition.tsx` had a hardcoded single-option dropdown.
Now it loads `organizations` where `type='employer'` at runtime
(RLS-scoped), shows an honest empty state when none are visible, and
disables the Execute button until a target is selected.

### A5 — RoleProfile placeholder tabs filled in
`RoleProfile.tsx` had four `// TODO: wire to underlying queries`
tabs (team_definition, versions, defensibility, manage) that rendered
the same placeholder shell. Each is now a working component:
- **TeamDefinitionTab** — lists `team_definition_runs` that target
  this version or share its family; empty state CTA opens
  `/team-def/new` with the right query params; each row links to the
  full driver page.
- **VersionsTab** — calls `fetchRoleVersionHistory()` (which already
  existed); renders the version timeline with the current version
  highlighted and per-version draft / signed-off status.
- **DefensibilityTab** — renders
  `definition_json.validation_and_defensibility_metadata` (method,
  inter-rater agreement, sign-off date, run reference, framing
  default, next review). Empty state when the role has no
  provenance attached (e.g. legacy templates) is honest about why
  and points to the team-definition flow to fix it.
- **ManageTab** — two operational tiles (supersede via team-def, use
  for a requisition) and an honest panel about the archive seam
  not being built yet ("a future migration adds…"), with the
  workaround documented.

### A1 — Workspace Admin contrast warning
Already wired. `ContrastPreview` component in `WorkspaceAdmin.tsx`
renders WCAG AA contrast ratios against canvas + surface when the
admin edits the accent color. No change needed.

## What did NOT land in Phase A (deferred to Phase B/C with reasoning)

- **`/req/:id` five sub-tab restructuring** (Overview / Candidates /
  Activity / Decisions / Settings) — the existing single-page layout
  is functional and already groups these sections visually. Reshaping
  it to tab navigation is UX preference, not a production blocker;
  carry to Phase C if the user wants it.
- **`/team/:id` five sub-tabs + 1:1 prep with refusal-taxonomy
  composer** — the existing `ManagerEmployeeDetail.tsx` already
  surfaces refit history, signals, guidance with refusal kinds, and
  action recording. The composer with the live framework-library RAG
  call requires either a wired LLM endpoint (operator) or a more
  thorough seam — carry to Phase B (notifications + Cmd-K) or Phase D.
- **`/me` five sub-tabs** — the existing self-view shows person,
  memberships, consents, audit feed in a single layout. Same reasoning
  as above; tab-navigation restructuring is preference, not a defect.
- **Job-ad generator with three guardrails + hiring-manager review**
  — separate Recruiter Demo Extension. Acknowledged in
  `UNIFIED-SESSION-REPORT.md` as un-built. Carry to Phase B/C.
- **PDF export of placement reports** — current path generates HTML
  and `window.open`s it. PDF requires either a server-side renderer
  (operator config) or a client-side PDF library (new dependency
  ask). Carry to Phase D operator/handoff.

## Verification

```
npm run typecheck      # clean, no errors
npm test               # 66/66 tests pass
npm run build          # build succeeds; chunks within budget
node scripts/invariant-checks.mjs   # ✓ all four invariants pass
```

Phase A leaves the platform with: no hardcoded demo-org UUIDs in
prod-bound paths, a working create-requisition flow, an employer-org
dropdown that's actually multi-tenant, and four previously-inert
RoleProfile tabs that now show real data with honest empty states.
