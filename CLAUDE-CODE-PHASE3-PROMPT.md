# Claude Code — Phase 3 Kickoff Prompt (HeiTobias · Lifecycle / Manager Layer)

> Paste the fenced block below into Claude Code **after Phases 0, 1, and 2 are
> complete and their acceptance tests pass**. Phase 3 is the retention engine: the
> manager workspace, continuous guidance, team composition, pulse signals, and the
> re-fit (person-drift vs. role-drift) trajectory. This is the layer that makes
> HeiTobias more than a recruiting tool — and the one with the sharpest
> ethical/culture-design risk. Assumes the repo contains Phases 0–2, `CLAUDE.md`,
> `PHASE0-SPEC.md`, `DESIGN.md`, and any project-brief/build-plan files.

---

```
You are building Phase 3 (Lifecycle / Manager Layer) of HeiTobias, on top of the
completed Phase 0 core, Phase 1 Recruiter OS, and Phase 2 Hand-off. Phase 3 is the
retention engine: it gives managers continuous, specific, GROUNDED guidance about the
people they manage, and tracks how fit evolves over tenure. This is the most
scope-heavy phase AND the one with the highest ethical risk — the same data that reads
as "developmental support" can read as "surveillance." Build it so it is provably the
former. Work as a careful senior engineer: plan first, build in small verifiable
increments, write tests as you go, pause at the checkpoints.

## Step 0 — Read + confirm state before doing anything
1. Read in full and treat as authoritative: CLAUDE.md (architecture rules + hard
   "never" list, esp. pillar #5 + human-in-the-loop + grounded-not-freeform), SCIENCE-SPEC.md
   (THE authority for re-fit cadence + four-quadrant-as-synthesis-not-measurement, developmental
   framing as a measurement-validity requirement, engagement≠performance, the Frameworks Library
   evidence-tier model, and RAG/refusal rules),
   PHASE0-SPEC.md (entity model — esp. profiles as a TIME-VERSIONED series,
   consent_grants with the ongoing_management purpose, roles_catalog versioning +
   the evolution-vector field left nullable in Phase 1), DESIGN.md (UI system).
   Read project-brief/build-plan for product context if present.
2. Verify Phases 0–2 are done: run the existing test suites and confirm acceptance
   items still pass — especially purpose-aware consent (hiring_decision /
   profile_portability / ongoing_management), the single cross-org placement RPC,
   channel-posture (agency loses standing visibility post-placement), and the
   grounded-not-freeform 90-day-kickstart guidance seam. If anything fails, STOP and
   report; do not build on a broken foundation.
3. Summarize back (<=15 bullets): the profile time-series model, the
   ongoing_management consent gate, the roles_catalog versioning + evolution-vector
   field, and your Phase 3 plan mapped onto them. Then STOP and wait for confirmation.

## TWO OVERRIDING PRINCIPLES FOR PHASE 3 (restate these in your plan)
A) DEVELOPMENTAL, NEVER SURVEILLANCE. Every lifecycle feature must be framed and
   built as growth-support owned by the employee, not monitoring done to them:
   - All ongoing personal-data use is gated by an active ongoing_management consent
     (from Phase 2). No consent → no lifecycle data. Enforce in RLS, test revocation.
   - The EMPLOYEE can view their own profile, re-fit history, and the signals their
     manager sees (transparency, not a one-way mirror). Build the employee self-view.
   - Framing in copy + data: re-fit is "where the role is heading and how to grow
     toward it," never "you are falling behind." No feature ranks employees against
     each other for punitive use; no hidden manager-only scoring the employee can't see.
   - NO peer-rates-peer personality evaluation (carried from Phase 1). Team
     composition is derived ONLY from members' own validated profiles.
B) GROUNDED, NEVER FABRICATED. Manager guidance and frameworks follow the exact
   discipline of the Phase 1 I/O seam and Phase 2 kickstart:
   - Guidance is generated via retrieval over a FRAMEWORKS LIBRARY + structured
     profile/role data (RAG), never freeform model output about a named person, and
     every generation logs its inputs + framework sources to audit.
   - The frameworks library CONTENT is labeled SAMPLE/STUB (DEV_STUB_ / // DEV STUB,
     status flag) pending real management-science IP. Build the grounded-generation
     PIPELINE and the clean seam; do not ship invented "management science" as
     validated. Where you'd assert an unvalidated claim, store null + a stub flag.

## What Phase 3 IS (scope) — built as MODULES on the core
1. MANAGER WORKSPACE — the daily surface. Per-direct-report living profile (how they
   work, motivators, predictable friction, what to do this week), 1:1 preparation view,
   surfaced from profile + role + tenure + recent signals. Manager sees only their
   reports (reuse Phase 0 in_scope + ongoing_management consent).
2. GUIDANCE COMPOSER — turns profile + role + tenure + framework into specific,
   grounded suggestions (per principle B). Each suggestion shows its framework source
   ("grounded" chip) and is an INFORMING suggestion, not an instruction; manager
   actions/dismissals are logged.
3. PULSE & SIGNALS — lightweight, low-burden, employee-consented periodic check-ins
   that keep the profile time-series current (replacing annual surveys). The employee
   sees and owns their own pulse data. No silent/background data collection.
4. TEAM COMPOSITION ENGINE — aggregate a team's collective strengths/gaps FROM
   MEMBERS' OWN PROFILES (never peer ratings); predictable-friction view; project-fit
   view; feed the team-gap back into the Phase 1 Role Architecture engine.
5. RE-FIT & GROWTH ENGINE — the trajectory. Periodically re-measure the person against
   the EVOLVED role (use roles_catalog versioning + the evolution-vector field, now
   activated); compute the four-quadrant signal (growth gap / flight risk / stable fit
   / emerging misfit) as a fit time-series; surface the right developmental growth
   conversation. Re-evaluation is consent-owned and developmentally framed. Capture
   actual outcomes (this is the ground-truth that Phase 4 models will later use — store
   it, do not model it yet).

## What Phase 3 is NOT (do not build)
- No predictive models, no bias-audit automation, no proprietary instruments — Phase 4.
  (Re-fit CAPTURES outcomes for later modeling; it does not train models.)
- No invented management-science or psychometric content — labeled stubs + clean seam.
- No surveillance affordances: no hidden manager-only scores, no peer-personality
  rating, no background data collection, no punitive ranking.
- No new cross-org data paths — the Phase 0 placement RPC remains the only one.

## Constraints (inherited from CLAUDE.md — restate in your plan)
- Database-first; RLS DEFAULT-DENY on every new table; ALL ongoing personal-data
  visibility gated by active ongoing_management consent (purpose-aware consent_active).
  Reuse Phase 0 helpers (is_self / has_permission / in_scope / consent_active).
- profiles are a TIME-VERSIONED series (valid_from/valid_to) — re-fit appends new
  versions; never destructively overwrite; history is retained for the trajectory.
- Human-in-the-loop: guidance INFORMS, never decides; log actions + overrides.
- Everything consequential → audit_log. Multi-table writes → atomic, policy-checked RPCs.
- Modular + template-driven: guidance frameworks, pulse templates, growth-conversation
  templates, re-fit cadences = templates (data), not hardcoded.
- UI strictly per DESIGN.md (three-tier shell, forest tab band, cream-green canvas,
  serif display, Lucide, tinted pills, role=blue/person=green, trait-range control,
  consent-as-first-class). New surfaces: manager workspace, per-report profile,
  1:1 prep, team composition, re-fit/fit-trajectory view, AND the employee self-view.

## Build sequence — plan, build, test, PAUSE at each checkpoint
1. Lifecycle module tables (migrations): pulse_checkins, signals, guidance_items
   (+ framework source refs), team_composition snapshots, refit_evaluations
   (fit time-series), growth_conversations, outcome_captures. RLS DEFAULT-DENY +
   ongoing_management consent gating on every personal-data table as created.
2. Re-fit engine: periodic re-measure of person vs. evolved role version; four-quadrant
   computation as a time-series; activate the evolution-vector field. Tests: re-fit
   appends a new profile/fit version (no destructive overwrite); quadrant logic correct;
   gated by ongoing_management consent; revocation removes access.
3. Pulse & signals: consented, low-burden check-ins feeding the time-series; employee
   owns/sees their own. Tests: no data without consent; employee self-visibility works;
   no background collection path exists.
4. Team composition: aggregate from members' OWN profiles; gap feed into Role
   Architecture. Tests: NO peer-personality path; gap correctly feeds Phase 1 engine.
5. Guidance composer: grounded generation over labeled-stub frameworks; "grounded"
   source chip; informing-not-instructing; log generations + manager actions. Tests:
   no freeform output about a named person; framework source recorded; frameworks are
   labeled stubs; manager action/dismissal logged.
6. Manager workspace + 1:1 prep UI, AND the employee self-view, per DESIGN.md. The
   employee self-view is a REQUIRED part of this step (transparency principle), not
   optional.
7. End-to-end scenario seed: a placed employee (from Phase 2) with ongoing_management
   consent → pulse check-ins over time → re-fit shows an "emerging misfit" trajectory
   → grounded developmental guidance generated → manager records an action → employee
   views their own profile + the same signals. Then test the revocation path: employee
   revokes ongoing_management → manager lifecycle access to that person disappears.
8. Verification: automated tests for consent gating + revocation, time-series integrity,
   four-quadrant logic, grounded-not-freeform guidance, no-surveillance affordances
   (no hidden scores, no peer rating, no background collection), employee self-view,
   and the no-second-bridge rule + a manual walkthrough.

## Working style
- Plan before code each step; small reviewable diffs; tests alongside, not after.
- Ask, don't guess, on anything touching consent gating, the developmental-vs-
  surveillance line, the grounded-guidance seam, RLS scope, or time-series integrity.
  A confident wrong guess there is expensive and can make the product unusable/unethical.
- Comment the consent gating, re-fit time-series logic, and guidance-grounding seam
  thoroughly — they are load-bearing (security AND ethics).
- No new third-party deps beyond Supabase, the test runner, the named frontend libs,
  and (if needed for RAG over frameworks) a clearly-scoped retrieval lib — ask first.

## Definition of done for Phase 3
A manager can, in the running app: see a grounded, source-attributed living profile and
1:1 prep for each direct report; view team composition built from members' own profiles;
see a re-fit fit-trajectory with the four-quadrant signal on the evolved role; and record
an action on an INFORMING (never deciding) suggestion. An EMPLOYEE can view their own
profile, pulse data, re-fit history, and the same signals their manager sees. ALL of this
is gated by active ongoing_management consent, and revoking it removes the access
(tested). profiles remain a non-destructive time-series; outcomes are captured (not
modeled); guidance is grounded + logged with sample/stub frameworks clearly labeled; no
surveillance affordance, no peer-personality rating, no second cross-org path exists. Then
summarize what's built, what's stubbed pending real frameworks IP + the I/O psychologist,
and the exact entry point for Phase 4 (predictive intelligence + EU AI Act bias audit).

Begin with Step 0 (verify Phases 0–2, read, restate the two overriding principles,
summarize), then STOP for my confirmation.
```

---

## How to use this
1. Run **only after Phases 0–2 tests pass.** The prompt re-verifies them and refuses
   to build on a broken foundation.
2. Paste the fenced block; it reads the specs, confirms state, restates the two
   overriding principles, summarizes its plan, and **pauses**.
3. Work the checkpoints one at a time; review the consent gating, the re-fit time-series
   logic, and the guidance-grounding seam yourself.

## Why it's shaped this way (and how it differs from Phases 0–2)
- **Same discipline** — verify-prior-phases gate, security-critical parts first with
  DEFAULT-DENY RLS + consent, "done" = automated tests, ask-don't-guess on sensitive seams.
- **The defining new rule: developmental, never surveillance.** Phase 3 is where the
  product could quietly become an employee-monitoring tool. The prompt enforces this
  structurally — ongoing_management consent gates everything, the EMPLOYEE SELF-VIEW is
  a required deliverable (transparency, not a one-way mirror), no hidden manager-only
  scores, no peer rating, no background collection, developmental framing in copy + data.
  This isn't ethics theater; if employees experience it as surveillance they'll game the
  pulse data and the whole signal degrades.
- **Grounded-guidance discipline carried forward** — the guidance composer uses the same
  labeled-stub-frameworks + RAG + logging pattern as the Phase 1 I/O seam and Phase 2
  kickstart, so no invented management science ships as validated.
- **Time-series integrity is explicit** — re-fit APPENDS profile versions
  (valid_from/valid_to), never overwrites, because the trajectory IS the value and the
  ground-truth Phase 4 will model. Tested for non-destructiveness.
- **Captures outcomes, doesn't model them** — the prompt draws a hard line: Phase 3
  stores the outcome ground-truth; Phase 4 trains on it. Keeps the moat-building data
  flowing without prematurely building (or faking) prediction.
