# DESIGN.md — UI System & Visual Language

> How we build the interface: **shadcn/ui as the accessible, unstyled-by-default component base**, restyled through our own design tokens into a distinctive, editorial, structural aesthetic — not generic SaaS, not default-shadcn-on-white. This file is the contract between "use a proven component library" and "don't look like everyone else."

---

## 1. Philosophy

- **shadcn/ui gives us the plumbing** — accessible primitives (Radix under the hood), composable, copy-into-repo components we fully own and can restyle. We do **not** accept its default look; we override tokens and component styles.
- **Our aesthetic is editorial / structural:** confident typography, strong rules and borders, intentional asymmetry, generous structure, a warm paper-and-ink palette with sharp signal accents. Think "well-designed report / operating system for people decisions," not "another pastel dashboard."
- **Restraint with conviction.** This is a serious tool handling sensitive people-data. The design is precise and calm, with a few bold moments — not maximalist, not timid.
- **Trust through clarity.** Because we make consequential recommendations about people, the UI must always make *provenance, confidence, and human-control* legible. Never present a score as a verdict.

---

## 2. How we use shadcn/ui

- **Install per-component** (the shadcn CLI copies source into `components/ui/*`). We own and edit that source.
- **Theme via CSS variables**, not by forking each component. We set our tokens on `:root` and shadcn components consume them.
- **Allowed to restyle**, expected to: border treatments, radii, shadows, typography, spacing, focus rings.
- **Keep**: accessibility behavior, keyboard handling, ARIA, focus management. Never strip these.
- **Composition over customization sprawl:** build feature components by composing shadcn primitives; don't reinvent a Dialog/Popover/Command.

Core shadcn components we lean on: `button`, `card`, `dialog`, `sheet`, `dropdown-menu`, `command`, `tabs`, `table`, `badge`, `tooltip`, `form` (+ react-hook-form + zod), `select`, `slider` (trait ranges), `progress`, `avatar`, `separator`, `accordion`, `toast`/`sonner`, `skeleton`, `scroll-area`.

---

## 3. Design tokens

Defined as CSS variables and mirrored in `tailwind.config`. Tokens drive both shadcn theme vars and our own utilities. Per-tenant branding (`organizations.settings_json`) may override the accent + logo only — never the structural system.

### 3.1 Color — light (default)
A warm paper-and-ink base with functional accents. **No purple-on-white. No flat cold grey SaaS.**

```css
:root {
  /* base */
  --paper:        #f4f1ea;   /* app background (warm) */
  --surface:      #fbfaf6;   /* cards / raised */
  --ink:          #13131a;   /* primary text / borders */
  --muted:        #6a675e;   /* secondary text */
  --line:         #2a2a35;   /* strong rules / borders */
  --hairline:     #cfcabd;   /* dashed dividers */

  /* functional accents (semantic, not decorative) */
  --accent:       #e8593a;   /* signal / primary action / "attention" */
  --role:         #3b5b8c;   /* Role Profile entity (slate blue) */
  --person:       #2f6f5e;   /* Person Profile entity (deep green) */
  --highlight:    #c9a227;   /* emphasis / ochre */

  /* fit quadrant semantics */
  --fit-grow:     #c9a227;   /* growth gap */
  --fit-flight:   #e8593a;   /* flight risk */
  --fit-stable:   #2f6f5e;   /* stable fit */
  --fit-misfit:   #b23a2a;   /* emerging misfit (intervene) */

  /* shadcn mapping */
  --background:   var(--paper);
  --foreground:   var(--ink);
  --card:         var(--surface);
  --primary:      var(--ink);
  --primary-foreground: var(--paper);
  --secondary:    var(--surface);
  --accent-color: var(--accent);
  --border:       var(--ink);
  --ring:         var(--accent);
  --radius:       4px;        /* tight, structural — not pill-soft */
}
```

### 3.2 Color — dark
For data-dense/manager surfaces and user preference.
```css
[data-theme="dark"] {
  --paper:   #16151a;
  --surface: #1e1d24;
  --ink:     #f1efe9;
  --muted:   #a39f95;
  --line:    #3a3a45;
  --hairline:#3a3a45;
  /* accents keep their hues, lightened ~8% for contrast */
}
```

### 3.3 Typography
Distinctive pairing — a characterful display serif + a clean grotesque body + mono for data/labels. **Never Inter/Roboto/Arial as the brand face.**

```css
--font-display: "Fraunces", Georgia, serif;        /* headings, section titles */
--font-body:    "Archivo", system-ui, sans-serif;  /* body, UI */
--font-mono:    "Space Mono", ui-monospace, monospace; /* labels, metrics, tags, code */
```
Rules:
- **Display (Fraunces):** page/section titles, role & person names, big numbers. Use optical sizing; allow italic for emphasis.
- **Body (Archivo):** all UI text, paragraphs, form labels. Weights 400–800.
- **Mono (Space Mono):** eyebrows, tags, metric units, IDs, audit timestamps, "type" labels. Uppercase + letter-spacing for eyebrows.
- Scale (rem): display 2.4 / 1.8 / 1.4; body 1 / 0.875; mono labels 0.69–0.75 uppercase, letter-spacing 1–2px.

### 3.4 Structure, borders, shadows
The aesthetic is **structural** — borders and rules do the work, not soft blur.
```css
--border-weight: 2px;            /* default component border */
--border-strong: 2.5px;          /* cards, key containers */
--shadow-hard: 6px 6px 0 var(--ink);  /* offset "printed" shadow on key cards */
--radius: 4px;                   /* corners stay tight */
```
- Cards: strong ink border + optional hard offset shadow (entity cards use a colored offset: role=`--role`, person=`--person`).
- Dividers between meta and body: 1.5px **dashed** `--hairline`.
- Hover on interactive cards: translate(-2px,-2px) + shadow grows to `8px 8px`.
- Avoid soft drop-shadows and heavy blur; this is print-grade, not glassmorphism.

### 3.5 Spacing & layout
- 8px base grid. Generous section spacing (section rules at ~44–48px vertical rhythm).
- Section dividers: a horizontal rule with a centered mono uppercase label (the `section-rule` pattern).
- Embrace controlled asymmetry and grid-breaking in marketing/overview surfaces; keep operational surfaces (tables, manager workspace) calm and aligned.

### 3.6 Motion
- Subtle, structural. Page-load: one orchestrated staggered reveal, not scattered micro-animations.
- Interactive feedback: the card "lift" on hover; focus ring in `--accent`.
- Respect `prefers-reduced-motion`.

---

## 4. Domain-specific UI patterns

These are product-specific components composed from shadcn primitives — build once, reuse.

- **Entity badge** — visually distinguishes Role (slate `--role`) vs Person (green `--person`) data everywhere they appear. Consistency here teaches the two-entity model implicitly.
- **Fit display** — never a single number presented as a verdict. Show **multi-dimensional** fit (per competency / trait-range / context) with the human-decision affordance always visible. Use `--fit-*` semantics for the four quadrants in re-fit views.
- **Trait-range control** — a `slider`-derived component showing the role's **target band** (not a point) with the person's value plotted against it. Core to expressing "ranges, not more-is-better."
- **Divergence view** (team role definition) — surfaces disagreement between evaluators rather than averaging; visually emphasizes the spread.
- **Provenance & confidence chips** — mono tags showing data source, recency, and confidence on any profile-derived insight. Builds trust.
- **Consent state indicator** — always-visible status of the data subject's consent on any personal-data surface; links to the consent dashboard.
- **Guidance card** — manager guidance always shows it is grounded (framework reference) and is an *informing* suggestion, never an instruction.
- **Audit/timeline** — mono-labeled, dense, calm; for re-fit history and audit trails.

---

## 5. Accessibility & trust requirements

- WCAG AA contrast minimum; verify accent-on-paper combinations (especially `--accent` text).
- Keyboard-complete: every interaction reachable and operable without a mouse (shadcn/Radix gives this — don't break it).
- Focus always visible (`--ring`).
- **Sensitive-data UX:** consent state, data provenance, and the human-in-the-loop control must be visible wherever a person's profile or a recommendation appears. This is both an ethical and an EU AI Act requirement, expressed through design.
- Localizable: layouts must tolerate longer Nordic strings (no fixed-width truncation of critical labels).

---

## 6. The "never" list (visual)

- ❌ Default shadcn-on-white look. Always apply our tokens.
- ❌ Purple/indigo gradients on white (the generic-AI tell).
- ❌ Inter/Roboto/Arial as the brand typeface.
- ❌ Soft glassmorphism / heavy blur — we are structural/print-grade.
- ❌ A fit score shown as a single verdict number with no dimensions and no human-control affordance.
- ❌ Pill-soft rounded everything — keep radii tight (`4px`).
- ❌ Stripping accessibility behavior from shadcn primitives.

---

## 7. Implementation notes

- `tailwind.config` extends `colors`, `fontFamily`, `borderWidth`, `boxShadow` from the tokens above so utilities (`bg-paper`, `text-ink`, `shadow-hard`, `font-display`) are available.
- shadcn theme variables map to our tokens in the global stylesheet (§3.1).
- Per-tenant branding overrides **accent + logo only**, injected from `organizations.settings_json`; structural tokens are fixed.
- Fonts self-hosted (EU/privacy) or via a compliant CDN; preload display + body.
- Keep a single source of truth: tokens in CSS vars → consumed by both Tailwind and shadcn. Don't duplicate color literals in components.

---

*See `CLAUDE.md` for architectural rules and `PHASE0-SPEC.md` for the data model. Design serves the product principle: make people-decisions clear, defensible, and human-controlled.*
