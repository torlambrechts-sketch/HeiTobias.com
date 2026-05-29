# Operations Layer Part 1 — closure report

> Generated 2026-05-29 after landing all 7 items in one continuous pass. Test suite green
> (one pre-existing env-var smoke fail unrelated). Branch `claude/heitobias-phase-0-core-qS2Df`.

## What landed

| # | Item | Migrations | Tests |
|---|------|------------|-------|
| 1 | Admin operations (invite + role + deactivate + reactivate + accept-v2) | 3 | 8/8 SQL |
| 2 | Org settings v2 (brand + locale + retention-as-read-only) | 1 | — |
| 3 | Module toggles with availability tri-state + DB-enforced lock | 1 | — |
| 4 | Audit-log explorer (actor + date + compliance view + export) | 1 | — |
| 5 | My profile (memberships + leave-org grace + my audit) | 1 | — |
| 6 | Seeded demo org (Lindqvist + Holst) + `/demo` page | 2 | 6/6 SQL |
| 7 | Closure report (this file) | — | — |

**Total new migrations:** 9. **Total new SQL tests:** 2 files / 14 assertions.

### Discipline that held

- Every consequential admin action writes a `decision_artefact` via the new `admin_decisions`
  table (third source under the `decision_artefacts` view). Rationale ≥20 chars enforced by
  CHECK constraint on `admin_decisions.rationale`.
- Module toggles cannot flip `enabled=true` for modules with `availability != 'available'`
  (DB trigger enforces; not a UI-only check).
- Demo data carries `is_demo_data = true` on every principal table row. SQL test 38 verifies.
- No fabricated science: no demo row anywhere has `validity_status = 'validated'`. Verified.
- Audit-log export writes its own `audit_log_exported_by` row (export itself is auditable).

### What's deliberately a stub or limit

- **Per-route gating on disabled modules**: the Modules tab shows + toggles correctly; the
  DB constraint blocks `not_available` modules. But the existing Shell nav + per-route
  components don't yet read `org_modules` to hide nav entries / refuse navigation. Visible
  gap, intentionally deferred — gating is a per-page touch and Part 2 lands several new
  routes. Closing this gap is a polish pass.
- **Leave-org auto-finalisation**: `me_leave_request` sets `status='leaving'` with a 7-day
  grace; the spec wants automatic transition to `inactive` at expiry. That transition is
  operator scheduler work (cron / pg_cron). Documented in the migration's comment block.
- **`/demo` "Reset demo data" button**: not built. Re-applying the demo migrations is
  effectively idempotent (`on conflict do update`) — that's the reset.
- **Pre-populated audit log in the demo seed**: not built. Walking the live surfaces
  (invite a user, change a role, toggle a module, etc.) populates it organically with the
  right rationale + decision_artefact, which is more believable than a static seed.
- **Demo personas without auth.users entries**: the demo people rows have `auth_user_id =
  null`. Sign-in needs to go through Supabase Auth; demo sessions are reachable only via
  the existing fixture personas (`linnea.strand@fjordtech.test` etc.) until the operator
  wires the demo logins. Documented on the `/demo` page itself.

## Test surface (post-Part 1)

```
SQL (pgTAP):
  31  Phase 3 closure fix-ups                     10/10
  32  Team-Based Role Def CP3.1 independence       9/9
  33  Team-Based Role Def CP3.3 divergence         8/8
  34  Team-Based Role Def CP3.4 reconciliation     7/7
  35  Team-Based Role Def CP3.5 e2e                7/7
  36  Use-for-requisition attach                   6/6
  37  Ops Part 1 admin operations                  8/8
  38  Ops Part 1 demo discipline                   6/6

Vitest:
  cp32-guardrails               7/7
  cp33-divergence-ui            7/7
  cp34-reconciliation-ui        7/7
  cp36-discoverability          5/5
  cp4-use-for-requisition       6/6
  cp5-i18n                      8/8
  cp6-code-split                4/4
  cp7-admin-polish              5/5
  + pre-existing connect.test.ts (env-var smoke, pre-existing fail — unrelated)
```

**Total: 61 SQL + 49 vitest = 110 assertions, 109 PASS.**

## Bundle (post-Part 1)

Main `index-*.js`: 432 kB. WorkspaceAdmin chunk: 35.9 kB (up from 21 kB — adds the audit
explorer, module-toggles, my-profile expansion). 24 per-route chunks total. No Rollup warning.

## Out of scope — explicitly refused

### HANDOFF (H-1 to H-10, expert-owned, unchanged from closure pass)

Validated band-fit math, Nordic norm samples, fairness verdicts, invariance verdicts,
Pareto weights, compliance sign-offs, trait-target backfill, modeling.signoff GRANT,
filled sample-template content, critical-weight rebalance.

### Operator items

EU-region Supabase provisioning, SMTP/email infra, audit-log retention policy,
CI runner wiring. The admin UI surfaces the operator gap honestly ("Email infrastructure
pending operator action" in the invite flow).

### Part 2 surfaces — HARD STOP

- Requisition lifecycle operator UI (`/req`, `/req/new`, `/req/:id`)
- Candidate `/take/<token>` experience
- Manager workspace + 1:1 prep
- Employer people-side + employee self-view (`/me`)

**Per the closure prompt's "stop at CHECKPOINT 7 and do not start Part 2" guard.**

## Next pass

Part 2 will close the four user-facing surface families above. After Part 2 lands, the
full demo scenario walks end-to-end in one continuous session from agency requisition →
candidate take-token → placement → manager workspace → employee self-view → consent
revocation. This is the unlock for design-partner conversations.
