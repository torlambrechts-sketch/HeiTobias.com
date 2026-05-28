# SCIENCE-SPEC.md — I/O psychology & EU regulatory constraints

> The engineering contract for everything that touches **measurement, fit, fairness,
> and post-hire decision support**. The system is the engine; the science is pluggable.
> Before any live deployment with real candidates: credentialed I/O psychologist sign-off
> and legal review are required.
>
> This file is referenced from `CLAUDE.md` and is authoritative for instrument selection,
> trait modelling, fairness practices, guidance refusal categories, and the AI Act / GDPR
> obligations the architecture must structurally honour. Conflicts between this file and
> implementation are bugs against the implementation, not the spec.

---

## 1. Predictor validity (Sackett, Zhang, Berry, Lievens 2022)

The most recent meta-analysis of selection methods. Practical implications encoded
in the architecture:

| Predictor                  | Operational validity ρ      | Architectural treatment                                                                   |
|----------------------------|-----------------------------|-------------------------------------------------------------------------------------------|
| Structured interviews      | ~.42 (top predictor)        | Captured as `growth_conversations` + `hiring_decisions.rationale` (text), not scored.    |
| Work samples / job tests   | ~.33                        | Modelled as `assessment_instruments.type='composite'` once licensed.                      |
| General mental ability     | ~.23–.31 (not dominant)     | Modelled as `assessment_instruments.type='cognitive'` once licensed; not a single score. |
| Personality (broad Big 5)  | ~.10–.22 per facet, banded  | `roles_catalog.definition_json.trait_targets[]` with min/max bands (already enforced).    |
| Integrity (HEXACO H factor)| ~.20–.30                    | HEXACO-H is **the only allowed integrity surface**; never a "general integrity score".    |

**Key implication for the product:** the best composites explain ~65–75% of performance
variance. The fit number is therefore a **range with uncertainty**, never a verdict, never
the closing input to a decision (see §5).

---

## 2. Trait specification — bands, not maxima

Personality traits operate as **inverted-U** with the optimum context-dependent.

- A role profile **MUST** carry trait targets as `{trait, band:{min,max}, direction, justification}`.
- "More is better" is forbidden for any Big Five facet. Conscientiousness and Emotional
  Stability in particular should be encoded as bands.
- The trait-range control in the UI must render the **band**, not a threshold.

Already enforced structurally via the `chk_role_definition_shape` check on
`roles_catalog.definition_json` requiring `trait_targets[].band.{min,max}`.

---

## 3. Allowed and forbidden measurement instruments

The catalogue of `assessment_instruments` is the single point at which content arrives in
the system. The structural rule:

### 3.1 Allow-list (open-domain or public-domain, validated)

- **IPIP-NEO** (and IPIP-NEO-120 short form) — Big Five facet model.
- **BFI-2** — Big Five inventory (Soto & John 2017).
- **HEXACO-PI-R** — six-factor model; required for any Honesty-Humility / integrity surface.
- **O\*NET-derived work-activity instruments** — used as role-side anchoring, not person-scoring.

### 3.2 Deny-list (refused at the DB layer)

These instruments either **lack predictive validity**, have **commercial restrictions**
that block lawful redeployment, or both. They MUST NOT be ingested even in DEV STUB form:

- **MBTI** (Myers-Briggs)
- **DISC** (and any "DISC-derived" rebadging)
- **Learning styles** ("VARK", "Kolb learning styles", etc.)
- **Belbin Team Roles** (as a scored instrument; the role taxonomy is fine as a discussion frame)

Structural enforcement: a CHECK constraint on `assessment_instruments` refuses any row whose
`key`, `name`, or `vendor` matches the deny patterns above.

### 3.3 Nordic norms

US norms systematically misclassify Nordic respondents (particularly on Extraversion).
Once content is real (not stub):

- Country-level norm tables required, **n ≥ 3,000 per country**, drawn under purpose-
  appropriate consent.
- Norm provenance recorded on the score row (already supported by `assessment_scores.
  validity_flags_json`).

---

## 4. The role profile (full structural shape)

A role profile, as stored in `roles_catalog.definition_json`, MUST contain:

1. **Identity & governance** — `title`, `family`, `version`, `signed_off_by`, `authored_by_json`.
2. **Task / work-activity layer** — list of activities, anchored to O\*NET task codes where
   possible. (Today carried inside `definition_json` as an array; full O\*NET integration
   is a later content-layer step.)
3. **Weighted competencies** — `competencies[]` with `{key, weight}`, weights summing to 1.0.
4. **Trait target bands** — `trait_targets[]` with `{trait, band:{min,max}, direction, justification}`.
5. **Context factors** — `context_factors` covering autonomy, pace, collaboration intensity,
   complexity. Carried as `definition_json.context_factors`; null until tuned.
6. **Success criteria** — behavioural anchors, time-bounded, multi-dimensional. Carried as
   `definition_json.success_criteria`.
7. **Evolution vector** — how the role is expected to drift over the next 6-12 months.
   `roles_catalog.definition_json.evolution_vector` (Phase 3 activates the field).
8. **Validation metadata** — SME records, inter-rater agreement, adverse-impact log refs.
   Carried as `definition_json.validation_json`; required for `validity_status='validated'`.

---

## 5. Decision architecture — fit informs, never decides

**GDPR Art. 22** prohibits decisions based solely on automated processing where they
significantly affect an individual.

**EU AI Act Art. 14** requires effective human oversight of high-risk AI systems.

Recruitment + post-hire performance/promotion/termination are high-risk under Annex III.

Therefore:

- A fit score MUST NEVER be the sole signal closing a hiring, promotion, PIP, or
  termination decision. Already enforced via:
  - `hiring_decisions` row required before `placement_execute` will transfer (Phase 1).
  - `rationale` NOT NULL on `hiring_decisions` (free text — the human's reasoning).
  - `overrode_recommendation boolean` captured per decision.
- The same rule extends to **ongoing** decisions: promotions, PIPs, RIFs. A new
  `lifecycle_decisions` table is added in this milestone to record human decisions
  on post-hire actions, gated by `ongoing_management` consent, with the same rationale
  + override fields.

---

## 6. Guidance refusal — categories the composer MUST refuse

The guidance composer is RAG over the frameworks library + structured profile data.
Outside that scope, it MUST refuse with a structured explanation rather than free-generate.

### 6.1 Refused categories

- **Medical** — anything seeking a diagnosis, prognosis, accommodation determination, or
  treatment suggestion. Direct the manager to occupational health.
- **Legal** — anything seeking dismissal grounds, contract interpretation, regulatory
  defence. Direct to legal counsel.
- **Dismissal / termination scripting** — performance-improvement-plan content with
  termination as an implied outcome; severance recommendations. Capture the situation in
  `growth_conversations`; require legal + HR sign-off out-of-band.
- **Salary / compensation** — pay-band recommendations, raise sizing. Direct to comp
  team. The frameworks library carries no salary data.

### 6.2 Structural enforcement

- `guidance_refusal_kind` enum: `medical | legal | dismissal | compensation | out_of_scope`.
- `guidance_compose` short-circuits when the inferred category is on the refusal list and
  writes a row to `guidance_items` with `output_json.refused = true`, `output_json.refusal_kind`,
  and a recommended direction (e.g. "occupational health"). The row STILL carries
  `framework_ids` citing the refusal policy itself, so the audit trail remains grounded.

### 6.3 RAG hygiene (when wired to an LLM)

- Temperature ≤ 0.3.
- Retrieval window confined to: frameworks library + the named person's profile + the
  named person's role + the requesting manager's open guidance/growth conversations.
- No open-web retrieval, no other employees' data, no organisation-wide gossip.
- Every input + the retrieved framework_ids logged on `guidance_items.inputs_json`.
- Output is never "freeform advice about a named person from priors" — it's a recombination
  of cited frameworks + the structured data above.

---

## 7. Fairness & compliance practices

### 7.1 Adverse-impact monitoring

- **Four-fifths rule** (EEOC Uniform Guidelines §4D) as inspection trigger, not as a pass/fail.
- Implementation: a `fairness_audits` table accumulates aggregate metrics per
  (role, instrument, decision-stage). Future Phase 4 work computes ratios + differential
  prediction. For now we record the inputs (decision outcomes by group) so the data exists
  when the analysis ships.

### 7.2 AI Act Article 10(5)

- "Demographic-blind" violates Art 10(5) — bias monitoring requires sensitive-attribute data,
  collected under purpose-appropriate consent.
- Sensitive attributes (where collected): held in a separate, purpose-limited table with
  its own consent purpose (`fairness_monitoring`). NOT joined to user-facing surfaces.
  This milestone DEFINES the purpose value and the table; populating it requires the
  separate consent flow (out of scope here).

### 7.3 Measurement invariance

- Required across language versions before a localised instrument can be marked
  `validity_status='validated'`. Implementation: `assessment_instruments.body_json.
  measurement_invariance_json` with per-language fit statistics. Until populated for a
  given language, the localisation runs as `dev_stub`.

---

## 8. Timeline & deferrals

- **Original high-risk recruitment AI obligations:** 2 August 2026.
- **May 2026 deferral** extends to **2 December 2027** for standalone systems.
- **Engineering posture:** build to the original requirements; treat the extension as
  schedule relief, not a permission slip. This file's discipline is enforced today.

---

## 9. What this milestone implements

Concrete structural changes shipped alongside this document:

1. `assessment_instruments` deny-list CHECK refusing MBTI, DISC, learning-styles, Belbin.
2. `lifecycle_decisions` table — human-decided post-hire actions (promotion / PIP / etc.)
   with rationale + override fields, gated by `ongoing_management` consent.
3. `guidance_compose` extended with refusal categories + the `guidance_refusal_kind` enum;
   refused requests still produce an audit row.
4. `consent_purpose` enum extended with `fairness_monitoring` for the future
   sensitive-attribute table.
5. Tests verifying: deny-list refuses MBTI/DISC, refusal categories produce refusal rows
   not freeform output, lifecycle_decisions cannot be inserted without rationale.

---

*See `CLAUDE.md` for engineering rules, `PHASE0-SPEC.md` for the data substrate,
`DESIGN.md` for the UI system. Conflicts with this file are bugs against the
implementation, not the spec.*
