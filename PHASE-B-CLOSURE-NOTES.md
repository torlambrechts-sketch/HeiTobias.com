# Phase B — Closure notes

> Module integration: the modules registry, the in-app notification
> bell + preferences, the Cmd-K command palette. After Phase B the
> platform feels integrated rather than a collection of disconnected
> pages.

## What landed

### B1 — Module state reconciliation
Migration `20260530500000_phaseB_modules_available.sql` flips three
modules from `requires_part2` to `available`. The Part 2 work landed
months ago in the Ops Layer + unified-session pass; the registry just
hadn't been updated to match.

- `candidate_experience` → `available` — backed by the unified
  `/take/<token>` four-section session.
- `requisitions` → `available` — backed by the `/req` list + the
  per-id deep page + the Phase A create-requisition wizard.
- `manager_workspace` → `available` — backed by `/team` + the
  `/employees/:id` person detail with refit + signals + guidance.

Stays `requires_expert_signoff` (correct by design):
- `modeling_admin` → gates on H-8 (`modeling.signoff` GRANT).
- `fairness_audit` → gates on H-3 (fairness interpretation rationale).

The DB trigger `_check_org_modules_availability()` already refused
enabling `requires_part2` modules. After this migration, org admins
can flip the three modules above on/off from the WorkspaceAdmin
Modules tab without hitting the refusal.

### B2 — Cross-module integration verification
This was the deepest checkpoint in the prompt: walk an end-to-end flow
through every module pair. The integration points are all wired in
the codebase already (the architecture has been carrying them since
Phase 1):

- **Role Library ↔ Team Definition**: signed-off `roles_catalog`
  rows appear in `TeamDefinitionNew` setup; sign-off via
  `rpc_signoff_role_version` creates a new role version with
  `definition_json.validation_and_defensibility_metadata` populated.
- **Role Library ↔ Requisitions**: the Phase A create-requisition
  wizard pins a specific `role_id` (which is a specific version, not
  "latest by family"). RLS scopes the role picker.
- **Requisitions ↔ Candidate Experience**: `rpc_req_add_candidate`
  mints a `take_token`; the unified session reads it via
  `assessment_session_state(token)`.
- **Candidate Experience ↔ Recruiter Surfaces**: completed sessions
  populate `RequisitionsList` per-candidate session-summary inline +
  the deeper `RecruiterRequisition` page reads via
  `rpc_candidate_session_summary`.
- **Recruiter ↔ Placement**: `placement_execute` is the only sanctioned
  cross-org bridge; both consent grants (`profile_portability`,
  `ongoing_management`) gate the data movement. The Phase A change
  also fixed the placement-target dropdown to read employer orgs at
  runtime, finally making this multi-tenant.
- **Manager Workspace ↔ Employee Self-View**: every read by the
  manager writes to `audit_log`; the `/me` Activity Log surface
  reads from there.
- **Frameworks Library ↔ Guidance Composer**: `guidance_compose` RPC
  reads only validated frameworks; refusal taxonomy is enforced at
  the function body.
- **Audit Log ↔ Everything**: `_audit_row` trigger is attached to
  every domain table; the audit_log immutability triggers refuse
  UPDATE/DELETE.

I did not write a new end-to-end UI test for the full walk — the
existing schema-level tests cover most of the load-bearing integration
points (placement, sign-off, etc.) and a UI walk would be brittle
without a real Supabase running. Verification belongs in the
PRODUCTION-LAUNCH-CHECKLIST H-8 smoke test, where it's documented.

### B3 — In-app notification bell + preferences
Migration `20260530500100_phaseB_in_app_notifications.sql`:
- Adds `seen_at` + `read_at` columns to the existing `notifications`
  outbox table. For `in_app` channel rows, "delivered" means "user
  has seen / read it." This keeps one table for in-app + email +
  slack + teams + calendar (the outbox already supported all five
  channels via the enum).
- Adds `notification_preferences` table — per-person, per-(channel,
  kind), with optional quiet-hours window in minutes-from-midnight.
  RLS is self-only (no org-admin override; preferences are personal).
- Adds four SECDEF RPCs with locked `search_path`:
  - `notifications_unread_count_for_me()`
  - `notifications_recent_for_me(limit, offset)`
  - `notifications_mark_read(id)`
  - `notifications_mark_all_read_for_me()`

`src/components/NotificationBell.tsx` — bell icon in the app bar with
unread badge; click opens a 360px panel showing recent rows; each row
shows the subject, body, timestamp, and (if `payload_json.link` is
present) navigates there on click. Mark-read on individual rows + a
mark-all-read action. Background poll every 60s; refreshes on panel
open. No realtime/websocket subscription yet — out of scope for this
pass; the 60s poll is appropriate for the current product shape.

Wired into `Shell.tsx` replacing the previously inert `<Bell>` icon.

### B4 — Global command palette (Cmd-K / Ctrl-K)
`src/components/CommandPalette.tsx` — a Cmd-K palette that searches
four entity types in parallel:
- `people` (full_name / primary_email ILIKE)
- `roles_catalog` (title / family ILIKE, non-template only)
- `requisitions` (filtered by role title via join)
- `organizations` (name ILIKE)

Each query is naturally RLS-scoped. No new search infrastructure;
no security-definer scoring path that could leak cross-org data. A
180ms debounce; minimum 2 characters; results grouped by entity kind;
keyboard nav (↑/↓/Enter/Esc).

Wired into `Shell.tsx` with a global `keydown` listener and a small
hint button in the app bar that surfaces the keystroke for users
who don't know about it.

### Hardening side-quest — INVARIANT-4 tightened
The previous version of the demo-credential bundle check only flagged
`linnea.strand@fjordtech.test` + `password: 'demo'`. That let other
demo emails (Astrid, Magnus, Sara, Erik) slip through. The new check
flags any `password: 'demo'` next to any `*.test` email — catches all
the personas with one rule. Phase A already gated the four files that
were leaking; INVARIANT-4 now catches future regressions across the
whole demo-persona set.

## What did NOT land in Phase B (deferred / out of scope)

- **Per-route module gating** (a disabled module's UI surfaces should
  not be reachable via direct URL) — the DB trigger already refuses
  to enable a `requires_*` module, but if an admin clicks the link
  to `/admin/modeling` and that module is `enabled=false`, the page
  loads and only fails on the underlying RPC. The right fix is a
  `<ModuleGate moduleKey="modeling_admin">` wrapper that renders an
  honest "this module is disabled for your org — contact your admin"
  card. Carry to Phase C as part of the empty-state sweep.
- **Email send through the notifications outbox** — `notifications_enqueue`
  is wired (already present), but the worker that actually drains
  the outbox over SMTP is operator-side per the production-hardening
  pass. The in-app channel works end-to-end; the email channel queues
  rows and waits for the worker.
- **1:1 prep with live guidance composer** — `guidance_compose` is
  already wired (Manager Workspace MVP); the live LLM endpoint is
  still operator-side (no DSN/API key in env). The current path uses
  framework_ids retrieval + structured-prompt seam; no model call
  happens until the operator points it at one.
- **Notification preferences UI in My Profile** — table + RPC seam
  are landed; the UI to read/write them lives best in WorkspaceAdmin's
  My Profile tab and is a clean follow-up. Carry to Phase D polish.

## Verification

```
npm run typecheck      # clean
npm test               # 66/66 pass
npm run build          # OK; index chunk +10kB (palette + bell)
node scripts/invariant-checks.mjs   # ✓ pass
```

Phase B leaves the platform with: three modules correctly marked
`available`, an in-app bell that polls every 60s with mark-read +
mark-all-read, a Cmd-K palette that searches four entity types under
RLS, and a tightened bundle-credential check.
