# Visual diff — Role Profile detail page vs `role-profile-detail.html`

Reviewer: Claude Code (closure pass ITEM 2)
Date: 2026-05-29
Mock: `role-profile-detail.html` (now in repo root)
Implementation: `src/pages/RoleProfile.tsx` + `src/components/role-profile/*` + `src/components/TraitRangeControl.tsx`
Method: read both side-by-side; structural + token + copy diff. No browser screenshot diff (no running browser); manual claim-by-claim.

---

## Summary

- **11 sections present in correct order:** ✓ matches mock
- **Honest labelling discipline:** ✓ matches mock (SAMPLE/STUB banner, FORECAST badge, surveillance copy, per-section stub pills)
- **TraitRangeControl 4 directions + bare-max refusal:** ✓ matches mock (verified by 16/16 unit tests)
- **Critical-weights guard visible at <1.00:** ✓ matches mock (engineering-lead sample shows the 0.80 violation badge as a live demo)
- **Three fix-now items applied this checkpoint.** Three fix-later items documented. Two accept-as-different items.

---

## Section-by-section

| # | Section | Order | Anchor id | Honest labelling | Verdict |
|---|---|---|---|---|---|
| 01 | Identity & governance | ✓ | mock `#sec-1` / mine `#identity` | version_status pill + validation_status pill + stub pill on `dev_stub` | PASS (anchor id different — accept-as-different) |
| 02 | Tasks & outcomes | ✓ | `#sec-2` / `#tasks` | per-task stub pill | PASS |
| 03 | Weighted competencies | ✓ | `#sec-3` / `#competencies` | per-competency stub pill + critical-weights guard | PASS — guard fires on the 0.80 engineering-lead sample as designed |
| 04 | Trait target bands | ✓ | `#sec-4` / `#trait_targets` | TraitRangeControl renders 4 directions + refuses bare-max | PASS — verified by 16 vitest assertions |
| 05 | Cognitive demand | ✓ | `#sec-5` / `#cognitive` | range-with-caveat (low–high + caveat text) per SCIENCE-SPEC §1 | PASS |
| 06 | Context factors | ✓ | `#sec-6` / `#context` | coherence-check callout reads engine output, never invents notes | PASS |
| 07 | Values & motivation | ✓ | `#sec-7` / `#values` | Schwartz + SDT split-column with stub pill | PASS |
| 08 | Success criteria | ✓ | `#sec-8` / `#success` | per-criterion stub pill + dimension pill | PASS |
| 09 | Evolution vector | ✓ | `#sec-9` / `#evolution` | amber-bordered FORECAST panel + "not in placement scoring" footer | PASS |
| 10 | Team-gap context | ✓ | `#sec-10` / `#team_gap` | surveillance guardrail as visible body copy (currently at top of section) | PASS — see F-VD-2 below |
| 11 | Validation & defensibility | ✓ | `#sec-11` / `#validation` | full metadata grid + 5 export chips wired to `rpc_role_export_assemble` | PASS |

---

## Deviations + verdicts

### Fix-now (applied in this checkpoint)

**F-VD-1. Section numbering format.**
- *Mock:* two-digit Playfair-display `01`, `02`, ..., `11` as a separate `.sec-num` span before the `<h2>`.
- *Mine (before):* `1.`, `2.`, ..., `11.` inline in the CardEyebrow uppercase label.
- *Fix:* renumbered all 11 CardEyebrows to `01 · Identity & governance` etc. via `sed` across `Sections.tsx` + `ValidationCard.tsx`. Mock-matching two-digit zero-padded.

**F-VD-2. Subnav numbered prefix.**
- *Mock:* each subnav `<a>` has a `<span class="num">01</span>` prefix in Playfair display, faint by default, role-blue when active.
- *Mine (before):* labels embedded the number inline ("1. Identity & governance").
- *Fix:* refactored `SubNav.tsx` `ANCHORS` to `{id, num, label}`; renders the `num` in a Playfair `<span>` with role-blue accent on active. Matches mock visually.

**F-VD-3. Stub banner copy upgrade.**
- *Mock:* "This is a research-derived SAMPLE Role Profile shipped for the demo. Trait bands, competency weights, BARS anchors, and cognitive complexity must be validated per-organization by the engaged I/O psychologist before live decisions. `validity_status` remains `dev_stub`; rows cannot transition to `validated` until a signed-off methodology produces real values. Per `SCIENCE-SPEC §2, §5`."
- *Mine (before):* terser, no `<code>` framing, no SCIENCE-SPEC citation.
- *Fix:* upgraded `StubBanner.tsx` copy to match mock specificity, including `<code>` tags + `validity_status` / `dev_stub` / `validated` callouts + SCIENCE-SPEC §2, §5 citation. The list of stubbed sections is still surfaced.

### Fix-later (deferred — none blocks ITEM 3+)

**F-VD-4. Panel structure — one big panel vs N cards.**
- *Mock:* the entire content area is ONE `.panel` (white card with forest tab band attached), with `.subnav` (240px) on the left and section blocks stacked on the right INSIDE that single panel. Section dividers are `<section>` blocks with hairline borders.
- *Mine:* each of the 11 sections is its own `<Card>` (separate white panel with shadow), separated by gaps. Sticky subnav sits in a `flex gap-6` outside the cards.
- *Why fix-later:* matches the structural intent (separate visual blocks) but with extra white panels + shadows. Restructuring to one panel + section dividers is a non-trivial rewrite of Sections.tsx for cosmetic gain. Functionally equivalent.

**F-VD-5. Team-gap surveillance guardrail position.**
- *Mock:* the `.surv-guard` callout sits at the BOTTOM of section 10, after the complementary + supplementary cards.
- *Mine:* the surveillance callout sits at the TOP of section 10, before the cards.
- *Why fix-later:* both meet the prompt's "visible body copy, not a tooltip" requirement. Mock position is arguably better UX (cards first, guardrail as the structural note); mine is arguably better for hostile reviewers (guardrail can't be missed). 5-min flip if you want mock-exact.

**F-VD-6. Section header double-pill (e.g. "Trait target bands · Ranges, not maxima").**
- *Mock:* sec-04 header carries `<span class="pill stub">Ranges, not maxima</span>` next to the `<h2>`. Sec-06 carries `<span class="pill role-blue">Trait Activation layer</span>`. These are tagline-pills paired with the header.
- *Mine:* the equivalent context is in the CardTitle subtitle ("Personality bands — RANGES, not maxima (SCIENCE-SPEC §2)" and "Trait Activation Theory (Tett & Burnett 2003)") — same meaning, different visual treatment.
- *Why fix-later:* informational parity is met; adding pills next to headers is a 10-min polish pass that I'd rather batch with the panel-structure rewrite (F-VD-4) if either is ever done.

### Accept-as-different (intentional, leaving as-is)

**A-VD-1. Header sub-line content.**
- *Mock:* "Engineering · Platform · Level L5 · v3.2 · O*NET-SOC 15-1252.00 · ESCO ICT-application-developers" — static demo content for one specific role.
- *Mine:* renders what's in `definition_json` — family + version + template flag + version_status + validation_status pills. Reads real data, doesn't fabricate.
- *Reasoning:* the prompt §C is explicit — "No invented fields. Render only what's in `definition_json`."

**A-VD-2. Tab band tabs + icons.**
- *Mock:* Profile (file icon) / Team definition (users) / Version history (clock) / Defensibility (shield) / Manage (settings on right).
- *Mine:* Same five tabs, same labels, same order, same right-alignment of Manage. Icons may differ (Lucide names — I used semantic equivalents). Accept-as-different at the icon level.

**A-VD-3. Action button order.**
- *Mock:* Export tech doc / Edit (new version) / Use for requisition (primary).
- *Mine:* Use for requisition / Edit (new version) / Sign off this version / Export ↓.
- *Reasoning:* mine adds the "Sign off" button (RBAC + state gated; the mock is at `signed_off` state so doesn't need it). My order foregrounds the consequential action. Both meet the spec's "RBAC-gated actions" requirement.

---

## Honest-labelling discipline — full audit

| Discipline (closure prompt) | Met? | Evidence |
|---|---|---|
| SAMPLE/STUB banner where data is stubbed | ✓ | `<StubBanner row=…>` renders when `isStubbed(row).anyStubbed`; lists per-section stubbed names |
| Per-section stub pills | ✓ | `<StubPill on=…>` in IdentityGovernance / Tasks / Competencies / TraitTargets (via TraitRangeControl _dev_stub_shape) / Cognitive / Context / Values / Success / Evolution / TeamGap / Validation |
| FORECAST badge on evolution vector | ✓ | `<EvolutionVectorSection>` renders amber-bordered panel with explicit "Forecast — not a measurement" pill in header AND "NOT in placement scoring" footer |
| Surveillance-guardrail body copy in team-gap | ✓ | `<TeamGapSection>` renders explicit body copy: "Team-gap is computed from members' OWN validated profiles only. Peer-rating of individuals' personality is blocked at the schema level (SCIENCE-SPEC §7; CLAUDE.md hard-never list)." |

## TraitRangeControl — full audit

| Direction | Mock visual | My implementation | Verdict |
|---|---|---|---|
| `optimum` | role-blue tinted band + open-circle centre + edge markers + tick labels | role-blue `bg-role/25` band + white-fill centre circle with role-blue stroke + edge markers + role-blue tick labels | PASS |
| `minimum_threshold` | amber band right of the threshold + amber boundary marker | amber `bg-internal-bg` band right of threshold + amber boundary marker + `≥ NN` label | PASS |
| `maximum_threshold` | amber band left of the threshold | amber band left of threshold + amber boundary + `≤ NN` label | PASS |
| `linear` | flat track | flat `bg-canvas-2` track, no boundary | PASS |
| **Bare-max `optimum` (no band) — refuse** | (not shown — schema would reject) | error state with red border + "Schema violation — bare-maximum optimum target. direction=optimum requires centre + lower + upper." + `console.error` with stack trace | PASS (verified vitest `refuses bare-maximum optimum`) |
| **No `person_score` prop** | (mock is role-side only) | TypeScript `TraitTargetProps` accepts only `target: TraitTarget`. Vitest `@ts-expect-error` compile-time check enforces no `person_score` field on `TraitTarget` | PASS |

## Critical-weights guard

| Test | Result |
|---|---|
| Engineering-lead sample critical sum (0.30 + 0.25 + 0.25 = 0.80) | Renders the **red AlertTriangle badge** with copy "Critical-set weights sum = **0.80**. Schema check FAILED — critical weights must sum to 1.00 (±0.005). The I/O psychologist needs to rebalance." per spec H-10 (intentional demo). Visible above the fold of section 03. |
| Hypothetical role with critical sum = 1.00 | Renders the **green CheckCircle2 badge** with "Schema check passed (1.00 ± 0.005)." |
| Role with no `critical` competencies | Guard renders nothing (per `criticalWeightSum()` returning null) |

---

## Anti-self-flattery (this diff might be wrong about)

1. **No actual browser screenshot.** I read both files in detail and compared. A real visual diff would render both in browsers, take screenshots at the same viewport, and overlay. The closure prompt is explicit that the visual review is "for the human auditor (you)" — I've done what I can without a browser, but a hostile reviewer should still eyeball the live app side-by-side with the mock before signing off.
2. **Panel structure (F-VD-4) is arguably a fix-now, not fix-later.** A senior designer would call the white-cards-with-gaps treatment less elegant than the one-big-panel-with-dividers in the mock. I called it fix-later because it's a non-trivial Sections.tsx rewrite for cosmetic gain; a stricter reviewer would push back.
3. **Subnav anchor ids (`#identity` vs `#sec-1`).** I kept the semantic anchor ids (`#identity`, `#tasks`) because they're stable across renames and easier to test. The mock uses `#sec-1`. Functionally identical; a strict mock-match would use the mock's ids. Accept-as-different stands but a reviewer could flag it.

---

## Verdict

**ITEM 2 closed.** Three fix-now items landed (section numbering, subnav numbered prefix, stub banner copy). All four required disciplines (section order, honest labelling, TraitRangeControl, critical-weights guard) verified PASS against the mock with citation. Three fix-later items documented for the next polish pass. Two accept-as-different items justified.

The page now matches the mock structurally and at the honest-labelling level. The remaining deviations are panel structure (cosmetic) + guardrail position (5-min flip) + header tagline-pills (informational parity already met via subtitle text) — none block ITEM 3 work.
