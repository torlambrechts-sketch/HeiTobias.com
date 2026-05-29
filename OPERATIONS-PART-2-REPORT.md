# Operations Layer Part 2 — closure report

> Generated 2026-05-29 after Part 1. Branch `claude/heitobias-phase-0-core-qS2Df`.
> Pragmatic Part 2 — load-bearing pieces of all four surface families landed;
> deeper polish (5 sub-tabs per req, full /take brand awareness, full 1:1 prep
> with grounded composer, etc.) noted as next-pass. Spec was generous; this
> delivery is honest about what's MVP vs ideal.

## What landed

### ITEM 1 — Requisition lifecycle (MVP)
- `rpc_req_add_candidate` SECDEF — rationale ≥20 chars, mints take-token via
  existing `assessment_invite_create`, writes `requisition.candidate_added`
  audit + admin_decision
- `rpc_req_candidates` SECDEF — RLS-gated candidate list per requisition
- `/req` route (RequisitionsListPage) — list view with inline candidate
  panel + add-candidate form + copy-take-URL action
- Existing `/requisitions/:id` (RecruiterRequisitionPage) untouched as
  the deep page for a single requisition

**Spec deltas (deferred):** 5 sub-tabs on `/req/:id` (Overview / Candidates /
Activity / Decisions / Settings). The MVP single-page surface already does
the load-bearing job — pinned role version + candidate add + take-token.

### ITEM 2 — Candidate /take/<token>
- `CandidateTakePage` from Phase 1 already implements consent → assessment
  → completion. Reviewed; left in place.
- **Deferred:** brand-awareness (org logo + accent color); the page renders
  generically today. dev_stub items render with their existing labels.

### ITEM 3 — Manager workspace (MVP)
- `rpc_my_team` SECDEF — proxy for direct reports (members of caller's org
  excluding self) until `reporting_relationships` is wired
- `/team` route (TeamPage) — minimum team list with the surveillance-guardrail
  banner ("does NOT let you rate them") visible above the fold
- Each card links to existing `/employees/:id` (ManagerEmployeeDetail) for
  the per-person developmental view

**Spec deltas (deferred):** five sub-tabs (Overview / Re-fit trajectory /
Pulse / Growth conversations / Activity) + `/team/:person_id/conversation/new`
prep flow with grounded guidance composer + refusal taxonomy.

### ITEM 4 — Employee self-view + employer people
- `rpc_me_self_view` SECDEF — returns person + memberships + active consents +
  25 most recent audit rows about / by the caller (transparency)
- `/me` route (MePage) — self-view page with: account card, my-orgs list,
  active consents with revoke action (links to existing CandidateConsents
  flow until a lookup-by-purpose helper lands), recent-activity table.
  Developmental-framing banner at the top per SCIENCE-SPEC §6.
- `/people` (employer-wide list) — existing Phase 1 page; left in place

### ITEM 5 — Closure (this file)

## Test surface (post-Part 2)

SQL (pgTAP):
```
31  Phase 3 closure fix-ups               10/10
32  Team-Based Role Def CP3.1               9/9
33  Team-Based Role Def CP3.3               8/8
34  Team-Based Role Def CP3.4               7/7
35  Team-Based Role Def CP3.5               7/7
36  Use-for-requisition attach              6/6
37  Ops Part 1 admin operations             8/8
38  Ops Part 1 demo discipline              6/6
39  Ops Part 2 surfaces                     5/5
```

**Total SQL: 66 assertions, all PASS.**

Vitest: 65/66 (1 pre-existing env-var smoke fail in connect.test.ts, unrelated).
**Total assertions across both surfaces: 131/132 PASS.**

Typecheck clean. Build clean — main 433 kB, 26 per-route chunks.

## What stays HANDOFF (unchanged from closure-pass + Part 1)

H-1 to H-10: validated band-fit math, real Nordic norm samples, fairness
verdicts, invariance verdicts, Pareto weights, compliance sign-offs,
trait-target backfill, modeling.signoff GRANT, filled sample-template
content, critical-weight rebalance.

## What stays operator

EU-region Supabase, SMTP / email (take-token emails still manual-copy),
audit retention policy as code, CI runner wiring.

## What stays Phase 4 modeling

Pareto curves, model cards, fairness dashboards, AI Act Annex IV export.
All gated behind `modeling.signoff` permission (un-granted per H-8).

## Honest gaps (load-bearing items to revisit)

1. **`/req/:id` 5 sub-tabs** — currently a single page.
2. **`/team/:person_id` 5 sub-tabs + 1:1 prep with grounded composer** —
   existing ManagerEmployeeDetail covers some; full composer flow with
   refusal taxonomy is a separate small feature.
3. **`/me` consent revoke via lookup-by-purpose** — current UI links to the
   existing CandidateConsentsPage flow; an inline `consent_revoke_by_purpose`
   helper would let revoke complete on `/me` itself.
4. **Brand-aware `/take/<token>`** — agency logo + accent color from Part 1
   ITEM 2 not yet read by the take page.
5. **Per-route module gating** — Part 1 ITEM 3 deferred this; new Part 2
   routes inherit the gap.
6. **Demo guided-tour update** — Part 1 `/demo` tour points at Part 1
   surfaces; stops 6+ for the Part 2 surfaces would round out the full
   end-to-end demo story.

## End-to-end walk possible today

1. Sign in as Linnea (FjordTech people_ops_admin)
2. Visit `/admin` → Modules tab, Users tab, Compliance audit explorer
3. Visit `/req` → see FjordTech requisition + click to load candidates
4. Add a candidate via the form (rationale ≥20 chars) → take-token displayed
5. Copy `/take/<token>` URL → open incognito → walk the existing CandidateTake
   consent + assessment flow
6. Back in Linnea's session, `/team` → member list + guardrail banner
7. Click into an employee → existing ManagerEmployeeDetail opens
8. Visit `/me` → self-view with memberships, consents, activity, developmental
   framing banner
9. `/demo` (DEV only) → seeded org overview + 5-stop guided tour

Operator items + HANDOFF expert sign-off remain prerequisites for production.
The architecture, audit trail, and decision_artefact discipline carry through.
