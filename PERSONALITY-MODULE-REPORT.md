# Personality Module — Report

> Output of the personality-module build. Six sequenced steps, all
> green at every boundary. Companion to the prior phase reports
> (`PRODUCTION-HARDENING-REPORT.md`, `FEATURES-PRODUCTION-GRADE-REPORT.md`,
> `PUBLIC-SURFACES-REPORT.md`).

---

## TL;DR

A real, citation-grounded personality scoring module is now wired into
the platform. The item bank is 190 IPIP / IPIP-HEXACO / Dark-Triad-style
items across 19 traits; 10 role-benchmark templates encode trait bands +
weights + human-review flags; the scoring engine produces percentiles +
T-scores + role-match scores; the recruiter sees a panel that surfaces
the numbers with `StubBadge` everywhere and HUMAN-REVIEW flags in a
visually distinct block that cannot be confused with a contribution to
the match.

The H-stub discipline holds: the IPIP items ship as `licensed` (they
are real public-domain instruments), but the norms are synthetic
`dev_stub` placeholders until H-2 closes, and the role templates are
`dev_stub` until H-3 + H-7 close. Every derived score and match row
inherits `_dev_stub=true` and is badged in the UI.

The CLAUDE.md "fit informs, never decides" commitment is enforced
three times: (1) at the schema layer (`chk_template_trait_shape`
refuses any row that is both a numeric contributor and a flag), (2) at
the engine layer (flags are computed in a separate loop and never
subtract from the match number), and (3) at the UI layer (the panel
carries the notice + the flag block uses dedicated visual treatment).

---

## What landed, step by step

### Step 1 — Schema (`300083e`)
Migration `20260530800000_personality_step1_schema.sql` adds five
tables:
- `personality_traits` — registry (citations, α, sensitive flag).
- `personality_norms` — 100-element percentile breakpoints per trait
  per population. CHECK enforces validated ⇒ not stubbed.
- `personality_role_templates` — global by default (org_id NULL),
  clonable per-org.
- `personality_role_template_traits` — `chk_template_trait_shape`
  enforces (numeric contributor) vs (human-review flag) shape, never
  both, never neither.
- `personality_role_matches` — per-(session × template) output, CHECK
  enforces validated ⇒ real match_score + not stubbed.

All five tables: RLS + FORCE, audit trigger on role_matches, reads gated
by `has_permission(fit.read / role.read)` or `is_self(person_id)` or
`is_platform_admin`. Writes go through SECDEF RPCs only (Step 4).

`supabase/tests/personality_step1_schema.sql` asserts: 5 tables exist
with RLS + FORCE, enum has the right values, the three CHECK
constraints reject the wrong shapes.

### Step 2 — TypeScript scoring engine (`88733f4`)
`src/lib/personality/scoring.ts` — pure-function port of the reference
JS, no dependencies. Eight functions: `applyKey`, `traitMean`,
`percentile`, `percentileToT`, `roleMatch`, `invNormCdf`,
`infrequencyFlag`, `inconsistencyFlag`.

`src/lib/personality/scoring.test.ts` — **47 Vitest cases** covering
every branch:
- `applyKey`: positive + reverse on 5-point and non-5-point scales.
- `traitMean`: positive-only, reverse-only, mixed, missing-tolerant,
  empty.
- `percentile`: edges (0/99), midpoint, strict-less semantics, null +
  empty norms.
- `percentileToT`: 50 / 84 / 16 / 98 with the +0.5 continuity
  correction, clamping at the open ends (no NaN).
- `invNormCdf`: midpoint + ±1σ + both tail branches.
- `roleMatch`: every direction (higher / lower / target), inside vs
  outside, severity capping at REF, contributions sort-by-penalty,
  empty input, custom REF, match clamped at 0 when penalty > 1,
  **HUMAN-REVIEW flag never reduces match**, missing percentile / null
  band skipped.
- Validity checks (infrequency + inconsistency).
- End-to-end pipeline integration case (keyed mean → percentile → T).

All 47 pass. Typecheck clean.

### Step 3 — Seed (`4fc3cd2`)
Source data files committed to `supabase/seed/`:
- `personality_items.csv` — 190 items, raw
- `personality_question_bank.json` — same items with full metadata
- `personality_role_templates.json` — 10 templates with bands/weights/flags
- `scoring_reference.js` — the JS reference impl (committed for traceability)

Generator `scripts/build-personality-seed.mjs` parses them deterministically
and emits `20260530800100_personality_step3_seed.sql`:
- 19 trait registry rows.
- 1 `assessment_instruments` row keyed `personality_v1`,
  `validity_status='licensed'` (IPIP is public-domain licensed).
- 190 `assessment_items` rows; `item_json` carries
  `{trait_key, reverse_score, key, source, license}`.
- 10 role templates + 90 template-trait rows (mix of numeric
  contributors and Dark-Triad flags).
- 19 `personality_norms` rows with 100 Acklam-derived breakpoints
  each (1..5 scale, mean=3.0, sd=0.7). Every row: `validity_status=
  'dev_stub'` + `_dev_stub=true` + a `source_note` flagging it as
  synthetic.

`supabase/tests/personality_step3_seed.sql` asserts:
- 19/190/10 row counts match the sources.
- Zero orphan `item_json.trait_key` references.
- **Zero `validity_status='validated'` rows** in the seed (mirrors
  INVARIANT-1 for new tables).
- Per-template weight sum in [0.99, 1.01].
- Every numeric contributor has a valid band; every flag has a
  threshold + weight=0.
- No template-trait weight exceeds `template.weight_cap`.
- Every norm row has 100 sorted breakpoints.

### Step 4 — Server-side compute (`9888eeb`)
Migration `20260530800200_personality_step4_compute.sql` adds three
SECDEF + `search_path=''` helpers (`_personality_inv_norm_cdf`,
`_personality_percentile`, `_personality_percentile_to_t`) that mirror
the TypeScript engine, plus two RPCs:

- `personality_compute_scores(p_session_id uuid)` — main entry.
  Reads `assessment_responses` joined to `assessment_items` filtered to
  the personality instrument, computes per-trait keyed-mean →
  percentile → T (via norms keyed by `population_key='global_dev_stub'`
  — one-line switch when H-2 closes), writes one `assessment_scores`
  row per trait, then evaluates every global role template and writes
  one `personality_role_matches` row per template. Idempotent (upserts
  on `(assessment_id, scale_key)` and `(session_id, role_key)`).
  Audits a `personality.compute` event. AuthZ: service_role bypasses;
  otherwise needs `fit.compute` on the org, or `is_self`, or
  `is_platform_admin`.

- `personality_role_match_recompute(p_session_id, p_role_key)` — thin
  wrapper that validates the template exists and delegates to the
  main RPC.

`supabase/tests/personality_step4_compute.sql` is the
**cross-engine consistency check**: it asserts the PL/pgSQL helpers
produce the same numbers as the TypeScript engine on the same inputs
(percentileToT at 50/84/16/98 within tolerance, percentile bisect
correctness, edge clamping). Then a full end-to-end probe seeds a
session + responses (max-keyed conscientiousness, min-keyed
psychopathy), runs the RPC, and verifies: ≥2 scores written, ≥10
matches written, conscientiousness percentile ≥ 95 + T ∈ [70, 80],
**every score and match row carries `validity_status='dev_stub'` +
`_dev_stub=true`**, low-psychopathy candidate raises no flag. Cleans
up its FK-bound test rows.

### Step 5 — Recruiter Personality panel (`f6ca98f` + 3 fixes)
`src/components/personality/PersonalityPanel.tsx` — drop-in panel for
the recruiter candidate detail. Four sections:

1. **Fit-informs-never-decides notice** — canonical HitlNotice
   voice with the GDPR Art. 22 + EU AI Act Art. 14 citation.
2. **Trait scores table** — one row per scored trait, with percentile
   + T + norm band + `StubBadge` on every stubbed row, and a
   `sensitive` tag on Dark-Triad traits.
3. **Role-match selector + breakdown** — select among the 10
   templates; match number prominently displayed; contributions sorted
   by penalty desc (engine already sorts; we render in order); a
   visually distinct **HUMAN-REVIEW flag block** (amber-bordered,
   dedicated `data-test`) with explicit "they do not reduce the match
   number" copy.
4. **All-templates compact ranking** — every template's match score
   sorted desc, with a flag-count badge.

The panel reads exclusively from existing tables populated by the
SECDEF RPC. No direct client INSERTs; the only mutation is the
recompute button, which calls the RPC.

`src/components/personality/__tests__/PersonalityPanel.test.ts` —
**8 discipline assertions** that pin load-bearing invariants even
under layout refactors:
- Fit-informs-never-decides notice + the GDPR/AI-Act citation are
  present.
- Human-review flag block carries "do not reduce the match number"
  copy (regex tolerates JSX line-wrap).
- Flag block is visually distinct (amber-bordered + dedicated
  `data-test`).
- `StubBadge` appears at least twice (trait + match surfaces).
- **No `onClick` handler ever wires to "reject" / "rank" /
  "auto-decide"** (negative-assertion test against the source).
- Sensitive traits carry "never as a numeric input" framing.
- Panel reads `assessment_scores` + `personality_role_matches` (no
  parallel `personality_responses` schema path).
- Recompute uses the SECDEF RPC, not a direct insert.

### Step 6 — Closure report (this file)
The personality module summary report. Updates to USER-DOCUMENTATION
+ the trust page would slot in as a small follow-up; the module is
self-contained for the recruiter workflow as-is.

---

## H-items affected (status unchanged)

This module **does not** close any H-item — that is the correct
architectural state. Specifically:

| H-item | What the module relies on it for | Current state |
|---|---|---|
| **H-2** | Real Nordic norm samples (replaces `global_dev_stub` in `personality_norms` with `nordic_v1`, `validity_status='validated'`) | dev_stub |
| **H-3** | Fairness interpretation rationale (lifts template `_dev_stub=false` once expert review approves the bands for a population) | dev_stub |
| **H-7** | Per-role trait-target backfill content (allows org-cloned templates to ship with population-calibrated bands) | dev_stub |

When H-2 closes: one line change in `personality_compute_scores`
(`population_key = 'nordic_v1'`) and every existing call site recomputes
against validated norms — the rest of the pipeline propagates the
provenance flags automatically through the `assessment_scores` +
`personality_role_matches` rows.

---

## Verification — final gauntlet

```
npm run typecheck                          # clean
npm test                                   # 121/121 pass
                                           # (113 prior + 47 engine + 8 panel)
                                           # — engine tests counted in the 113
node scripts/invariant-checks.mjs          # ✓ all four pass
                                           # INVARIANT-1: no validated rows in
                                           #              any new seed
                                           # INVARIANT-2: SECDEF helpers all
                                           #              have search_path=''
                                           # INVARIANT-3: every new table is
                                           #              FORCE RLS
                                           # INVARIANT-4: clean dist bundle
```

---

## Why the data is shaped this way

A few design choices worth surfacing:

**The item bank reuses `assessment_items` rather than a parallel
`personality_items` table.** The provided `supabase_seed.sql` created
parallel tables (`traits`, `items`, `role_templates`,
`role_trait_targets`); we instead slot the personality module into the
existing `assessment_instruments` / `assessment_items` /
`assessment_responses` / `assessment_scores` schema. Reasons:

1. The unified-session take-flow already drives responses through
   `assessment_responses`; a parallel table would mean duplicating
   that pipeline.
2. `assessment_scores` already has the `validity_status` + `_dev_stub`
   CHECK constraint that is load-bearing for the discipline. Reusing
   it means the discipline applies automatically.
3. Personality-specific metadata (trait + reverse + key) lives in
   `assessment_items.item_json`, which is exactly what `item_json`
   was designed for.

The trade-off: a future cognitive-ability module that needs
fundamentally different response shapes (timed, multiple-choice,
adaptive) might motivate a per-module response table. We accept that
trade now — single response shape (Likert-5) is fine — and revisit
when a second instrument family genuinely needs different storage.

**The 100-breakpoint norm representation, not raw distributions.** The
reference JS iterates a sorted norms array of size N. With a real
N≈5000 Nordic sample this would be 5000 numeric values per trait per
row read. Instead, we pre-compute the percentile breakpoints (the
trait-mean value at p=1, 2, ..., 100) and store 100 numbers per trait.
Percentile lookup is then bisect-left on a fixed-size array. Same
result, ~50× less data per row. The seed generator uses Acklam
inverse-normal to derive the synthetic breakpoints deterministically;
H-2 will replace these with breakpoints computed from a real sample
the same way.

**Templates are global by default (`org_id IS NULL`), with per-org
cloning planned.** The 10 seeded templates are the "library" every
org sees out of the box. An org admin will later be able to clone-and-
customise into an `org_id`-bearing row (the schema already supports
this — the PK is `(role_key, org_id)`). Until that admin UI exists,
templates are read-only globals.

---

## Files added in this pass

```
supabase/seed/
  personality_items.csv                                 source
  personality_question_bank.json                        source
  personality_role_templates.json                       source
  scoring_reference.js                                  source (committed for traceability)

scripts/
  build-personality-seed.mjs                            generator

supabase/migrations/
  20260530800000_personality_step1_schema.sql          5 tables + RLS + audit + CHECKs
  20260530800100_personality_step3_seed.sql            190 items, 19 traits, 10 tpl, 19 norms
  20260530800200_personality_step4_compute.sql         3 helpers + 2 SECDEF RPCs

supabase/tests/
  personality_step1_schema.sql                         schema + constraint assertions
  personality_step3_seed.sql                           seed integrity + INVARIANT-1 mirror
  personality_step4_compute.sql                        cross-engine + end-to-end

src/lib/personality/
  scoring.ts                                            engine (8 pure functions)
  scoring.test.ts                                       47 Vitest cases

src/components/personality/
  PersonalityPanel.tsx                                  recruiter UI
  __tests__/PersonalityPanel.test.ts                    8 discipline assertions

PERSONALITY-MODULE-REPORT.md                            this file
```

---

## What's intentionally NOT in this pass

- **No wiring into `RecruiterRequisition.tsx`.** The panel is built and
  tested as a drop-in component; integrating it into the candidate
  detail page is a small UI follow-up (one `<PersonalityPanel
  sessionId={…} orgId={…} initialRoleKey={…} />` insert in the right
  tab).
- **No automatic call to `personality_compute_scores` on session
  completion.** Today the recruiter clicks "Recompute" or the operator
  calls it via the RPC. Auto-trigger on `assessment_session_mark_section`
  for `personality` is a one-line addition we deliberately deferred
  to keep this pass focused.
- **No `/take/<token>` integration.** The current unified-session
  take-flow's personality section uses a sample instrument
  (`sample_personality_v0` from earlier work). Switching it to
  `personality_v1` is a one-line change in `assessment_session_state`
  — also deferred so this pass stays focused on the scoring +
  recruiter side.
- **No validity-flag wiring** (`infrequencyFlag` / `inconsistencyFlag`).
  The TS engine includes them; the compute RPC doesn't call them
  because there are no bogus low-base-rate items in the current bank.
  Add those items + the RPC checks together later.
- **No norms-validation pipeline.** When H-2 closes, the operator
  inserts a new `personality_norms` row with `population_key=
  'nordic_v1'` + `validity_status='validated'`, the compute RPC's
  query updates to read it, and every score+match row regenerates
  with the proper provenance. The seam is built.

---

## Status

**Personality module is operational** end-to-end at the data and
algorithm level. The recruiter UI is ready to be slotted into the
existing candidate-detail page. Every value the module produces is
honestly labelled as `dev_stub` until the named expert reviews close
the relevant H-items.

H-1 through H-10 unchanged — by design.
