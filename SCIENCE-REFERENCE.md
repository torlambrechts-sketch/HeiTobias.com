# HeiTobias — Scientific Reference

> **What this is.** The authoritative scientific reference for the HeiTobias platform.
> Compiled from deep research across the published literature relevant to H-1 through
> H-10. The Claude Code build instructions read from this file. The eventual engaged
> I/O psychologist validates the values; this document establishes the methodology and
> citations.
>
> **Authority.** Where this document and an engaged I/O psychologist's judgment differ,
> the expert's judgment wins and this document is revised. Where this document and
> SCIENCE-SPEC.md differ, SCIENCE-SPEC wins on architectural commitments.
>
> **Status.** All scientific *values* (trait bands, fairness thresholds, norm percentiles,
> validity coefficients) remain `_dev_stub` until expert sign-off. This document
> specifies the *evidence base* and *methodology*, not the values themselves.

---

## 1. The Predictor Validity Hierarchy (Sackett et al. 2022 + 2024-2025 debate)

**Primary source:** Sackett, P. R., Zhang, C., Berry, C. M., & Lievens, F. (2022).
Revisiting meta-analytic estimates of validity in personnel selection: Addressing
systematic overcorrection for restriction of range. *Journal of Applied Psychology,
107*(11), 2040-2068. doi:10.1037/apl0000994

**Revised operational validities (Sackett et al. 2022):**

| Predictor | ρ (operational validity) | SD_ρ | 80% credibility interval |
|---|---|---|---|
| Structured interview | **.42** | .12 | .18 – .66 |
| Empirically-keyed biodata | **.38** | — | .26+ |
| Job knowledge | ~.40 | — | — |
| Cognitive ability (GMA) | **.31** | — | wide |
| Work sample | **.33** | — | — |
| Integrity tests | **.31** | ~.20 | — |
| Conscientiousness (decontextualized) | **.19** | .15 | — |
| Conscientiousness (contextualized) | **.22** | .00 | — |
| Assessment center | ~.29 | — | — |
| SJT | ~.26 | — | — |
| Unstructured interview | ~.19 | .16 | — |

**Active debate — the GMA validity question.**
- Bobko, Roth, Le, Oh & Salgado (2024, 2025, *International Journal of Selection and
  Assessment*) — "considered estimation" yields GMA closer to .45
- Sackett, Berry, Lievens & Zhang (2025, *IJSA*, doi:10.1111/ijsa.70016) — defended
  "conservative estimation" at .31
- Cucina (2025, *Intelligence* 109:101892) — additional critique
- Griebie et al. (2022, SIOP poster) — 21st-century cognitive validity r=.23 across
  113 studies, *lower* than Sackett

**Defensible range for GMA operational validity: .31 (lower bound, Sackett 2022) to
.45 (Bobko 2024 considered) to .51 (Schmidt & Hunter 1998 historical).**

**Build implication:** the platform must express validity as a *range* with explicit
caveats. Never a single point estimate. Customer-facing copy must reflect this. Berry,
Lievens, Sackett & Zhang (2024, *JAP*) further showed that with revised values,
excluding GMA produces little to no validity loss but substantial adverse-impact
reduction — informing H-5 Pareto work.

---

## 2. Public-Domain Personality Instruments

### IPIP-NEO
- Goldberg (1999); Johnson (2014, *JRP* 51:78-89)
- Available: 300-item, 120-item, 60-item versions
- Big Five domains × 30 facets
- α typically .79-.86 domain level
- Public domain — full transparency for AI Act Art. 13

### BFI-2 (Big Five Inventory-2)
- **Primary:** Soto, C. J., & John, O. P. (2017). The next Big Five Inventory (BFI-2):
  Developing and assessing a hierarchical model with 15 facets to enhance bandwidth,
  fidelity, and predictive power. *Journal of Personality and Social Psychology,
  113*(1), 117-143.
- 60 items, 5 domains × 3 facets (15 facets total)
- Controls for acquiescent responding via positively + negatively keyed items
- Short forms: BFI-2-S (30 items), BFI-2-XS (15 items) — Soto & John (2017, *JRP*
  68:69-81)

### HEXACO-PI-R
- Lee & Ashton (2018) — `hexaco.org`
- 60/100/200-item versions
- 6 domains × 4 facets each
- Domain α=.88-.92 in adequate samples
- Honesty-Humility is the differentiating sixth factor

### Honesty-Humility as predictor of CWB
- Oh, I.-S., Lee, K., Ashton, M. C., & de Vries, R. E. (2011). Are dishonest extraverts
  more harmful than dishonest introverts? The interaction effects of Honesty-Humility
  and Extraversion in predicting workplace deviance. *J Personality Assessment*
- Honesty-Humility predicts CWB and OCB above the Big Five
- Operational validity for CWB substantial in applicant settings

**Build implication:** core personality battery must include a facet-level Big Five
instrument AND a Honesty-Humility module. Defensible choices: BFI-2 + HEXACO-PI-R
Honesty-Humility facet, OR full HEXACO-PI-R. The instrument-burden vs facet-coverage
tradeoff is an expert decision (worksheet H-1b).

---

## 3. Trait-Performance Curvilinearity (Inverted-U)

**Primary sources:**
- Le, H., Oh, I.-S., Robbins, S. B., Ilies, R., Holland, E., & Westrick, P. (2011).
  Too much of a good thing: Curvilinear relationships between personality traits and
  job performance. *Journal of Applied Psychology, 96*(1), 113-133.
- Pierce, J. R., & Aguinis, H. (2013). The too-much-of-a-good-thing effect in
  management. *Journal of Management, 39*(2), 313-338.
- Grant, A. M. (2013). Rethinking the extraverted sales ideal: The ambivert advantage.
  *Psychological Science, 24*(6), 1024-1030.

**Key findings:**
- Conscientiousness and Emotional Stability show inverted-U relations with task
  performance, OCB, and CWB
- Job complexity moderates the inflection point — higher complexity = higher inflection
- Grant 2013 N=340 outbound sales reps: **Extraversion 3.75-5.50 (on 1-7) → $154.77/hr
  revenue; extraverts $125.19; introverts $120.10. Ambivert advantage 23.6% over
  extraverts.**

**Build implication:** every trait target in the platform must be a *range with optimum*,
not a maximum. The schema enforces this via the `direction` field:
- `optimum` — band with centre, lower, upper (inverted-U default for C, ES)
- `minimum_threshold` — fit increases up to threshold then plateaus
- `maximum_threshold` — fit decreases above threshold
- `linear` — explicitly justified linear relation (rare; requires expert sign-off)

The band-fit math (H-1c) implements this with uncertainty propagation. Out-of-band is
a structured-interview probe trigger, never an automatic screen-out (SCIENCE-SPEC §2).

---

## 4. Trait Activation Theory

**Primary sources:**
- Tett, R. P., & Burnett, D. D. (2003). A personality trait-based interactionist model
  of job performance. *Journal of Applied Psychology, 88*(3), 500-517.
- Tett, R. P., Simonet, D. V., Walser, B., & Brown, C. (2021). Trait activation theory:
  Applications, developments, and implications for person-workplace fit. In *Handbook
  of Personality at Work* (Christiansen & Tett, eds.).

**The five situational moderator categories (at task, social, and organizational levels):**
1. **Demands** — situational cues that require trait expression
2. **Distractors** — cues that interfere with trait expression
3. **Constraints** — cues that suppress trait expression
4. **Releasers** — cues that permit/encourage trait expression
5. **Facilitators** — cues that enhance trait expression

**Build implication:** every role profile carries a Trait Activation vector (the nine
context factors in SCIENCE-SPEC §5). Trait targets are conditioned on this vector —
e.g., a high-ambiguity context shifts the Conscientiousness band centre.

---

## 5. Nordic Norms

### Hofstede dimensions (anchoring the cross-cultural argument)

| Country | PDI | IDV | MAS | UAI |
|---|---|---|---|---|
| Denmark | 18 | 74 | **16** | 23 |
| Sweden | 31 | 71 | **5** | 29 |
| Norway | 31 | 69 | **8** | 50 |
| Finland | 33 | 63 | 26 | 59 |
| Iceland | ~30 | ~60 | 10 | ~50 |

Sweden's MAS of 5 is the world minimum. Source: Hofstede (2001, *Culture's
Consequences*, 2nd ed.); Aðalsteinsson et al. (2011) for Iceland replication.

Caveat: Gerlach & Eriksson (2021, *Frontiers in Psychology* 12:662604) showed the
modern VSM 2013 has poor internal consistency; use original IBM-era scores for narrative
anchoring, not VSM 2013.

### The Jante/lagom hypothesis — direct evidence

Føllesdal, H., & Soto, C. J. (2022). The Norwegian adaptation of the Big Five
Inventory-2. *Frontiers in Psychology, 13*, 858920. Studies 1 (N=606) + 2 (N=409):
**17 of 60 BFI-2 items had the most extreme response (1 or 5) as the modal Norwegian
response.** Compassion facet hitting ceiling. Direct empirical evidence that Nordic
populations differ in response style from US samples.

Schmitt, D. P., Allik, J., McCrae, R. R., & Benet-Martínez, V. (2007). The geographic
distribution of Big Five personality traits. *Journal of Cross-Cultural Psychology,
38*(2), 173-212. N=17,837 across 56 nations — systematic regional differences,
warning that mean differences may reflect response styles rather than true trait
differences.

### Validated Nordic adaptations

| Instrument | Country | Citation | Sample | α |
|---|---|---|---|---|
| BFI-2 | Norwegian | Føllesdal & Soto (2022, *Front Psychol* 13:858920) | N=606+409 | .70-.82 |
| BFI-2 | Danish | Vedel, Wellnitz, Ludeke, Soto, John & Andersen (2021, *EJPA* 37:42-51) | N=2,030 | ~.74 |
| BFI-2 | Swedish | Zakrisson, Soto, Löfstrand & John (2025, *PTAD* 6:199-215) | N=2,751 | (full structure) |
| HEXACO-PI-R 200 | Norwegian | Sharifibastan et al. (2025, *Scand J Psychol*, doi:10.1111/sjop.70098) | N=460 | .88-.92 |

**Known gap: no published Finnish BFI-2 validation.** This is a real blocker for
pan-Nordic claims.

### Sample-size requirements

- AERA, APA & NCME (2014), *Standards*, Ch. 5: norm samples must be sufficient and
  representative; no specific N mandated
- Hogan, Davies & Hogan (2007, *JOOP*): N > 100 yields little gain within a single
  occupational sample, but norm relevance (job-family match) matters — sales vs.
  trucking norms differed by 7.3 T-score points
- Lenhard & Lenhard (2019, *PLoS ONE*): continuous (regression-based) norming yields
  stable percentile estimates with N≈150-250 per stratum vs. N≥500 for conventional

**Defensible floor:** N≥500 per country with stratification on age × gender ×
education × language. Continuous norming for facet-level percentiles in smaller
strata. Applicant vs. general-population samples maintained separately.

### Applicant vs. general-population differences

Birkeland, S. A., Manson, T. M., Kisamore, J. L., Brannick, M. T., & Smith, M. A.
(2006). A meta-analytic investigation of job applicant faking on personality measures.
*International Journal of Selection and Assessment, 14*(4), 317-335. 33 studies:
applicants > non-applicants on Conscientiousness (d=.45), Emotional Stability (d=.44),
Openness (d=.13), Extraversion (d=.11).

Salgado, J. F. (2016). A theoretical model of psychometric effects of faking on
assessment procedures. *IJSA, 24*(3), 209-228 — larger effect d=0.70.

**Build implication:** maintain two norm sets per country (applicant vs. general
working population); report percentiles against the appropriate reference.

### Reliability re-estimation

AERA/APA/NCME 2014 Standards 2.2 and 2.6 require reliability evidence in the population
of use. Føllesdal & Soto's Norwegian α=.70-.82 lower than US .81-.86. **Reliabilities
do not transfer; re-estimate α, ω, CAT SEs per language.**

---

## 6. Adverse Impact and Differential Prediction

### Four-fifths (80%) rule

EEOC Uniform Guidelines on Employee Selection Procedures, **29 CFR §1607.4(D)**: "A
selection rate for any race, sex, or ethnic group which is less than four-fifths (4/5)
(or eighty percent) of the rate for the group with the highest rate will generally be
regarded by the Federal enforcement agencies as evidence of adverse impact."

Adverse Impact Ratio = selection rate of focal group / selection rate of reference
group. AIR < 0.80 is a regulatory inspection trigger.

### Cleary differential prediction model

Cleary, T. A. (1968). Test bias: Prediction of grades of Negro and white students in
integrated colleges. *Journal of Educational Measurement, 5*(2), 115-124.

A test is unbiased if the same regression equation predicts criterion performance
equally well across groups. Slope differences = differential validity. Intercept
differences = differential prediction.

### Aguinis power critique

Aguinis, H., Culpepper, S. A., & Pierce, C. A. (2010). Revival of test bias research
in preemployment testing. *Journal of Applied Psychology, 95*(4), 648-680.

Monte Carlo with 3,185,000+ cells and ~15.9 billion samples showed: (a) statistical
power to detect slope differences is near-zero (often < .10) in realistic settings,
and (b) intercept-bias tests are inflated by predictor unreliability, range
restriction, and group-size imbalance.

### Berry 2015 — overprediction of minority performance

Berry, C. M. (2015). Differential validity and differential prediction of cognitive
ability tests. *Annual Review of Organizational Psychology and Organizational
Behavior, 2*, 435-463. Slope differences typically null. Intercept differences
typically show **overprediction of Black examinees' performance** — a colorblind
regression slightly *over*-predicts performance for minorities, not under-predicts.

The fairness issue is primarily adverse impact in selection ratio, NOT criterion-
related prediction bias. **Build implication:** the platform's bias reports must be
careful not to mislead — present adverse-impact (selection-ratio) findings as
distinct from differential-prediction findings, with clear interpretive guidance.

### Statistical vs practical significance

The Uniform Guidelines permit departures from 4/5 in small samples or where
statistical significance does not obtain. Standard supplementary tests: Fisher's
exact, two-proportion z, shortfall analysis.

Mattern & Patterson (2013, *JAP* 98:134-147, N>475,000): ΔR²_intercept .004-.032,
ΔR²_slope .001-.013 in college admissions — minimal but in the same direction.

---

## 7. Pareto-Optimal Validity-Diversity Tradeoff

**Primary sources:**
- De Corte, W., Lievens, F., & Sackett, P. R. (2007). Combining predictors to achieve
  optimal trade-offs between selection quality and adverse impact. *Journal of Applied
  Psychology, 92*(5), 1380-1393.
- Song, Q. C., Wee, S., & Newman, D. A. (2017). Diversity shrinkage: Cross-validating
  Pareto-optimal weights to enhance diversity via hiring practices. *Journal of
  Applied Psychology* (doi:10.1037/apl0000240).
- Song, Q. C., Tang, C., Newman, D. A., & Wee, S. (2023). Adverse impact reduction
  and job performance optimization via Pareto-optimal weighting: A shrinkage formula
  and regularization technique. *Journal of Applied Psychology, 108*(9), 1461-1485.

**The method:**
1. For a set of predictors with criterion-related validities and group differences,
   compute the full Pareto frontier of (expected validity, adverse impact ratio)
   tradeoffs.
2. Each point on the frontier represents an undominated weighting — no other weighting
   achieves both higher validity and lower adverse impact.
3. The deployer selects an operating point. This selection is a documented business
   decision, attributed to a named human (the customer's people-leadership executive).

**Shrinkage corrections:**
- Song et al. (2017) — Pareto solutions shrink on cross-validation
- Song et al. (2023) — ridge/LASSO regularization further reduces shrinkage

**Operational implementation:**
- **R package `ParetoR`** (Diversity-ParetoOptimal/ParetoR on GitHub) — open-source
- TROFSS (De Corte, 2006) — proprietary

### Berry, Lievens, Sackett & Zhang (2024, *JAP*)
"Insights from an updated personnel selection meta-analytic matrix." Rebuilds the
predictor matrix with Sackett 2022 values. Key finding: excluding GMA from the
selection composite often produces little to no validity loss but substantial
adverse-impact reduction. **This fundamentally reframes the Pareto curve.**

### Robustness — De Corte, Sackett & Lievens (2020, *ORM*)
Simulation across 3,888 cells × 24 selection systems. Pareto solutions stable but
sensitive to sample size and predictor intercorrelation estimates.

**Build implication:** the platform computes the Pareto frontier from the configured
predictor set + their validity estimates (with the .31-.45 GMA range as a parameter) +
their group-difference estimates. Surfaces the curve to the deployer. The selection
point requires explicit attribution (decision_artefact) and rationale. Never a
default-chosen point.

---

## 8. Measurement Invariance and DIF

### The Vandenberg-Lance invariance hierarchy

Vandenberg, R. J., & Lance, C. E. (2000). A review and synthesis of the measurement
invariance literature: Suggestions, practices, and recommendations for organizational
research. *Organizational Research Methods, 3*(1), 4-69.

1. **Configural** — same factor structure (baseline)
2. **Metric / weak** — factor loadings equal → loadings comparable
3. **Scalar / strong** — intercepts equal → latent means comparable
4. **Strict / residual** — error variances equal → observed means comparable
5. **Structural** — factor variances/covariances/means equal

### Fit-index cutoffs

| Source | Criterion | Cutoff |
|---|---|---|
| Cheung & Rensvold (2002, *SEM* 9:233-255) | ΔCFI | ≤ -.01 |
| Chen (2007, *SEM* 14:464-504) — metric | ΔCFI + ΔRMSEA + ΔSRMR | ≤ -.010 & ≥ .015 & ≥ .030 |
| Chen (2007) — scalar/strict | ΔCFI + ΔRMSEA + ΔSRMR | ≤ -.010 & ≥ .015 & ≥ .015 |
| Meade, Johnson & Braddy (2008, *JAP* 93:568-592) | ΔCFI (stricter) | ≤ -.002 |

Putnick & Bornstein (2016, *Developmental Review* 41:71-90) is the current best-
practice reporting standards reference.

### DIF detection methods

**IRT-based:**
- Lord's χ²
- Area indices
- Raju's DFIT
- IRT-LR

**Logistic-regression-based:**
- Swaminathan & Rogers (1990)

**Mantel-Haenszel** with ETS A/B/C classification (simplest).

### Sample-size requirements

- MGCFA invariance with 5-6 latent factors and 30-60 items: N≥200 per group minimum,
  N≥500 per group preferred for stable estimates and adequate partial-invariance power
- IRT-based DIF: N≥500 per focal group

References for power: Meade & Bauer (2007); Chen (2007).

**Build implication:** the platform supports the invariance pipeline as code — load
data, fit configural, fit metric, fit scalar, fit strict, report fit indices and
deltas. The verdict per level remains expert sign-off (`invariance_verdict_record`
schema).

---

## 9. EU AI Act and GDPR Compliance

### Regulation (EU) 2024/1689

Classification: **recruitment/HR AI is high-risk (Annex III, point 4(a)-(b))** —
recruitment/selection (CV screening, candidate evaluation, interview ranking) and
HR (promotion/termination/work allocation/performance monitoring).

### Key obligations

| Article | Obligation | Relevance |
|---|---|---|
| Art. 9 | Risk management system across lifecycle | Continuous risk register, mitigation plan |
| Art. 10 | Data governance — relevant, representative, complete training/validation/test data; bias detection mandatory | Norms representativeness, fairness audits |
| Art. 10(5) | Special-category data permitted strictly for bias detection with safeguards | Enables fairness monitoring |
| Art. 11 + Annex IV | Technical documentation | System description, design choices, datasets, performance, oversight, post-market monitoring |
| Art. 12 | Automatic logging of events | Audit log, retention ≥6 months (Art. 26(5)) |
| Art. 13 | Transparency to deployers; instructions for use | Documentation handoff |
| Art. 14 | Human oversight — must be effectively overseeable, intervenable, overridable | Decision_artefact architecture |
| Art. 15 | Accuracy, robustness, cybersecurity; declared performance metrics | Validity claims, monitoring |
| Art. 26 | Deployer obligations: use per instructions, oversight, monitoring, log retention, worker notification (Art. 26(7)) | Customer-side obligations |
| Art. 26(11) | Inform affected natural persons of high-risk AI use | Candidate transparency |
| Art. 27 | Fundamental Rights Impact Assessment (FRIA) for certain Annex III deployers | FRIA template required |
| Art. 50 | Transparency for limited-risk AI | 2 August 2026 |
| Art. 99 | Penalties up to €35M or 7% worldwide turnover (prohibited); €15M or 3% (high-risk infringements) | Material exposure |

### Timeline

**As of May 30, 2026:** Per Council of the EU press release dated **7 May 2026**
("Artificial Intelligence: Council and Parliament agree to simplify and streamline
rules"), the EU Council and Parliament reached **provisional political agreement on
the Digital Omnibus on AI**:
- **Stand-alone Annex III high-risk obligations deferred from 2 August 2026 to 2
  December 2027.**
- AI embedded in regulated products (Annex I) deferred to 2 August 2028.
- Art. 50 transparency obligations remain at 2 August 2026.
- Underlying obligations unchanged; only application date moves.
- A new Art. 5 prohibition on AI-generated non-consensual intimate imagery / CSAM was
  added.

Sources: White & Case, Hogan Lovells, Bird & Bird, Covington & Burling (InsidePrivacy),
Gibson Dunn — all dated 7 May 2026 or shortly thereafter. Status: provisional, subject
to formal adoption and OJ publication expected before 2 August 2026.

**Build to original requirements, treat the deferral as margin not relief.**

### GDPR

- **Art. 22** — Automated individual decision-making prohibited where it produces
  legal or similarly significant effects, with exceptions (contract necessity, explicit
  consent, EU/MS law) and required safeguards (right to human intervention, to express
  view, to contest).
- **Art. 35** — DPIA mandatory for systematic/extensive evaluation of personal
  aspects including profiling that produces legal/similarly significant effects
  (Art. 35(3)(a)) — squarely applicable to hiring AI.

**FRIA vs DPIA:** complementary, not duplicative. DPIA centers on data-processing
risks to data subjects; FRIA centers on fundamental-rights impact of the AI system in
deployment context.

### Mobley v. Workday (US precedent)

*Mobley v. Workday, Inc.* (N.D. Cal. 3:23-cv-00770-RFL) — the leading AI-vendor
liability case.
- **July 12, 2024:** Workday plausibly acts as employer's "agent" under Title VII,
  ADEA, ADA. Court: "Drawing an artificial distinction between software decisionmakers
  and human decisionmakers would potentially gut anti-discrimination laws."
- **May 16, 2025:** preliminary ADEA collective certification granted. Workday
  represented 1.1 billion applications were rejected through its tools; the collective
  could include hundreds of millions of applicants aged 40+.
- **July 7, 2025:** collective expanded to include HiredScore AI features.
- **December 2, 2025:** notice plan approved.
- **March 6, 2026:** court rejected Workday's argument that ADEA disparate-impact
  protections do not extend to applicants.

**Build implication:** per-applicant audit logs, contemporaneous bias monitoring,
documented human-oversight involvement, transparent decision rationales — these are
litigation-defense assets, not just compliance overhead. The platform's existing
decision_artefact architecture already supports this; production hardening operationalizes
the retention.

---

## 10. Job Analysis and Competency Frameworks

### Bartram Great Eight

Bartram, D. (2005). The Great Eight competencies: A criterion-centric approach to
validation. *Journal of Applied Psychology, 90*(6), 1185-1203. Meta-analysis of 29
SHL validation studies, N=4,861.

**The Great Eight:** Leading & Deciding, Supporting & Cooperating, Interacting &
Presenting, Analysing & Interpreting, Creating & Conceptualising, Organising &
Executing, Adapting & Coping, Enterprising & Performing. SHL Universal Competency
Framework spans 112 sub-competencies.

Operational validities: .20-.44 single-criterion, .53 aggregated.

### O*NET

U.S. Department of Labor O*NET database (onetonline.org):
- 41 Generalized Work Activities (GWAs)
- ~2,000 Detailed Work Activities (DWAs)
- ~19,000 Tasks
- Keyed to SOC occupations

Bartram, Brown & Burnett (2005) — mapping O*NET work activities to competency profiles.

### Critical Incident Technique

Flanagan, J. C. (1954). The critical incident technique. *Psychological Bulletin,
51*(4), 327-358.

Method: gather behavioral examples of effective/ineffective performance from SMEs,
categorize, derive performance dimensions. Foundational for BARS and behavioral
interview question development.

### SME Delphi

Linstone, H. A., & Turoff, M. (1975). *The Delphi Method: Techniques and Applications.*
Hsu, C.-C., & Sandford, B. A. (2007). The Delphi technique: Making sense of consensus.

Iterative anonymous SME consensus. Standard for competency weight determination and
content validity. Lawshe (1975) content validity ratios.

**Build implication:** the platform's Team Definition module is the operational
implementation of structured SME Delphi. Stage 2 independent rating + Stage 3
divergence surface + Stage 4 reconciliation maps directly to this methodology.

---

## 11. Performance Taxonomy

### Campbell (1990) 8-factor performance model

Campbell, J. P. (1990). Modeling the performance prediction problem in industrial
and organizational psychology. *Handbook of Industrial and Organizational Psychology*.

Eight factors: job-specific task proficiency, non-job-specific task proficiency,
written/oral communication, demonstrating effort, maintaining personal discipline,
facilitating peer/team performance, supervision/leadership, management/administration.

### Borman & Motowidlo task vs contextual

Borman, W. C., & Motowidlo, S. J. (1997). Task performance and contextual performance:
The meaning for personnel selection research. *Human Performance, 10*(2), 99-109.

Task performance: varies by job, predicted by ability.
Contextual performance: similar across jobs, predicted by personality and motivation.
Contextual performance later subsumed into OCB (Organ).

### Pulakos adaptive performance

Pulakos, E. D., Arad, S., Donovan, M. A., & Plamondon, K. E. (2000). Adaptability in
the workplace: Development of a taxonomy of adaptive performance. *Journal of Applied
Psychology, 85*(4), 612-624.

Eight-dimension Job Adaptability Inventory (N=1,619 EFA + N=1,715 CFA): handling
emergencies; handling work stress; creative problem solving; dealing with uncertainty;
learning new tasks/technologies; interpersonal adaptability; cultural adaptability;
physical adaptability.

### CWB

Sackett, P. R. (2002). Counterproductive work behavior. *International Journal of
Selection and Assessment.*
Bennett & Robinson (2000). Workplace Deviance Scale.

**Build implication:** the platform's success criteria (SCIENCE-SPEC §5) span the
four-domain taxonomy: task / contextual-OCB / adaptive / CWB-avoidance. Every role
profile's success criteria must address all four.

---

## 12. Values and Motivation

### Schwartz basic human values

Schwartz, S. H. (1992; 2012). Universals in the content and structure of values.
*Advances in Experimental Social Psychology*; *Online Readings in Psychology and
Culture.*

10 (refined to 19) motivationally distinct values arranged on a circular continuum:
two bipolar dimensions (Self-Transcendence vs Self-Enhancement; Openness to Change vs
Conservation).

**PVQ-RR:** Schwartz, S. H., & Cieciuch, J. (2022). Measuring the refined theory of
individual values in 49 cultural groups: Psychometrics of the Revised Portrait Value
Questionnaire. *Assessment, 29*(5), 1005-1019. 57 items, 19 values × 3 items each.

### Self-Determination Theory

Deci, E. L., & Ryan, R. M. (1985). *Intrinsic motivation and self-determination in
human behavior.*
Ryan, R. M., & Deci, E. L. (2000). Self-determination theory and the facilitation of
intrinsic motivation, social development, and well-being. *American Psychologist,
55*(1), 68-78.

Three basic psychological needs: autonomy, competence, relatedness. Needs-supplies fit
is the operational construct for job fit.

---

## 13. Feedback and Goal Setting

### Locke & Latham goal setting

Locke, E. A., & Latham, G. P. (1990; 2002). *A Theory of Goal Setting and Task
Performance*; *Building a practically useful theory of goal setting and task motivation.*

Specific, challenging goals consistently outperform "do your best." Commitment,
feedback, and task complexity moderate.

### Kluger & DeNisi feedback intervention theory

Kluger, A. N., & DeNisi, A. (1996). The effects of feedback interventions on
performance: A historical review, a meta-analysis, and a preliminary feedback
intervention theory. *Psychological Bulletin, 119*(2), 254-284.

Meta-analyzed 607 effect sizes (N=23,663 observations). **Mean feedback intervention
effect d=.41, but 38% of effects were negative.** Feedback that directs attention to
the self (rather than the task) often degrades performance.

**Build implication:** the platform's guidance composer and feedback features must
be task-focused, not person-focused. This is a measurement-validity requirement, not
soft language.

---

## 14. Faking and Forced-Choice

### Birkeland et al. 2006 meta-analysis

Birkeland, S. A., Manson, T. M., Kisamore, J. L., Brannick, M. T., & Smith, M. A.
(2006). A meta-analytic investigation of job applicant faking on personality measures.
*International Journal of Selection and Assessment, 14*(4), 317-335.

33 studies. Applicants > non-applicants:
- Conscientiousness d=.45
- Emotional Stability d=.44
- Openness d=.13
- Extraversion d=.11

### Salgado 2016 — larger estimate

Salgado, J. F. (2016). A theoretical model of psychometric effects of faking on
assessment procedures. *IJSA, 24*(3), 209-228. Effect size d=0.70.

### Forced-choice mitigation

Martínez, A., & Salgado, J. F. (2021). A meta-analysis of the faking resistance of
forced-choice personality inventories. *Frontiers in Psychology, 12*, 732241.
Forced-choice substantially reduces but does not eliminate faking.

Thurstonian IRT scoring: Brown, A., & Maydeu-Olivares, A. (2011, 2013).

**Build implication:** for high-stakes applicant settings, forced-choice with
Thurstonian IRT is the recommended format. The platform's instrument layer supports
both Likert and forced-choice administration; expert sign-off determines per-instrument
choice.

---

## 15. Test Standards and Documentation

Three primary authorities for legal defensibility:

1. **EEOC Uniform Guidelines on Employee Selection Procedures (1978; 29 CFR Part 1607)**
   — Sections 14 (technical standards for criterion-related, content, construct
   validity studies) and 15 (documentation requirements).

2. **SIOP Principles for the Validation and Use of Personnel Selection Procedures
   (5th ed., 2018)** — professional standards.

3. **AERA, APA & NCME (2014) Standards for Educational and Psychological Testing** —
   the most comprehensive standards document. The 2014 revision elevated fairness from
   secondary to fundamental validity issue ("fairness is a fundamental validity issue
   and requires attention throughout all stages of test development and use," p. 49).
   Chapter 1 (validity), Chapter 2 (reliability), Chapter 3 (fairness), Chapter 11
   (workplace testing).

---

## 16. CAT for Cognitive Assessment

### Embretson & Reise foundation

Embretson, S. E., & Reise, S. P. (2000). *Item Response Theory for Psychologists.*
The canonical IRT/CAT reference.

### Efficiency claim origin

Weiss, D. J., & Kingsbury, G. G. (1984). Application of computerized adaptive testing
to educational problems. *Journal of Educational Measurement, 21*(4), 361-375.

**CAT can achieve equivalent measurement precision with roughly half the items of a
fixed-length test.**

### Personality CAT validation

Reise, S. P., & Henson, J. M. (2000). Computerization and adaptive administration of
the NEO PI-R. *Assessment, 7*(4), 347-364. N=1,059.

Concluded: "the NEO PI-R could be reduced in half with little loss in precision by CAT
administration."

### Matrix reasoning item banks

- Raven's APM (proprietary)
- Sandia matrices (research-grade)
- Open-source AI-generated banks (newer)

**Build implication:** the platform's cognitive module is built on an in-house IRT/CAT
matrix-reasoning item bank. Item parameters (a, b, c) estimated from calibration data
per language. Bank growth and refresh schedule (Art. 15 robustness) is operator work.

---

## End

This document is the scientific reference. The Claude Code build instructions read
from it. The eventual engaged I/O psychologist validates the values it points toward.
The architecture is built; the science is pending expert sign-off; the H-items close
when both meet.
