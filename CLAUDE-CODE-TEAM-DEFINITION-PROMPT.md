# Claude Code — Team-Based Role Definition (HeiTobias)

> Paste the fenced block below into Claude Code. This builds the **Team-Based Role Definition
> module** — the Delphi-style independent-rating workflow that produces a research-defensible,
> signed-off role version. This is where the science is *created*, not just displayed. The
> Role Profile detail page renders this module's output.
>
> **Hard prerequisites:** (1) Phase 0 Hardening §A–C complete (schema, RPCs, full Role Profile
> field model); (2) Role Profile detail page built (the rendering target for the output);
> (3) PHASE0-SPEC, SCIENCE-SPEC, and CLAUDE.md treated as authoritative. The prompt verifies
> these in Step 0 and refuses to proceed if missing.
>
> **Visual reference:** `team-based-definition.html` (a static mock showing the four-stage
> flow, the divergence-surfacing view, and the surveillance guardrail). The live build
> implements the *logic*; the mock shows the *visual contract*.

---

## What this module is and why it's load-bearing

Most platforms let a team define a role by sitting around a table and listing what they want.
Anchoring bias and the highest-status voice win; the resulting role profile *feels* shared
but is psychometrically thin and produces invalid downstream scoring.

Team-Based Role Definition uses **Delphi methodology** (Linstone & Turoff 1975; NGT) —
evaluators rate *independently first*, the system *surfaces divergence rather than averaging
it away*, and a structured reconciliation produces a final version with attributable
authorship. This is what makes the role profile defensible under EU AI Act Art. 11/12 and
makes the science the platform sells actually work.

**Non-negotiable, per SCIENCE-SPEC §7:** peers validate **role requirements** (tasks,
competency weights, context factors, trait targets for the *role*), **never each other's
personalities**. The schema enforces this; the UI must visibly honor it.

---

## Integration with other modules

This module is the **single canonical writer** of role versions. Every other module is a
reader or a downstream consumer.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    TEAM-BASED ROLE DEFINITION                            │
│                                                                          │
│  WRITES → roles_catalog (new version) via rpc_create_role_version (§B1) │
│           role_definition_evaluations (per-evaluator independent rating) │
│           role_definition_divergence_runs (computed divergence + Δ logs) │
│           role_definition_reconciliations (decisions + attributions)     │
│           audit_log (every action) + decision_artefacts (sign-off)       │
└──────────────────────────────────────────────────────────────────────────┘
        │                  │                    │                  │
        ▼                  ▼                    ▼                  ▼
  ROLE PROFILE       REQUISITION /         FIT SCORING        FRAMEWORKS
  DETAIL PAGE        HIRING FLOW           (Phase 1 +)        LIBRARY
  (Phase 1 add.)     (Phase 1)             (Phase 1)          (Phase 3)
  reads finalized    pins to a specific    reads the          tier-S/A
  version + shows    signed_off version    role version       competency
  attribution        ID; never "latest"    used at decision   templates
                                           time (frozen)      seed the
                                                              initial draft
        │                  │                    │
        ▼                  ▼                    ▼
  TEAM-GAP CONTEXT   AUDIT LOG / DPIA      RE-FIT ENGINE
  (Phase 3)          export                (Phase 3) reads
  reads role +       (Phase 4)             evolved role
  members' OWN       includes the          versions to
  profiles, NEVER    full Delphi           compute the
  peer ratings       provenance            four-quadrant
                                           trajectory
```

**The five integration contracts the build must honour:**

1. **Roles catalog versioning.** This module is the only sanctioned writer of new role
   versions. It must use `rpc_create_role_version` (Hardening §B1), never write directly.
   Every superseded version is retained (audit + re-fit history depend on it).
2. **Decision artefact discipline.** Every signoff, reconciliation override, and version
   promotion writes a `decision_artefact` row (Hardening §A4). No UI button mutates state
   directly.
3. **Requisitions pin to a specific version id, not "latest."** When a requisition is
   created from a role, it captures the immutable role version it was scored against. The
   Hiring flow must read from `requisition.role_version_id`, never from
   `roles_catalog.where(family=...).order(version desc)`.
4. **Frameworks Library seeds the initial draft.** When an evaluator starts a new role draft,
   the system pre-populates competencies (UCF / Great Eight), trait targets at family defaults
   (SCIENCE-SPEC §2), and context factors at family defaults. The evaluator can adjust; they
   cannot start from a blank slate. This anchors quality.
5. **Re-fit reads evolved versions.** When a role evolves (a new signed_off version
   supersedes), Phase 3's re-fit engine reads the new version to compute fit-trajectory. The
   evolution_vector field is the *forecast* of this, generated as part of the reconciliation
   step (labelled as forecast per SCIENCE-SPEC §5).

---

## The four-stage flow

```
   STAGE 1: SETUP                    STAGE 2: INDEPENDENT RATING
   ─────────────                     ──────────────────────────────
   Owner picks role family,          Each evaluator (3–7 ideal) rates
   purpose, evaluators, deadline.    in isolation — submissions are
   System seeds from Frameworks      sealed until everyone is in OR
   Library + family defaults.        the deadline passes. NO PEEKING.

           │                                      │
           ▼                                      ▼

   STAGE 3: DIVERGENCE                STAGE 4: RECONCILIATION
   ────────────────────               ─────────────────────────
   System computes per-criterion      Owner runs structured reconciliation
   spread + consensus. SURFACES        on flagged items: discussion notes
   disagreement; never averages it    + final value + per-evaluator
   away. Flags low-consensus items.   attribution. Sign-off writes new
                                       role version + decision_artefact.
```

Stages 2 and 3 are the load-bearing innovations. Stage 2 enforces independence (the Delphi
mechanism); Stage 3 makes disagreement productive instead of hiding it.

---

## The prompt — paste this block

```
You are building the TEAM-BASED ROLE DEFINITION module for HeiTobias. This is the workflow
that produces signed-off role versions through Delphi-style independent rating, divergence
surfacing, and structured reconciliation — the mechanism that makes downstream fit scoring
psychometrically defensible.

This is a Phase 1 module addition. The data layer is partly in place (the Phase 0 Hardening
landed roles_catalog with the full §2.7 field model + rpc_create_role_version); this work
adds the workflow tables, the four-stage flow, and the UI. You build the LOGIC and the SEAMS
correctly — the actual psychometric weight of "what counts as a low-consensus item" is a
labelled threshold that the I/O psychologist will tune; do not invent the number, expose the
seam.

Work as a careful senior engineer: plan first, build small verifiable increments, write tests
as you go, pause at the checkpoints.

## Step 0 — Read + verify prerequisites + summarize
1. Read in full and treat as authoritative:
   - SCIENCE-SPEC.md (esp. §5 Role Profile spec, §7 Delphi + surveillance guardrail, §10
     defensibility metadata)
   - PHASE0-SPEC.md §2.7 (Role Profile field model — the shape this module writes into)
   - CLAUDE.md (pillars, esp. #5 Scientific integrity; the "never" list — esp. no
     peer-personality rating)
   - DESIGN.md (v3 visual system)
   - team-based-definition.html (the visual reference for stages, divergence view, and the
     guardrail callout — the live build implements the LOGIC, mock shows the visual contract)
2. VERIFY PREREQUISITES. Confirm by querying schema + reading migrations:
   - roles_catalog.definition_json carries the full PHASE0-SPEC §2.7 structure (incl. trait
     `direction` enum, evolution_vector with confidence + next_review_date, validation_and_
     defensibility_metadata)
   - rpc_create_role_version exists and is the only path to insert a roles_catalog version
   - decision_artefact table exists; audit_log triggers are in place
   - validity_status enum + check constraint preventing 'validated' + stub-flagged values
   - The "disallow bare-maximum optimum trait target" constraint
   - The peer-personality-rating block (Hardening §A3) — verify the schema constraint
     prevents rater_person_id ≠ target_person_id with personality dimensions
   - Frameworks Library seed data exists for at least one role family (engineering minimum)
   If any prerequisite is missing, STOP and report. Do NOT paper over.
3. Summarize back (<=15 bullets): the prerequisites confirmed, the workflow tables you'll
   add, the four-stage flow mapped to UI routes, the integration touchpoints with other
   modules, your build sequence. STOP for confirmation.

## OVERRIDING PRINCIPLES (restate in your plan)
A) INDEPENDENCE IS THE WHOLE POINT. Stage 2 evaluator submissions MUST be sealed until all
   submit OR the deadline passes. A peek is a methodology breach. Enforce server-side
   (RLS on role_definition_evaluations); enforce client-side (no UI to see others' submissions
   pre-reveal); enforce audit-side (log every read attempt against the table during Stage 2).
B) DIVERGENCE IS SURFACED, NEVER AVERAGED AWAY. The system computes a spread metric per
   criterion (e.g. SD, range, % disagreement on critical-vs-not). For low-consensus items
   the UI shows individual positions (anonymized in the default view; named only with explicit
   reveal-permission), the rationale notes, and forces a reconciliation. Silent averaging is a
   methodology breach AND a UI defect.
C) NO PEER-PERSONALITY RATING. The evaluator UI must visibly remind evaluators they are
   rating ROLE requirements (tasks, competency weights, trait targets for the role context,
   context factors), NEVER each other's personalities. The schema constraint blocks it; the
   UI must not even surface the possibility.
D) RECONCILIATION IS ATTRIBUTABLE. Every Stage 4 decision (final value, override of group
   spread, weight adjustment) writes a decision_artefact with the decider, the rationale,
   and links to the dissenting evaluations. The role profile's
   `validation_and_defensibility_metadata` records ICC/Kendall's W + the reconciliation
   summary.
E) ALL THRESHOLDS ARE LABELLED STUBS. "What SD counts as low consensus" / "how many
   evaluators required for a valid run" / "ICC cutoff for sign-off" — these are I/O
   psychologist judgments. Encode them as configurable thresholds with `validity_status='dev_
   stub'` and a clear "DEV STUB — requires I/O sign-off" label in the UI for any threshold
   actively in use. Refuse to invent the values; ship sensible-looking defaults clearly
   flagged as such.
F) FORECAST FRAMING ON EVOLUTION VECTOR. The reconciliation step has an evolution-vector
   sub-step where evaluators provide a forecast — UI labels it explicitly as "Forecast — not
   a measurement" with confidence + sources + next_review_date.

## SCHEMA — new tables (migrations)

### role_definition_runs
Represents one complete role-definition exercise. One row per role-version-being-defined.
- id, org_id, role_family, role_template_id (from Frameworks Library seed), purpose enum
  ('initial_definition' | 'evolution_revision' | 'periodic_review'), owner_user_id,
  deadline_at, stage enum ('setup' | 'rating' | 'divergence' | 'reconciliation' | 'signed_off'
  | 'abandoned'), starts_at, completed_at, target_role_version_id (nullable; set on
  sign-off), thresholds_json (snapshot of the I/O-tunable thresholds active at run start),
  consensus_summary_json (computed at end of Stage 3), created_at, updated_at.

### role_definition_evaluators
- id, run_id, user_id, role (enum: 'manager' | 'team_member' | 'peer_team_lead' |
  'recruiter' | 'sme_external'), invited_at, accepted_at, submitted_at (nullable), reminded_at[],
  weight_in_aggregation numeric default 1.0 (NOT used for any user's score — used for the
  divergence weighting where senior SMEs may weigh more).

### role_definition_evaluations
The independent rating itself. One row per evaluator per run.
- id, run_id, evaluator_id (FK to role_definition_evaluators), submitted_at (nullable until
  sealed), rating_json (the evaluator's per-criterion proposed values: task criticalities,
  competency weights, trait band targets, context factor values, success criteria
  importance), rationale_notes_json (per-criterion free-text justification), allow_attribution_
  on_reveal boolean default true.

**RLS RULES (load-bearing):**
- Pre-reveal (run.stage IN ('setup', 'rating')): an evaluator can SELECT/UPDATE only their
  own row. Others' rows are invisible. Even the run owner cannot see them.
- At Stage 3 entry, the server-side `rpc_seal_evaluations(run_id)` transition flips the
  run.stage to 'divergence' and atomically marks all submitted rows as immutable. After
  this point, the run owner + designated reconciler can SELECT all rows in this run, but
  not UPDATE.
- Any read attempt against role_definition_evaluations during Stage 2 writes to audit_log
  with attempted_action='read_during_seal'. A run owner repeatedly attempting reads is itself
  a defensibility flag.

### role_definition_divergence_runs
- id, run_id, computed_at, criterion_key (which competency/trait/context-factor was
  analysed), spread_metric_type enum ('sd' | 'range' | 'percent_disagree' | 'kendalls_w'),
  spread_value numeric, consensus_category enum ('high' | 'moderate' | 'low'), flagged_for_
  reconciliation boolean, ranges_json (anonymized distribution of values for surfacing).

### role_definition_reconciliations
- id, run_id, criterion_key, reconciler_user_id, discussion_notes_text, final_value_json,
  attribution_json (which evaluators' positions influenced the final, with consent), decided_at,
  decision_artefact_id (FK).

### role_definition_thresholds (the labelled stub seam)
Configurable thresholds the I/O psychologist will tune.
- id, org_id (nullable for global defaults), threshold_key (e.g. 'low_consensus_sd_cutoff',
  'min_evaluators_for_valid_run', 'iccc_signoff_cutoff'), value numeric,
  validity_status validity_status_t default 'dev_stub', _dev_stub boolean default true,
  notes_text, last_signed_off_by, last_signed_off_at.

**DB constraint:** matching the Phase 0 Hardening pattern — a row cannot be
`validity_status='validated'` while `_dev_stub=true`.

## RPCs — new

### rpc_create_role_definition_run
Atomic, policy-checked. Creates a run + invites evaluators + seeds the initial draft from
Frameworks Library + family defaults. Writes audit + a decision_artefact for the run launch.

### rpc_submit_evaluation
The evaluator's submit action. Atomic; sets submitted_at; verifies the evaluator has not
peeked (read log clean); locks the row from further edits.

### rpc_seal_evaluations
The Stage 2 → Stage 3 transition. Server-side only. Requires either: (a) all invited
evaluators submitted, OR (b) deadline passed with at least the threshold min_evaluators
submitted. Flips run.stage; runs the divergence computation; writes audit_log.

### rpc_record_reconciliation
The Stage 4 action. Atomic; writes the reconciliation row + decision_artefact + updates a
DRAFT next-version of the role's definition_json in a staging area.

### rpc_signoff_role_version
Final action. Calls rpc_create_role_version (the existing Hardening §B1 RPC) with the
reconciled definition_json. Sets run.stage='signed_off' and run.target_role_version_id. The
new roles_catalog row carries the full provenance in validation_and_defensibility_metadata:
ICC/Kendall's W, evaluator count, reconciliation summary, sign-off attribution.

## UI — four routes + the shared role definition shell

- /roles/define/new — Stage 1 setup (owner only)
- /roles/define/:run_id/rate — Stage 2 the evaluator's independent rating form
- /roles/define/:run_id/divergence — Stage 3 the surfaced divergence view (owner + reconciler)
- /roles/define/:run_id/reconcile — Stage 4 the reconciliation flow (reconciler only)
- /roles/define/:run_id — the run dashboard (visible to all evaluators with appropriate
  scope hiding)

Each route uses the v3 shell (cream-green canvas, forest tab band, three-tier shell already
in place, Lucide icons, soft tinted status pills, role-blue/person-green discipline).

The DIVERGENCE VIEW is the signature component of this module. For each criterion it
shows:
- A horizontal scale of values
- Each evaluator's submitted value as a dot (anonymized by default — labelled "E1, E2..."
  with role; named only with explicit reveal-permission per evaluator's
  allow_attribution_on_reveal)
- A consensus pill (high / moderate / low) and the spread metric
- Each evaluator's rationale-note as expandable text
- A "needs reconciliation" badge for low-consensus items
- For trait targets: render with the TraitRangeControl, with multiple bands overlaid
  semi-transparently so divergence is visible

The PEER-PERSONALITY GUARDRAIL must be visible:
- A persistent on-page note in Stages 2 and 3: "You are rating the ROLE — its tasks,
  competency weights, trait targets for the role context, and context factors. You are NOT
  rating any specific person."
- The trait-target rating control is for the ROLE band (with `direction` discipline from
  Phase 0 Hardening §C3), not a person.

## Build sequence — plan, build, test, PAUSE at each checkpoint

1. SCHEMA: the five new tables + the RPCs + the RLS policies (with the seal/reveal logic
   correctly enforced server-side). Tests: pre-reveal read attempt by run owner is rejected
   AND logged; submit + read after seal works for owner; cross-run cross-org isolation holds.
   CHECKPOINT 1.

2. THE INDEPENDENT-RATING WORKFLOW: setup (Stage 1) + rate (Stage 2) UIs + rpc_submit_
   evaluation + rpc_seal_evaluations. Tests: an evaluator cannot see another's submission
   pre-reveal in any UI route or query path; submissions are locked at submit; seal
   transitions only with the threshold met.
   CHECKPOINT 2.

3. DIVERGENCE COMPUTATION + VIEW: the divergence-runs table writes + the divergence UI.
   Tests: low-consensus items are flagged correctly per the threshold; values are NOT
   averaged into a single number when consensus is low; anonymization is respected unless
   the evaluator opted into named attribution.
   CHECKPOINT 3.

4. RECONCILIATION + SIGN-OFF: Stage 4 UI + rpc_record_reconciliation + rpc_signoff_role_
   version. The signoff calls rpc_create_role_version with the reconciled definition_json
   AND the full provenance (ICC, evaluator count, reconciliation summary) in
   validation_and_defensibility_metadata. Tests: reconciliation overrides write decision_
   artefacts; sign-off creates a new roles_catalog row with provenance; the new version is
   pickable by the Hiring flow.
   CHECKPOINT 4.

5. INTEGRATION TESTS (end-to-end across modules):
   - The Role Profile detail page renders the new version, with the validation_and_
     defensibility_metadata visible (ICC, Kendall's W, evaluator count, reconciliation
     summary) and the SAMPLE/STUB banner correctly absent because the version is now
     signed_off (though individual fields may still be stubbed per their own validity_status).
   - A requisition created from the new version pins `requisition.role_version_id`; a
     superseding new version does NOT change the requisition's view.
   - The role evolution_vector forecast is rendered on the detail page with the FORECAST
     label.
   - Team-gap context (Phase 3) reads from the new role version + members' own profiles;
     no peer-personality path is exercised.
   - The Phase 4 audit/DPIA export includes the full Delphi provenance.
   CHECKPOINT 5.

6. POLISH + ACCESSIBILITY:
   - i18n at least en + nb-NO (rest of the project)
   - Keyboard navigation through the rating form
   - Sensible empty states (no evaluators yet; deadline passed with min not met; everyone
     submitted; first-time-defining-this-family)
   - Reminders: an evaluator who has not submitted gets a daily reminder; the owner sees a
     progress counter
   CHECKPOINT 6.

## TESTS — required, evidence-based

Beyond the per-checkpoint tests above, the following automated tests MUST exist and pass:

INDEPENDENCE (Stage 2 sealing — load-bearing methodology):
- T1: Evaluator A cannot SELECT or read Evaluator B's role_definition_evaluations row
  during Stage 2, via any code path (RLS test).
- T2: Run owner cannot SELECT or read any role_definition_evaluations row during Stage 2
  (RLS test; this is intentional, against intuition).
- T3: Any read attempt against role_definition_evaluations during Stage 2 writes an audit_
  log row with attempted_action='read_during_seal'.
- T4: After rpc_seal_evaluations, all SELECTs are allowed to owner + reconciler; UPDATEs are
  still rejected (rows are immutable post-submit).

PEER-PERSONALITY BLOCK (the SCIENCE-SPEC §7 non-negotiable):
- T5: An attempt to INSERT into role_definition_evaluations.rating_json a structure that
  rates a named person's personality (e.g. {"target_person_id": "X", "trait": "C"}) is
  rejected at the schema level.
- T6: The rating UI does not present a "rate a person" affordance anywhere.

DIVERGENCE FIDELITY:
- T7: Given evaluations with high spread, the system flags 'low' consensus and does NOT
  produce a single averaged value; the UI shows individual positions.
- T8: Given evaluations with tight clustering, the system flags 'high' consensus and the
  reconciliation step is skippable (with audit).

RECONCILIATION + SIGN-OFF:
- T9: A reconciliation override writes a decision_artefact citing the dissenting evaluations.
- T10: Sign-off calls rpc_create_role_version (no direct INSERT); the new roles_catalog row
  carries provenance in validation_and_defensibility_metadata.
- T11: Concurrent sign-offs on the same run fail safely (one succeeds, others rejected with
  clear error).

INTEGRATION:
- T12: A requisition created after sign-off pins the new version id; a subsequent new
  version does not change the requisition's frozen view.
- T13: The Role Profile detail page renders the new version's provenance fields.
- T14: Team-gap (Phase 3) reads the role's competency weights + trait bands; no
  peer-personality table is consulted.

THRESHOLDS / STUBS:
- T15: All thresholds in role_definition_thresholds start with validity_status='dev_stub';
  a test asserts no validated rows in fixtures.
- T16: A row cannot transition to validity_status='validated' while _dev_stub=true.

## REVIEW CODE — for the human auditor (you, post-build)

This module is the methodology heart of the science the platform sells. After Claude Code
completes, a human reviewer (security/architecture background) MUST verify the following.
Treat this as a checklist; check each box only with evidence in hand.

### Authentication of independence
[ ] Read the rpc_seal_evaluations function SQL. Confirm it cannot be called by an evaluator
    (only run owner with permission, or via the deadline cron). 
[ ] Read the RLS policy on role_definition_evaluations. Confirm the USING clause for SELECT
    during stage='rating' refers only to the row's own evaluator. Confirm the WITH CHECK on
    UPDATE prevents post-submit modification.
[ ] Try to query role_definition_evaluations as the run owner during Stage 2 in a SQL
    console with the owner's JWT. Confirm zero rows returned (intentional).
[ ] Grep the codebase for `from role_definition_evaluations` or equivalent ORM access; for
    each hit, trace whether RLS would gate it. If any path bypasses RLS (e.g. service-role
    key, raw SQL), confirm it's the seal/reveal RPC and nothing else.

### Authentication of the surveillance guardrail
[ ] Read the schema constraint preventing peer-personality rating. Try to INSERT a row that
    violates it; confirm rejection at the database level (not application code).
[ ] Walk the rating UI. Confirm there is no UI affordance to select a named person as a
    rating target. The only rating targets should be ROLE structural elements (tasks,
    competencies, traits-for-the-role, context factors).
[ ] Read the divergence view code. Confirm the default mode anonymizes evaluator identity;
    confirm naming requires explicit per-evaluator opt-in (allow_attribution_on_reveal).

### Authentication of decision-artefact discipline
[ ] For each mutating action (launch run, submit evaluation, seal, reconcile, override,
    sign off): confirm the corresponding RPC writes a decision_artefact row + an audit_log
    row. No UI button mutates state without going through the RPC.

### Authentication of integration contracts
[ ] Read the Hiring flow's role-version handling. Confirm requisitions pin role_version_id
    at creation; reads use the pinned id, not "latest by family."
[ ] Read the Role Profile detail page. Confirm it renders provenance (ICC, evaluator count,
    reconciliation summary) for signed_off versions.
[ ] Read the re-fit engine (Phase 3, if built). Confirm it reads the role version pinned at
    each re-fit time, not "latest."
[ ] Read the Phase 4 export RPCs. Confirm they include the full Delphi provenance per role
    version.

### Authentication of stubs
[ ] Grep for `validity_status='dev_stub'` and `_dev_stub` in seed data + role_definition_
    thresholds. Confirm every threshold actively used is labelled stub until an I/O
    sign-off lands.
[ ] Run the test asserting no row has validity_status='validated' in any fixture.

### Adversarial smoke test
[ ] As a hostile reviewer: try to (a) submit twice as the same evaluator, (b) submit after
    sealing, (c) seal with too few submissions, (d) sign off without reconciling
    low-consensus items, (e) sign off twice on the same run. Confirm each is rejected with
    a clear error.

## Definition of done
- The five new tables + RPCs + RLS policies are in place; all 16 enumerated tests pass.
- The four-stage UI flow is built per DESIGN.md, with the surveillance guardrail and FORECAST
  framing visible in the right places.
- Integration tests pass: requisitions pin version id; Role Profile detail page renders
  provenance; team-gap reads role + own-profiles only; Phase 4 export includes Delphi
  provenance.
- All thresholds are labelled `validity_status='dev_stub'`; no fabricated psychometric
  cutoffs ship as validated.
- The human review checklist above can be ticked off with cited evidence (file/line, query
  result, test name, RPC SQL). Where any box cannot be ticked, the build is not done.

Begin with Step 0 (read, verify prerequisites, summarise plan), then STOP for my
confirmation.
```

---

## How to use this
1. Run **only after** Phase 0 Hardening (§A–C) AND the Role Profile detail page work are
   complete. The prompt verifies prerequisites and refuses to proceed if missing.
2. Paste the fenced block; it pauses at each checkpoint.
3. After Claude Code reports done, **walk the human review checklist yourself** — this is the
   methodology heart of the science the platform sells, so the load-bearing pieces (Stage 2
   sealing, the peer-personality block, the decision-artefact discipline) deserve actual eyes.

## Why it's shaped this way
- **The methodology is the moat.** Delphi independence is what makes downstream fit scoring
  defensible; an agent will happily "improve" it into a friendlier round-table view if not
  told otherwise. The Stage 2 sealing is enforced server-side (RLS), client-side (UI), and
  audit-side (read attempts logged) — three locks because the failure is silent if any one
  is bypassed.
- **Divergence-surfacing is explicit.** "Don't silently average" is stated as a methodology
  breach AND a UI defect; the divergence view is the signature component and has its own
  test (T7) ensuring high-spread inputs don't collapse to a single value.
- **Integration is mapped, not implied.** Five integration contracts are spelled out and
  each gets an integration test (T12–T14). The classic failure mode here is "this module
  works, but the Hiring flow silently reads 'latest by family' instead of the pinned
  version" — T12 catches that.
- **The human review checklist is built in.** Self-audit isn't enough for this module
  because the methodology IS the value. The checklist gives you concrete commands to run
  (try the read during sealing, try the peer-personality INSERT) and concrete evidence to
  collect.
