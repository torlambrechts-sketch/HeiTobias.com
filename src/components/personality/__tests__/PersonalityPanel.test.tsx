import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

// Static-source assertions for the PersonalityPanel component. The
// panel rendering itself is exercised by manual + Playwright tests
// (out of scope here); these tests pin the load-bearing rules that
// must hold even if the layout is refactored:
//
//   * HUMAN-REVIEW flags are visually distinct from contributions and
//     carry the "do not reduce the match number" language.
//   * The "fit informs, never decides" notice is present on the panel.
//   * Every score / match row has a StubBadge when _dev_stub is true.
//   * The panel never renders an action that auto-decides anything —
//     only a "recompute" button (which is a re-read, not a decision).

const src = readFileSync(
  fileURLToPath(new URL('../PersonalityPanel.tsx', import.meta.url)),
  'utf8',
)

describe('PersonalityPanel — discipline assertions (source-static)', () => {
  it('carries the fit-informs-never-decides notice', () => {
    expect(src).toMatch(/fit informs, never decides/i)
    expect(src).toMatch(/GDPR Art\. 22.*EU AI Act/)
  })

  it('renders human-review flags with explicit non-reduction language', () => {
    expect(src).toMatch(/human-review flag/i)
    expect(src).toMatch(/do not reduce the match number/i)
  })

  it('renders flags in a visually distinct (amber-bordered) container', () => {
    // The flag block uses border-2 border-amber + a dedicated data-test.
    expect(src).toContain('data-test="personality-flags"')
    expect(src).toMatch(/border-amber/)
  })

  it('renders StubBadge on stubbed trait scores AND on stubbed role matches', () => {
    // At least two StubBadge usages — one for trait scores, one for matches.
    const count = (src.match(/<StubBadge \/>/g) ?? []).length
    expect(count).toBeGreaterThanOrEqual(2)
  })

  it('does not render any "auto-decide" / "reject" / "rank" action', () => {
    // Negative assertion: keywords the panel must NEVER use as a CTA verb.
    // (Substring search is conservative — wording the trip might appear
    // in copy explaining what the system does NOT do; here we look for
    // them being part of a JSX expression as a clickable.)
    expect(src).not.toMatch(/onClick=.*reject/i)
    expect(src).not.toMatch(/onClick=.*rank/i)
    expect(src).not.toMatch(/onClick=.*auto.?decide/i)
  })

  it('warns that sensitive traits are flagged, not scored numerically', () => {
    expect(src).toMatch(/sensitive/i)
    expect(src).toMatch(/never as a numeric input/i)
  })

  it('reads from the right tables (does not introduce a parallel personality_responses path)', () => {
    expect(src).toContain('assessment_scores')
    expect(src).toContain('personality_role_matches')
    expect(src).not.toContain('personality_responses')  // would be a schema split
  })

  it('exposes a recompute button that calls the SECDEF RPC, not a direct write', () => {
    expect(src).toContain("'personality_compute_scores'")
    expect(src).not.toMatch(/\.insert\(\s*{[^}]*match_score/)  // no direct client INSERTs
  })
})
