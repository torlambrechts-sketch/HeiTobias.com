# DESIGN.md — UI System & Visual Language

> **Build approach:** shadcn/ui as the accessible component base (we own the source, keep the behavior, restyle the look), themed via CSS variables into a warm, editorial, premium aesthetic. Icons are **Lucide** (shadcn's default set). This file is the contract: use a proven library, but don't ship the default look.
>
> **Aesthetic direction:** a warm cream-green canvas, dark forest-green chrome, high-contrast serif display, and soft tinted status pills. See `sample-ui-v3.html` for the canonical rendering. Our ownable signatures — the role/person entity-color system, the trait-range control, and consent-as-first-class — keep the brand distinctively ours.

---

## 1. Philosophy

- **Warm, editorial, calm, trustworthy.** This tool makes consequential, sensitive judgments about people; the interface should feel considered and human, not coldly corporate or generically "SaaS."
- **shadcn/ui gives the plumbing** (Radix accessibility, composable primitives we copy into the repo). We override tokens and styles; we never strip accessibility behavior.
- **Trust through clarity.** Wherever a person's profile or a recommendation appears, the UI must make *provenance, confidence, and human control* legible. A score is never shown as a verdict.

---

## 2. The three-tier app shell (canonical layout)

```
[ dark-green icon rail ] [ cream section nav ] [ content area ]
       60px                    220px               fluid
```

1. **Dark-green icon rail (60px)** — `--rail` background. White wordmark/logo tile at top, Lucide icons for top-level areas (Dashboard, Hiring, People, Growth, Insights, Company), settings + user avatar pinned to bottom. Active item = white tile with a small left accent tab.
2. **Cream section nav (220px)** — `--canvas` background, serif wordmark, UPPERCASE letter-spaced collapsible group headers (each with a Lucide icon + chevron) and bulleted sub-items. Active sub-item: bold ink text + green bullet.
3. **Content area** — `--canvas` background; white panels float on it. Top app-bar with breadcrumb + org switcher + bell/check icons + avatar.

**Signature element — the forest tab band:** section tabs render on a dark `--forest` bar with rounded top corners; the active tab is a white "lifted" notch (`border-radius` top corners, small top/left margin). The white `.panel` attaches directly beneath it (no top border). This is the most recognizable structural move — use it for any tabbed object (person record, team list, role detail).

---

## 3. Design tokens

Defined as CSS variables, mirrored into `tailwind.config`. Per-tenant branding may override **accent + logo only**; structural tokens are fixed.

```css
:root{
  /* surfaces */
  --canvas:#f3f1e8;     /* warm cream-green app canvas + sidebars */
  --canvas-2:#eceadf;   /* deeper cream: hovers, track fills */
  --surface:#ffffff;    /* white cards / panels */

  /* green chrome */
  --rail:#2c3b30;       /* darkest green — the icon rail */
  --forest:#3a4d3f;     /* forest green — tab bands, filter buttons */
  --forest-2:#2f4034;   /* hover/darker */
  --green:#3f7d5a;      /* accent green — links, "add", positive */

  /* text */
  --ink:#2a2a26;        /* warm near-black */
  --muted:#8a8a7e;      /* secondary / uppercase labels */
  --faint:#a6a698;      /* tertiary / icon idle */

  /* lines */
  --line:#e4e1d5;       /* hairline dividers/borders */
  --line-2:#d8d4c6;     /* slightly stronger (inputs, checkboxes) */

  /* soft tinted status pills (bg / fg pairs) */
  --open-bg:#dcebdf;      --open-fg:#3f7d5a;     /* Open / Active / Stable */
  --draft-bg:#ece7d6;     --draft-fg:#8a7a52;    /* Draft / Growth gap / Assessed */
  --internal-bg:#f3e9cf;  --internal-fg:#a8862f; /* Internal / consent:hiring */
  --reject-bg:#f4dedb;    --reject-fg:#b8584a;   /* Rejected / Emerging misfit */
  --interview-bg:#dde7f0; --interview-fg:#42729e;/* Interview / Flight risk */
  --offer-bg:#dcebdf;     --offer-fg:#3f7d5a;    /* Offer */

  /* domain entities (consistent everywhere) */
  --role:#42729e;       /* Role Profile = blue */
  --person:#3f7d5a;     /* Person Profile = green */
  --amber:#a8862f;      /* growth / mid-fit */
  --rust:#b8584a;       /* misfit / intervene */

  --radius:6px; --radius-lg:8px;
  --shadow:0 1px 2px rgba(58,77,63,.05), 0 6px 18px rgba(58,77,63,.05);

  --font-display:"Playfair Display", Georgia, serif; /* placeholder for a licensed Didone */
  --font:"Inter", system-ui, sans-serif;
}
```

### Dark mode
Defer to a later phase. The product is canvas-light by identity (the warmth is the brand). If/when needed, darken `--canvas`/`--surface` toward warm charcoals, keep the green chrome, lift accent luminance ~8%.

---

## 4. Typography

- **Display — high-contrast serif (Didone).** Big page titles ("Maria Lindqvist"), panel counts ("9 People"), card headings. This is the brand's voice. Ships now as **Playfair Display** (closest free match); **budget to license a true Didone** (Canela / Tiempos Headline / GT Sectra) before scale — Playfair reads slightly more "fashion," the licensed faces read more "modern-editorial."
- **Body & UI — Inter.** All controls, table text, paragraphs, form labels. Weights 400–700.
- **UPPERCASE labels.** Section/group headers, metadata, "ADD PERSON", "APPLICATION DETAILS": Inter, 11px, weight 700, letter-spacing ~1.3px, color `--muted`. A defining texture — use liberally for labels, never for body.
- Scale: display 40 / 30 / 26 / 22; body 14 / 13.5 / 13; labels 11–11.5 uppercase.

---

## 5. Icons — Lucide (standard)

- **Use Lucide everywhere.** It's shadcn's default; MIT-licensed; ~1,500 consistent icons. No emoji, no unicode glyphs, no mixed sets.
- Default stroke-width **2** (a slightly bold, confident feel); set once globally on the Lucide component.
- Sizes: 21px (icon rail), 18px (default), 15px (inline with labels, sub-nav, table).
- Idle icon color `--faint`/`--muted`; active inherits `--ink` or white (on green).
- Map domain concepts to stable icons, e.g. target = role fit, refresh-cw = re-fit, layers = team composition/assessments, shield = consent & data, clock = 1:1 history, trending-up = growth, file-text = profile.

---

## 6. Components

- **Buttons:** primary = `--forest` solid white text; filter/utility = `--forest` solid (uppercase, tracked); secondary = white + `--line-2` border; "add" = green text + plus icon, uppercase.
- **Status pills:** rounded-20px, uppercase, weight 700, tinted bg/fg pairs from §3. The same pill system expresses hiring states AND the four re-fit quadrants (Stable=open, Growth gap=draft, Flight risk=interview, Emerging misfit=reject) — one consistent visual language.
- **Tables:** generous row height (~16px padding), `--line` row dividers, left checkbox column (checkbox fills `--forest` when on), names as underlined link-style (`--line-2` underline, 3px offset), location subline in `--muted`, status pills, right-aligned meta. Row hover = `--canvas`.
- **Cards/panels:** `--surface`, 1px `--line`, `--radius-lg`, soft `--shadow`. Attach under a forest tab band with no top border/radius.
- **Stat strip:** big serif numbers in a row, divided by `--line`, first stat optionally boxed (2px `--ink` border). Color the number by meaning (`--person` positive, `--amber` mid, `--rust` flag).
- **Detail view:** left sub-nav (210px, `--line` divider, active = `--canvas` bg) + right body with serif H2 and key/value `.drow` lines separated by `--line`.

---

## 7. Domain-specific patterns (our ownable signatures)

- **Entity color system.** Role data = `--role` (blue), Person data = `--person` (green), used in badges, the trait control, fit bars, everywhere. Teaches the two-entity model implicitly; it's our most distinctive, non-the reference aesthetic signature.
- **Trait-range control.** A slim rounded track (`--canvas-2`); the role's **target band** is a `--role`-tinted segment with two edge bars + an uppercase "role band" mini-label; the person's value is a `--person` dot marker. Expresses "bands, not more-is-better." Below/above-band notes use `--rust`; in-band uses `--person`. Build from a styled Radix Slider.
- **Multi-dimensional fit.** Never a single verdict number. Per-dimension bars (`--person`/`--amber`) + a permanent "Human decides" note: the score *informs*, doesn't decide; overrides logged. (EU AI Act human-in-the-loop, expressed in UI.)
- **Re-fit quadrant / signal.** Four states as the tinted pills above; "emerging misfit" flagged `--rust`. Always framed developmentally, with the person's consent noted.
- **Consent & provenance.** Consent state shown as a first-class pill/column wherever personal data appears; a shield icon for the "Consent & data" surface. Provenance ("profile updated 4d ago · assessment + 2 pulses") shown near any profile-derived insight.
- **Grounded guidance.** Manager guidance carries a `--role`-tinted "grounded" chip naming its framework source — never freeform advice about a named person.

---

## 8. Accessibility & trust

- WCAG AA contrast; verify tinted-pill fg/bg pairs and `--muted`-on-`--canvas`.
- Full keyboard operability (Radix gives this — don't break it); visible focus ring in `--green`.
- Sensitive-data UX: consent, provenance, and the human-in-the-loop control must be visible wherever a profile or recommendation shows. Ethical *and* an EU AI Act requirement.
- Localizable (nb-NO / sv-SE / da-DK / en); layouts tolerate longer Nordic strings — no fixed-width truncation of critical labels.

---

## 9. The "never" list

- Never ship the default shadcn/Geist look — always apply these tokens.
- Never purple-on-white, no cold flat-grey SaaS, no glassmorphism.
- Never mix icon sets or use emoji/unicode glyphs — Lucide only.
- Never show a fit score as a single verdict number without dimensions + the human-control affordance.
- Never strip accessibility behavior from shadcn/Radix primitives.
- Never copy any single reference product wholesale — keep our entity-color + trait-range + consent signatures so the brand is ours.
- Never hardcode color literals in components — consume the tokens.

---

## 10. Implementation notes

- `tailwind.config` extends `colors`, `fontFamily`, `borderRadius`, `boxShadow` from §3 so utilities (`bg-canvas`, `text-ink`, `font-display`) exist; map shadcn theme vars to the same tokens.
- Lucide via `lucide-react`; set a default `strokeWidth={2}` wrapper.
- Self-host fonts (EU/privacy) or use a compliant CDN; preload display + body. License the Didone before scale.
- Single source of truth: CSS vars consumed by both Tailwind and shadcn; no duplicate literals.

---

*Canonical visual reference: `sample-ui-v3.html`. See `CLAUDE.md` for architecture rules and `PHASE0-SPEC.md` for the data model. Design serves the principle: make people-decisions clear, defensible, and human-controlled.*
