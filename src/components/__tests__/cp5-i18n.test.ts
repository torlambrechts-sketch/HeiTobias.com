import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it, expect } from 'vitest'

const __filename = fileURLToPath(import.meta.url)
const here = dirname(__filename)
const SRC = join(here, '..', '..')   // src/

function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1')
}
function listSources(dir: string): string[] {
  const out: string[] = []
  for (const e of readdirSync(dir)) {
    if (e === '__tests__' || e === 'node_modules') continue
    const p = join(dir, e)
    const s = statSync(p)
    if (s.isDirectory()) out.push(...listSources(p))
    else if (e.endsWith('.tsx') || e.endsWith('.ts')) out.push(p)
  }
  return out
}

const LOCALES = ['en', 'nb-NO', 'sv-SE', 'da-DK'] as const

describe('CP5 — i18n setup (Nordic localisation HANDOFF)', () => {
  // ============ T63 — All four dictionaries exist ============
  it('[T63] en / nb-NO / sv-SE / da-DK dictionaries exist + parse as JSON', () => {
    for (const code of LOCALES) {
      const raw = readFileSync(join(SRC, 'i18n', `${code}.json`), 'utf8')
      const parsed = JSON.parse(raw) as Record<string, unknown>
      expect(parsed['_meta.locale'], `${code}.json must self-identify`).toBe(code)
    }
  })

  // ============ T64 — Nordic dictionaries carry the HANDOFF marker ============
  it('[T64] nb-NO / sv-SE / da-DK carry an explicit HANDOFF marker (not silent emptiness)', () => {
    for (const code of LOCALES.filter(c => c !== 'en')) {
      const raw = readFileSync(join(SRC, 'i18n', `${code}.json`), 'utf8')
      const parsed = JSON.parse(raw) as Record<string, string>
      expect(parsed['_meta.coverage'], `${code} coverage marker`).toMatch(/HANDOFF/i)
      expect(parsed['_meta.handoff'], `${code} handoff note`).toMatch(/native-speaker|localiser/i)
    }
  })

  // ============ T65 — Load-bearing keys defined in en.json ============
  it('[T65] en.json defines the load-bearing keys (guardrail, stub_banner, hitl, seal)', () => {
    const en = JSON.parse(readFileSync(join(SRC, 'i18n', 'en.json'), 'utf8')) as Record<string, string>
    for (const k of [
      'guardrail.label', 'guardrail.body_html',
      'stub_banner.label', 'stub_banner.body_html', 'stub_banner.cite', 'stub_banner.stubbed_prefix',
      'hitl.label', 'hitl.body',
      'seal.label_prefix', 'seal.body_clean_html', 'seal.body_unclean_html',
      'locale_switcher.label',
    ]) {
      expect(en[k], `en.json key "${k}"`).toBeTruthy()
    }
  })

  // ============ T66 — i18n provider mounted at the app root ============
  it('[T66] App.tsx wraps the BrowserRouter in <LocaleProvider>', () => {
    const app = readFileSync(join(SRC, 'App.tsx'), 'utf8')
    expect(app).toMatch(/import\s*\{[^}]*\bLocaleProvider\b/)
    expect(app).toMatch(/<LocaleProvider>[\s\S]*<BrowserRouter>/)
  })

  // ============ T67 — Locale switcher in Shell ============
  it('[T67] Shell renders a data-test="locale-switcher" with all four locales', () => {
    const shell = readFileSync(join(SRC, 'components', 'Shell.tsx'), 'utf8')
    expect(shell).toMatch(/data-test="locale-switcher"/)
    expect(shell).toMatch(/LOCALES\.map/)
  })

  // ============ T68 — Load-bearing components actually pull from i18n ============
  it('[T68] Load-bearing components use useT() — no inline body copy regression', () => {
    const targets = [
      join(SRC, 'components', 'team-definition', 'SurveillanceGuardrail.tsx'),
      join(SRC, 'components', 'team-definition', 'SealCallout.tsx'),
      join(SRC, 'components', 'HitlNotice.tsx'),
      join(SRC, 'components', 'role-profile', 'StubBanner.tsx'),
    ]
    for (const path of targets) {
      const code = stripComments(readFileSync(path, 'utf8'))
      expect(code, path).toMatch(/useT\(\)/)
    }
  })

  // ============ T69 — Translate falls back to en when key missing ============
  it('[T69] Nordic dictionaries do NOT define load-bearing keys (they should fall through to en until HANDOFF)', () => {
    for (const code of LOCALES.filter(c => c !== 'en')) {
      const dict = JSON.parse(readFileSync(join(SRC, 'i18n', `${code}.json`), 'utf8')) as Record<string, string>
      // Bag-of-keys check: load-bearing keys absent => useT falls back to en.
      // We *want* them absent in this commit — translations land in a
      // separate HANDOFF commit and would then DELETE this test or relax it.
      for (const k of ['guardrail.body_html', 'stub_banner.body_html', 'hitl.body', 'seal.body_clean_html']) {
        expect(dict[k], `${code} should not yet ship a translation for ${k} (HANDOFF)`).toBeUndefined()
      }
    }
  })

  // ============ T70 — No load-bearing English copy inlined anywhere in src ============
  it('[T70] The "you are rating the role" surveillance phrase appears only in en.json — not in any .tsx', () => {
    const phrase = /You are rating\s*<strong>the role<\/strong>/
    for (const path of listSources(SRC)) {
      if (path.includes('__tests__')) continue
      const src = readFileSync(path, 'utf8')
      expect(phrase.test(src), `Inlined guardrail copy found in ${path}`).toBe(false)
    }
  })
})
