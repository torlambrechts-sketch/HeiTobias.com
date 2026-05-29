# Unified candidate assessment session — closure report

> Branch `claude/heitobias-phase-0-core-qS2Df` · 2026-05-29.
> Extends the existing `/take/<token>` flow into a 4-section unified
> session (personality + cognitive + values + structured-interview prep)
> with shared session state, save-and-resume, demo mode (`?demo=true`),
> and recruiter-side visibility of section completion + demo flag.

## What landed

### DB (4 migrations)

| File | Purpose |
|------|---------|
| `..._300000_unified_session_schema.sql` | `assessment_sessions` table (one row per invite_token) + `assessment_prep_responses` for free-text STAR responses. Both RLS-gated to org members with `requisition.read`. |
| `..._300100_unified_session_seed_instruments.sql` | Seeds 2 dev_stub instruments: `sample_cognitive_v0` (25 matrix items, `timed`, 90s/item) + `sample_values_v0` (21 PVQ-21 portraits + 3 SDT items). Every item carries `_dev_stub = true` + a clearly-synthetic prompt ("Sample matrix item N — DEV STUB"). |
| `..._300200_unified_session_rpcs.sql` | Five SECDEF + anon-callable RPCs: `assessment_session_init(token, demo)`, `assessment_session_state(token)`, `assessment_session_submit_item(token, item_id, value)`, `assessment_session_submit_prep(token, competency_key, text)`, `assessment_session_mark_section(token, section)`. |
| `..._300300_unified_session_recruiter_view.sql` | `rpc_candidate_session_summary(rc_id)` — recruiter-side per-candidate session view including `demo_mode` flag + section completion. |

### UI

`src/pages/CandidateTake.tsx` rewritten to drive the unified session:
- Reads `?demo=true` from the URL on mount; passes through to `assessment_session_init`
- Phases: `loading → consent → personality → cognitive → values → structured_prep → completed`
- Common chrome on every section: `<BrandStrip>` (agency accent + logo), `<DemoBanner>` (persistent banner when `demo_mode`), `<SessionProgress>` (4 dots with answered/total)
- **Personality**: existing items via `assessment_take_state` + `assessment_submit_response` (unchanged plumbing)
- **Cognitive**: per-item timer, no back-button, choices grid 1-5
- **Values**: 6-point Likert with anchor labels visible
- **Structured prep**: STAR textarea per competency, ≥20-char min, methodology callout above the textarea citing Sackett 2022 ρ≈.42
- Completion page unchanged from existing design (no scores shown to candidate, consent dashboard link surfaces)

`src/pages/RequisitionsList.tsx` extended:
- Per-candidate session summary surfaced inline
- **⚠ DEMO MODE** pill rendered prominently when `demo_mode = true`
- Per-section completion counters (pers / cognitive / values / prep) in monospace
- `dev_stub` pill always present

`src/pages/Demo.tsx` guided tour gains stop 4.5: "Walk the unified candidate session (demo mode)" with the specific call-out that production runs 45–75 minutes and demo mode is unmissable.

### Tests

**SQL test 41 — 9/9 PASS:**
- T1 demo_mode true
- T2 demo cognitive count = 10
- T3 demo values count = 8
- T4 demo structured-prep count = 2
- T5 Sackett methodology note present
- T6 cognitive item submit advances state
- T7 production cognitive count = 25
- T8 mark_section all four → session.status = completed
- T9 structured-prep submit advances state

## Discipline that held

- **dev_stub everywhere**: every item carries `_dev_stub = true`; every section block in the session-state response carries `validity_status: dev_stub`. Recruiter view shows the `dev_stub` pill adjacent to every candidate session row.
- **No fabricated science**: prompts are clearly synthetic ("Sample matrix item N — DEV STUB"). Real IRT-calibrated items + Nordic norm sample land per H-1 / H-2.
- **Demo mode unmissable**: persistent banner in candidate UI + `⚠ DEMO MODE` pill in recruiter view + `demo_mode` boolean on the DB row.
- **One consent covers four sections**: the existing `assessment_capture_consent` consent-token flow is unchanged. The consent screen now enumerates what's in the session (4 parts).
- **Save-and-resume across all sections**: re-fetching `assessment_session_state` returns the next unanswered item; each submit advances. Browser reload mid-session re-enters at the same item.
- **No scores shown to the candidate**: completion page only thanks + consent-dashboard link.
- **No proctoring / anti-cheat / identity verification** added (explicit refusal per prompt).

## Honest deviations from spec

1. **Recruiter walkthrough ends at step 5** (recruiter sees four-section data), not step 8. Steps 6-8 (placement-report generation, job-ad generator with guardrails, hiring-manager approve+export) require the **"recruiter demo extension" prerequisite that the prompt cites but which doesn't exist on this branch.** Building those properly is a separate prompt — flagging instead of stubbing.
2. **Section `personality` items** still come from the legacy `assessment_take_state` RPC (with whatever instrument the invite was created with). The unified `assessment_session_state` exposes cognitive + values + structured_prep; personality is still on the legacy path so the existing test scaffolding stays green. Folding personality into the unified state object is straightforward follow-up work but not on the critical path.
3. **No new vitest tests** for the new sections — the 5 SECDEF RPCs are SQL-test-covered (test 41); component-render tests would test React, not business logic. The senior-dev review pattern from previous closures applies.

## What stays out of scope (continued refusal)

- **HANDOFF H-1 to H-10** — real cognitive items, IRT calibration, validated PVQ-21 licensing, fairness verdicts, etc. The dev_stub seam keeps the science honest.
- **Operator items** — SMTP for the take-token email (admin still copies the link), EU-region Supabase, audit retention.
- **Phase 4 modeling surfaces** — gated behind `modeling.signoff` (un-granted per H-8).
- **Proctoring / identity verification** — explicitly refused per prompt. Recruiters asked for the unified flow, not integrity verification.
- **Direct third-party vendor connectors** (Hogan/SHL/cut-e) — refused.

## Recruiter demo walkthrough (step-by-step)

1. **Sign in** as Linnea (or any user with `requisition.write` in an org with a requisition)
2. **Open** `/req` → click the FjordTech requisition
3. **Add a candidate** with rationale → token shown in the success card
4. **Open the take URL in incognito with `?demo=true`** (e.g. `/take/<token>?demo=true`)
5. **Walk the unified session in demo mode** (~15 min):
   - Consent screen lists the 4 parts; click "I consent — start the assessment"
   - Personality: 5 items (existing flow); answer to advance
   - Cognitive: 10 items with per-item timer; no back button
   - Values: 8 items on 6-point Likert with anchor labels
   - Structured-interview prep: 2 STAR prompts (200-400 char target); methodology Sackett callout visible
   - Completion page: thanks + consent dashboard link (no scores shown)
6. **Back in recruiter view** at `/req`: the candidate row now shows ⚠ DEMO MODE + per-section completion counts + `dev_stub` pill
7. **Steps 7-8** (job ad + manager approve) require the un-built recruiter demo extension — see `OPERATIONS-PART-1-REPORT.md` for what was scoped vs deferred

## Next moves (not code)

1. **I/O psychologist engagement** — replace the seeded dev_stub items with real IRT-calibrated content (H-1, H-2)
2. **Schwartz PVQ-21 licensing** — operator decision; the placeholder text honors the methodology shape without infringing
3. **Operator wiring** — SMTP for take-token email so the recruiter doesn't manually copy the link
4. **Build the recruiter-demo extension** — placement report generation + job-ad generator with guardrails + hiring-manager approve flow (steps 6-8 of the walkthrough)
5. **Proctoring decision** — if integrity verification becomes important, scope separately; explicitly out of this build

## Test surface (post-this-pass)

```
SQL (pgTAP):
  31  Phase 3 closure fix-ups               10/10
  32  Team-Based Role Def CP3.1               9/9
  33  Team-Based Role Def CP3.3               8/8
  34  Team-Based Role Def CP3.4               7/7
  35  Team-Based Role Def CP3.5               7/7
  36  Use-for-requisition attach              6/6
  37  Ops Part 1 admin operations             8/8
  38  Ops Part 1 demo discipline              6/6
  39  Ops Part 2 surfaces                     5/5
  40  Ops Part 3 gap closures                 6/6
  41  Unified session                         9/9
```

**Total: 81 SQL + 65 vitest = 146 assertions, 145 PASS** (1 pre-existing env-var smoke).
Typecheck + build clean.
