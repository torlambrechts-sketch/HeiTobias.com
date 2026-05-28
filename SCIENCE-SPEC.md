# SCIENCE-SPEC.md — Research-Grounded Constraints (HeiTobias)

> **Status: authoritative.** This document encodes the I/O-psychology and EU-regulatory
> constraints derived from two research reports (Layer 3 Intelligence & Science blueprint;
> Role Profile scientific reference). Every phase references this. Where this conflicts with
> a convenient implementation, this wins. Where it requires a judgment the team isn't yet
> qualified to make, the rule is: build the seam, label the stub, flag for the I/O
> psychologist / legal advisor — never fabricate a number or a verdict.
>
> **Two non-negotiable dependencies this document assumes:** a credentialed I/O psychologist
> and a legal/EU-AI-Act advisor. Nothing in here ships to live decisions about real people
> without them.

---

## 1. The evidence base has shifted — design to it

- **Sackett, Zhang, Berry & Lievens (2022, *JAP* 107(11), 2040–2068)** substantially revised the
  Schmidt & Hunter (1998) validity hierarchy. Revised operational validities (ρ): **structured
  interview ≈ .42**, job-knowledge test ≈ .40, empirically-keyed biodata ≈ .38, work sample ≈ .33,
  **GMA ≈ .31 (≈ .23 in 21st-century studies)**, integrity ≈ .31, contextualized conscientiousness
  ≈ .25, unstructured interview ≈ .19, years of experience ≈ .07.
- **Implication for the predictor stack:** structured interview is now the top single predictor;
  GMA is one weighted, complexity-calibrated component, NOT the default-dominant one.
  **Contextualized** personality (measured "at work") outperforms decontextualized.
- **GMA's validity point estimate is an ACTIVE, UNRESOLVED debate** (Sackett vs. Oh/Le/Bobko/Salgado).
  Honest UI/marketing posture: present as a range (≈ .31–.45 depending on assumptions), never a
  single confident number. Use lower-bound (80% CV) values for risk-averse decisions.
- **Even best composites reach R ≈ .50–.60** → ~65–75% of performance variance is unexplained.
  Never market "predict performance with X% accuracy." Communicate uncertainty honestly.

## 2. Trait targets are RANGES, not maxima (curvilinearity) — load-bearing

- **Le et al. (2011, *JAP*); Carter et al. (2014); Pierce & Aguinis (2013) TMGT effect; Grant (2013)
  ambivert advantage.** Conscientiousness, Emotional Stability, and (in sales) Extraversion relate to
  performance via **inverted-U** curves; optima are moderated by job complexity.
- **Rule:** every personality trait/facet target on a Role Profile is encoded as a **band**
  (`centre`, `lower`, `upper`, `direction`), with `direction ∈ {optimum, minimum_threshold,
  maximum_threshold, linear}`. Default for Conscientiousness & Emotional Stability = `optimum`
  (band), band centre rising with complexity. "More is better" scoring is a mis-specification —
  architecturally disallow a trait target that is a single point maximum unless `direction` is
  explicitly a justified threshold.
- Trait ranges are **also a fairness intervention**: wider, evidence-based acceptance bands produce
  less differential selection than point cut-offs. Outside-band ⇒ a structured-interview probe
  trigger, NEVER an automatic screen-out.

## 3. Context determines which trait targets are valid (Trait Activation Theory)

- **Tett & Burnett (2003); Tett et al. (2021); DIAMONDS (Rauthmann 2014); O*NET Work Context.**
  Traits predict behaviour only in trait-relevant situations. Without context encoding, trait
  targets are mis-specified.
- **Rule:** Role Profile MUST carry context factors (autonomy, ambiguity tolerance, pace/urgency,
  collaboration intensity, stakeholder load, cognitive complexity, adversity, psychological-safety
  dependence). The platform enforces **coherence checks**: e.g. high pace + high ambiguity ⇒
  Conscientiousness band centre should be lower; high stakeholder load ⇒ Extraversion band should not
  be low-only without justification.

## 4. Instruments: open-domain, facet-level, Nordic-normed

- **Use public-domain item pools:** IPIP-NEO (Goldberg) for the Big Five (facet-level, 120/300), or
  BFI-2 (Soto & John 2017) for parsimony; layer in **HEXACO-PI-R Honesty-Humility** for integrity-
  sensitive roles (strongest personality predictor of CWB; Oh et al. 2011). Public domain ⇒ you can
  publish items, keys, reliabilities, norms — directly satisfying EU AI Act Art. 10/11/13.
- **Cognitive:** IRT/CAT abstract-reasoning (matrix) bank, in-house, Nordic-normed; CAT roughly halves
  test length at equal precision (Embretson & Reise 2000). Calibrate the cognitive *demand band* to
  documented role complexity (O*NET Job Zone analogue), not "max."
- **Faking:** social-desirability inflation is real (Birkeland 2006, d ≈ .45 for C in selection).
  Mitigate with forced-choice variants in high-stakes hiring, warning instructions, and verification
  against structured-interview behavioural evidence. **Report uncertainty intervals on every score.**
- **EXPLICITLY EXCLUDED — never implement as measurement:** MBTI, DISC, Insights/"colours", learning
  styles, Belbin team roles, 9-box as an auto-rated potential tool. (Poor reliability/validity:
  Pittenger 2005; Pashler 2008; Furnham 1993; Church & Rotolo 2013.) Belbin/9-box may appear ONLY as
  labelled discussion aids, never as scored instruments.

## 5. The Role Profile is the measuring stick — full required spec

A defensible Role Profile combines task-based + worker-oriented (KSAO) + context descriptors, is
versioned/attributable, and produces EU-AI-Act documentation. Required components (see PHASE0-SPEC
§2.7 for the field model):
- **Identity & governance** — version, status (draft/under_review/signed_off/archived), attributable
  sign-off, effective dates, validation_status, validation_evidence_refs. (AI Act Art. 11/12/26.)
- **Task / work-activity layer** — tasks with criticality+frequency, outcomes, tools; content-validity
  anchor (O*NET GWA/DWA; Brannick 2007).
- **Weighted competencies** — criterion-side first (Bartram 2005 "Great Eight" / SHL UCF / Korn Ferry
  KFLA mappings); weights 0–1 summing to 1 across the critical set; criticality band; BARS anchors;
  derivation method (SME_Delphi / CIT / criterion / hybrid). **Define the criterion (competencies)
  first, then map predictors (traits/ability) to it — never the reverse.**
- **Trait target bands** — per §2 above; facet-level where evidence supports; each with weight,
  direction, and a justification + evidence_refs.
- **Cognitive demand** — complexity level (1–5) + justification; target band; use_as
  (threshold/banded/continuous, banded preferred); adverse-impact monitoring hook.
- **Context factors** — per §3.
- **Values & motivation** — Schwartz 10 values; SDT autonomy/competence/relatedness needs-supplies.
- **Success criteria** — operationalized, behaviour-anchored, time-bounded (90-day/6-mo/annual),
  multi-dimensional (task / contextual-OCB / adaptive / leadership / CWB-avoidance); Campbell 1990;
  Borman & Motowidlo 1997; Pulakos 2000 adaptive; Locke & Latham specificity.
- **Evolution vector** — **labelled a FORECAST, not a measurement**, in data and UI; sourced (named
  SMEs + Lightcast/ESCO/WEF), confidence-rated, forced re-review date.
- **Team-gap context** — computed from members' OWN profiles (complementary + supplementary fit);
  **peer-rating of individuals' personality is blocked at the schema level** (see §7).
- **Validation & defensibility metadata** — validation method, SME/Delphi records, inter-rater
  agreement (ICC/Kendall's W), adverse-impact log (four-fifths), differential-prediction log,
  review dates, AI Act tech-doc ref, DPIA ref, framing default (= developmental).

## 6. Fit is a TRAJECTORY; re-measurement is developmental by default

- Fit is dynamic (Caldwell 2004; Vleugels 2019). Re-measure on a **6–12 month cadence**, consent-gated.
- **Four-quadrant model (person-drift × role-drift):** stable fit / growth gap / emerging misfit /
  aligned-evolution(flight-risk-if-not-promoted). It is a **practitioner synthesis, not a validated
  instrument** — label it as such; never present as measurement.
- **Developmental framing is a MEASUREMENT-VALIDITY requirement, not soft language** (Kuvaas 2011;
  DeNisi & Murphy 2017): evaluative framing suppresses honest signal and produces gaming. Default all
  re-measurement to developmental; evaluative use is opt-in, named, consented. Beware self-fulfilling-
  prophecy labelling (Rosenthal & Jacobson 1968) — "emerging misfit" must never be surfaced to a
  manager without developmental context.
- **Personality changes through adulthood** (Roberts et al. 2006) — this *justifies* re-measurement
  and *requires* the developmental framing.
- **Engagement ≠ performance** (Harter 2002 ρ ≈ .20–.30, causal direction contested). Treat pulse
  signals as **flight-risk / well-being** indicators, NOT performance proxies. Stay on the
  "high-performance" axis, explicitly out of the engagement-platform category.

## 7. Team definition — Delphi independence + the surveillance guardrail

- Group role definition uses **independent rating before discussion** (Delphi: Linstone & Turoff 1975;
  NGT) to suppress groupthink/anchoring — not open round-tables.
- **NON-NEGOTIABLE:** peers validate **role requirements**, never each other's personalities. Peer
  ratings of individuals' personality are psychometrically weak (Connelly & Ones 2010) AND a high-risk
  profiling pattern (GDPR Art. 22; EU AI Act Annex III §4). **Team composition is built ONLY from each
  member's own validated self-administered profile, aggregated against the role.** Block peer-personality
  rating at the schema level.
- Team-gap seeks **complementary** fit (fills gaps) as a deliberate counterweight to the
  Attraction-Selection-Attrition monoculture risk (Schneider 1987); culture-fit uses **supplementary**
  fit. Support both; do not let naive "culture fit" suppress diversity.

## 8. Manager guidance: grounded, evidence-tiered, never freeform

- **Frameworks Library = a graph of evidence objects.** Each "manager play" links to: primary
  citations, evidence-strength tier (S/A/B/C, GRADE-adapted), contraindications, the Role/Person
  signals that trigger it, versioned template text, and a re-review/expiry date.
- Seed it with validated frameworks ONLY: Goal-setting (Locke & Latham); **Feedback Intervention Theory
  (Kluger & DeNisi 1996 — 38% of feedback interventions DECREASED performance; guidance must be
  task-focused, behaviour-specific, goal-paired, never ego/self-focused)**; Job Characteristics Model;
  Self-Determination Theory (autonomy/competence/relatedness); Psychological Safety (Edmondson 1999);
  Schwartz values; SHL UCF/Great Eight; O*NET/ESCO. Exclude the §4 debunked list.
- **RAG is the only defensible generation pattern** (AI Act Art. 14): retrieval corpus = Frameworks
  Library + Role Profile + Person Profile ONLY, no open-web retrieval at inference. Every guidance
  sentence backed by a retrieved, cited chunk; below confidence threshold ⇒ refuse + route to human.
  **Refusal taxonomy:** medical, legal, dismissal, salary, protected-characteristic inference ⇒ decline
  with explanation. Temperature ≤ 0.3; log every prompt/retrieval-set/output (AI Act Art. 12).
  Human-in-the-loop gate for any consequential wording (hire/no-hire, PIP, promotion).
- EU-resident model hosting only; document base-model training data (AI Act Art. 50–55); no personal
  data leaves the EU for inference (Schrems II). Red-team each release (jailbreak, bias, demographic-
  inference probes); publish the eval set.

## 9. Fit informs, never decides — architectural rule

- **GDPR Art. 22 + EU AI Act Art. 14:** a fit score can NEVER be the sole signal closing a hiring,
  promotion, PIP, or termination decision. Human-in-the-loop is **architecturally enforced** — a
  `decision_artefact` (human, attributable, logged, overridable) is required before any consequential
  action. No auto-reject / auto-rank-to-action / auto-PIP. Log every decision and override.
- Prefer interpretable models (regularized regression / GBM + SHAP local explanations) over opaque
  nets — required for "meaningful information about the logic" (GDPR Art. 22) and AI Act transparency.
  Maintain a **model card** per model (intended use, data lineage, weights, fairness metrics, version,
  owner).

## 10. Bias & fairness — mandatory, demographic-aware, threshold-owned by experts

- **Methods:** four-fifths rule (EEOC Uniform Guidelines §4D) as inspection trigger + statistical
  confirmatory tests; **differential prediction** (Cleary 1968; Aguinis 2010 — test slope/intercept by
  group; note Berry 2015: cognitive tests often show no differential validity but intercept differences
  that *overpredict* minority performance); **measurement invariance / DIF** (configural→metric→scalar)
  per language version before launch; **Pareto-optimal validity–diversity weighting** (De Corte 2007;
  Song 2017, 2023) exposed as a curve the customer chooses a point on.
- **Demographic-blind is NOT compliant** — AI Act Art. 10(5) permits special-category processing FOR
  bias detection; bias monitoring REQUIRES demographic data. In the Nordics, collect sensitive
  attributes **voluntarily, separate-purpose, separately-stored, used only for fairness analysis, never
  in prediction**; pair with documented-uncertainty proxy auditing.
- **The computation is engineering; the thresholds and "is this acceptable?" verdicts are JUDGMENTS the
  I/O + legal owners set and sign off.** The system computes and surfaces metrics; it never self-asserts
  "unbiased" or "compliant." Immutable bias-audit log (AI Act Art. 12); regulator-ready report per role
  per quarter; publish a public fairness report per major release (cf. Pymetrics/Wilson 2021).
- **Cautionary precedent:** *Mobley v. Workday* (N.D. Cal., collective action certified May 16 2025 on
  ADEA grounds; notice plan approved Dec 2 2025) — a vendor may itself be treated as an "employment
  agency." Audit rigor is existential, not optional.

## 11. Nordic norms are a compliance asset AND the category wedge

- Nordic work culture is empirically distinct (Hofstede: very low power distance, world's most
  consensus/"feminine" cultures; Jante-law / *lagom* modesty depresses self-promotion in self-report).
  **US-normed personality scores systematically misclassify Nordic respondents toward the low end**
  (esp. Extraversion, C-facet "achievement striving").
- **Build Nordic per-country norms** (target ≥ 3,000 per country NO/SE/DK; ≥ 1,500 FI/IS phase 2),
  re-normed percentiles per country+language, with multi-group CFA/IRT DIF at configural/metric/scalar
  levels, published technical manual. Re-derive trait target bands per role family per Nordic context.
  This satisfies AI Act Art. 10 data-representativeness and defeats "US tools disadvantage Nordic group
  X." Incumbents (Hogan/SHL/PI) carry weak Nordic norms; Alva is closest but leans on a US comparison
  sample — the gap is the wedge.

## 12. EU AI Act timeline — build to the original, treat deferral as margin

- Recruitment/evaluation/promotion/termination/performance-monitoring AI is **high-risk under Annex
  III §4.** Provider+deployer obligations: risk-management system (Art. 9), data governance (Art. 10),
  technical documentation (Art. 11/Annex IV), event logging (Art. 12), transparency (Art. 13), human
  oversight (Art. 14), accuracy/robustness/security (Art. 15); deployers must inform workers + worker
  reps (Art. 26(7)); FRIA for some deployments (Art. 27). Fines up to €35M / 7% global turnover.
- **Timeline:** Annex III high-risk obligations were originally **2 August 2026**. The **May 2026
  *Digital Omnibus on AI* (COM(2025) 836)** provisional agreement (announced 7 May 2026, confirmed by
  Member-State representatives 13 May 2026) defers them to **2 December 2027** for standalone systems,
  pending formal adoption. **Build to the original requirements; treat the extension as schedule
  relief, not a permission slip.** Keep all policy logic in configurable rules, not hard-coded, because
  the landscape is still moving (EDPB consultations open).
- GDPR Art. 22 (no solely-automated significant decisions) + Art. 35 (DPIA for systematic profiling)
  layer on top. Nordic DPAs (Datatilsynet NO, IMY SE, Datatilsynet DK) have aligned guidance with EDPB
  Opinion 28/2024.

---

## Staged scientific roadmap (maps onto the build phases)

- **Stage 0 (pre-launch, ~Phase 0–1 foundation):** license nothing proprietary — IPIP + HEXACO-PI-R
  open items + in-house IRT-CAT matrix bank; lock the Frameworks Library schema (evidence graph w/
  citations+tier+version) and seed ~40 validated plays; stand up the RAG pipeline (EU-hosted, refusal
  taxonomy, full logging); begin Nordic norm collection (≥1,500/country by month 6 via partner agencies).
- **Stage 1 (recruitment-agency launch, ~Phase 1):** structured-interview kit (the top Sackett-2022
  predictor) + contextualized Big Five + CAT cognitive + H-H integrity; live adverse-impact &
  differential-prediction dashboards per role; publish v1 technical manual + bias audit; pursue EFPA
  review. **Advance threshold:** ≥5 placements/agency/month at ≥0.30 observed local validity vs 90-day
  performance on the first 200 placements.
- **Stage 2 (employer / lifecycle, ~Phase 2–3):** re-evaluation, pulse, four-quadrant fit,
  manager-guidance RAG, Pareto weighting tool; complete Nordic norm set (3,000+/country) + publish;
  begin DACH/Benelux norms. **Advance threshold:** scalar measurement invariance across Nordic
  languages + ≥50 employer customers + AI Act conformity assessment passed & registered.
- **Stage 3 (EU scale, ~Phase 4):** domain-specific predictive models per vertical with outcome
  feedback loops; open Frameworks Library to customer-authored tier-C plays under peer review.
  **Instrument-set expansion threshold:** a new instrument enters only on incremental validity Δρ ≥ .05
  over the current composite in a **pre-registered Nordic validation study.**

---

## The hard caveats (carry into every phase)

- Sackett et al. (2022) is itself contested (Bobko 2024 rebuttal; Sackett 2024 reply) — best current
  estimate, not final truth.
- Most personality validities are modest (.10–.25); resist accuracy marketing.
- Trait ranges are an interpretive layer, not a reject-outside-range licence.
- "Potential" prediction beyond past performance is empirically weak (Silzer & Church 2009); 9-box/HiPo
  survive on faith.
- The evolution vector is the most speculative element — structured forecast, never a measurement claim.
- Nordic culture is not monolithic (DK ≠ SE on power distance/uncertainty; FI/IS different language
  groups) — per-country norms matter.
- Defensibility is only as strong as the documentation produced — the Role Profile must *generate* the
  AI Act Annex IV tech doc, the GDPR Art. 35 DPIA, and a Uniform-Guidelines-style validity dossier on
  demand. Defensibility is a feature, not a footnote.
