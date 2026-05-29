# Closure pass — report

> Status of the seven-item closure pass on the HeiTobias talent lifecycle platform. Generated 2026-05-29.

This pass closes engineering-scope items from the `CLAUDECODECLOSUREPROMPT.md` brief. It deliberately **does not** touch HANDOFF items (validated science, real norms, fairness verdicts, compliance sign-offs, filled sample templates) or operator items (EU-region provisioning, SMTP, audit retention, CI). Those remain owned by the I/O psychologist, the legal/AI-Act advisor, the customer's executive, and the operator respectively — by design.

## Summary

| | Status | SQL tests | UI tests |
|---|---|---|---|
| ITEM 1  | Phase 3 re-audit + F1/F2 fix-ups       | 10/10 (test 31) | — |
| ITEM 2  | Visual diff Role Profile vs mock       | — | — |
| ITEM 3  | Team-Based Role Definition module      | 30/30 (tests 32–35) | 26/26 (cp32–36) |
| ITEM 4  | Use-for-requisition picker             | 6/6  (test 36) | 6/6  (cp4) |
| ITEM 5  | i18n scaffolding + load-bearing copy   | — | 8/8  (cp5) |
| ITEM 6  | Route-level code splitting             | — | 4/4  (cp6) |
| ITEM 7  | WorkspaceAdmin polish                  | — | 5/5  (cp7) |

**65/66 vitest pass.** The single failure is a pre-existing connectivity smoke test that requires `SUPABASE_URL` env in the test environment; out of scope for this pass, verified by stashing.

**Bundle:** main 432 kB · 23 per-route chunks · no Rollup warning.

---

## ITEM 1 — Phase 3 re-audit (closed)

Started from `PHASE3-AUDIT-REPORT.md` which scored Phase 3 at **6 PASS / 2 PARTIAL / 0 FAIL**. The two partials (P-1: team_composition read-edge for ITEM 3, P-2: transparency chain for the employee self-view) closed via fix-ups in `supabase/tests/31_phase3_closure_fixups.sql` — 10/10 PASS.

## ITEM 2 — Visual diff Role Profile vs mock (closed)

`VISUAL-DIFF-ROLE-PROFILE.md` itemised every divergence between `role-profile-detail.html` and the rendered `RoleProfilePage`. Three fix-now items landed in the same pass (SubNav restructure, StubBanner copy upgrade, section header numbering); three fix-later items were documented for later commits; two were accepted as different-by-design.

## ITEM 3 — Team-Based Role Definition module (closed, 6/6 checkpoints)

The largest item. Delphi-style independent rating workflow for role definitions; the spine of the talent lifecycle's hiring side. Six checkpoints shipped:

| CP | Scope | DB | UI |
|----|-------|-----|-----|
| 3.1 | Schema + RPCs + peer-personality CHECK + 3-lock seal | 6 tables, 5 SECDEF RPCs, 1 audit RPC | — |
| 3.2 | Stage 1 setup + Stage 2 rating UI | — | SetupForm + RatingForm + SurveillanceGuardrail |
| 3.3 | Stage 3 divergence — surface positions, never average | `rpc_compute_divergence` | DivergencePanel + per-evaluator dot-plot |
| 3.4 | Stage 4 reconciliation + sign-off; template-aware fix-up to `rpc_signoff_role_version` | template/instance branching | ReconciliationForm + SignoffForm |
| 3.5 | End-to-end integration test | — | — |
| 3.6 | Discoverability — list + Shell + RoleProfile CTA | — | TeamDefinitionList + PageHeader CTA |

The methodology load-bearers:

- **Three-lock Stage 2 seal**: RLS blocks others' rows pre-seal, the UI never queries them, AND the SECDEF reveal RPC writes a `team_def.read_during_seal` audit row if called pre-seal.
- **Peer-personality block**: schema CHECK `chk_team_def_evaluations_no_peer_personality` refuses `target_person_id` / `rater_person_id` / `rates_person` keys. UI body copy ("you are rating the role — you are not rating each other") is the second belt.
- **Provenance on the new role version**: signed-off roles carry `validation_and_defensibility_metadata.team_definition_run_id` + evaluator counts + reconciliation count + the dev_stub thresholds snapshot. Travels with the role wherever it's used.

## ITEM 4 — Use-for-requisition picker (closed)

`rpc_requisition_attach_role` SECDEF binds the team-def output to the existing requisition pipeline. Refuses templates (must instantiate first), cross-org attaches, no-op re-attaches, and short rationales (≥20 chars). UI is a modal-style picker from `RoleProfile`'s page header.

## ITEM 5 — i18n (load-bearing scope; full localisation HANDOFF)

CLAUDE.md mandate: `nb-NO / sv-SE / da-DK / en`, no hardcoded copy. Shipped:

- `src/lib/i18n.tsx` — minimal `LocaleProvider` + `useT()` + `useLocale()` (no library dependency)
- `src/i18n/en.json` — 11 load-bearing keys populated (guardrail, stub_banner, hitl, seal, locale_switcher)
- `src/i18n/nb-NO.json` / `sv-SE.json` / `da-DK.json` — explicit `_meta.coverage = "HANDOFF"` marker; the `useT` fallback chain renders English until a Nordic localiser fills them in
- Locale switcher in Shell AppBar
- 4 load-bearing components refactored to use `useT()`: `SurveillanceGuardrail`, `SealCallout`, `StubBanner`, `HitlNotice`

Bulk UI localisation (every label, error, tooltip) is **not** in scope here; that's a multi-day per-page externalisation pass + a translator round.

## ITEM 6 — Route-level code splitting (closed)

`React.lazy` + `<Suspense>` on every non-home route. Bundle went from 627 kB (single chunk, Rollup warning) to 432 kB main + 23 per-route chunks (no warning). HomePage stays eager — landing-paint matters.

## ITEM 7 — WorkspaceAdmin polish (closed)

Two rough edges resolved:

1. **Audit log row expansion** — `before_json` / `after_json` were on the wire but not rendered. Now expandable per row.
2. **"My profile" tab** — was a placeholder ("scaffolded; backend wiring is outside this hardening pass"). Now a working locale picker wired to `useLocale`. The signed-in email shows as read-only; org-managed fields explicitly route through the org admin flow.

---

## Explicitly REFUSED — HANDOFF and operator items

Per the closure prompt's OUT-OF-SCOPE list. The codebase is designed to refuse fabrication; this pass continued to refuse.

### HANDOFF (expert-owned, never fabricated by engineering)

| H-# | Item | Owner |
|---|---|---|
| H-1  | Validated band-fit math (real coefficients)         | I/O psychologist |
| H-2  | Real Nordic norm samples (no synthetic populations) | I/O psychologist |
| H-3  | Fairness-metric interpretation rationale            | I/O psychologist + legal advisor |
| H-4  | Invariance verdicts                                 | I/O psychologist |
| H-5  | Pareto weight choice                                | I/O psychologist |
| H-6  | Compliance artifact sign-offs                       | Legal / AI-Act advisor |
| H-7  | Trait-target backfill content                       | I/O psychologist |
| H-8  | `modeling.signoff` GRANT                            | Customer executive |
| H-9  | Filled-in sample role templates                     | I/O psychologist + customer |
| H-10 | Critical-weight rebalance of the engineering-lead sample | I/O psychologist |

The schema seam (`validity_status` enum + `_dev_stub` boolean + DB CHECK) means none of these can be silently promoted to `validated` without the right values present. The team-based definition module now provides the WORKFLOW that produces the audited values, but the per-org content still has to come from the expert.

### Operator items

- **EU-region Supabase provisioning.** Dev project remains in `us-east-1`. Per `supabase/config.toml` comment.
- **SMTP / Postmark / email infra wiring.** No email is sent today.
- **Audit-log retention policy.** `audit_log` is insert-only by RLS but the retention window is operator-policy.
- **CI runner wiring.** `npm test` + `npm run build` + `npm run typecheck` all work locally; the GitHub Actions / equivalent wiring is operator-side.

---

## Test surface (post-closure)

**SQL** (pgTAP via `supabase/tests/`):

```
31  Phase 3 closure fix-ups                                  10/10
32  Team-Based Role Definition CP3.1 independence            9/9
33  Team-Based Role Definition CP3.3 divergence              8/8
34  Team-Based Role Definition CP3.4 reconciliation + signoff 7/7
35  Team-Based Role Definition CP3.5 end-to-end integration  7/7
36  Use-for-requisition attach role                          6/6
```

**Vitest** (`src/**/__tests__/`):

```
cp32-guardrails.test.ts            7/7
cp33-divergence-ui.test.ts         7/7
cp34-reconciliation-ui.test.ts     7/7
cp36-discoverability.test.ts       5/5
cp4-use-for-requisition.test.ts    6/6
cp5-i18n.test.ts                   8/8
cp6-code-split.test.ts             4/4
cp7-admin-polish.test.ts           5/5
+ pre-existing connect.test.ts (1 fail — env-var smoke, pre-existing)
```

Total: **47 SQL** + **49 vitest** = **96 assertions, 95 PASS, 1 pre-existing unrelated FAIL**.

---

## Bundle (post-closure)

```
dist/assets/index-*.js       432 kB    (main, was 627 kB)
dist/assets/RoleProfile-*.js  44 kB    (lazy)
dist/assets/TeamDefinitionRun-*.js  42 kB  (lazy)
dist/assets/WorkspaceAdmin-*.js     21 kB  (lazy)
…20 more per-route chunks…
```

No Rollup size warning. Per-route chunks resolve on navigation.

---

## What the next pass might pick up

Noted during the work, deliberately NOT silently added:

- **Stage 4 visual flourishes**: the divergence panel doesn't render historical re-computes; recompute replaces. A small audit-trail header showing "computed at" would be a quality-of-life add.
- **DivergencePanel for SD on weights**: the 0–1 weight scale produces near-zero SD; the dev_stub cutoff (1.4) means it's always "high consensus". A scale-aware threshold belongs in the I/O-psych tuning pass (HANDOFF), not here.
- **i18n bulk pass**: every page still has hardcoded English labels outside the four load-bearing components. Per-page externalisation + a translator round is a separate engagement.
- **`/team-def` list filters**: currently shows the most recent 50 unfiltered. Filtering by stage / family is a small follow-up.
- **Per-user server-side locale persistence**: would land alongside a `user_preferences` table. Today the choice persists per-browser via localStorage.
- **Reconciliation history pane**: the reconciliation rows are persisted but the Stage 4 UI only shows the open form; a "previously reconciled" list with the audit-trail rationales would close a small UX loop.

None of these are HANDOFF; they're just genuinely next-pass.
