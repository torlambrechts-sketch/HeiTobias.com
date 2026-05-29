import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it, expect } from 'vitest'

const __filename = fileURLToPath(import.meta.url)
const here = dirname(__filename)
const ROOT = join(here, '..')

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

// Strip // line-comments and /* ... */ block-comments so doc references
// to forbidden names ("we deliberately don't accept target_person_id")
// don't trip the grep tests. We test what the code DOES, not what it
// SAYS about itself.
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')   // block comments
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1') // line comments (avoid breaking URL "http://")
}

const sources = listSources(ROOT)
const corpus  = sources.map(p => ({ path: p, src: readFileSync(p, 'utf8'), code: stripComments(readFileSync(p, 'utf8')) }))
const joined  = corpus.map(c => c.src).join('\n')

describe('CP3.2 — Team-Based Role Definition UI guardrails', () => {
  // ============ T7 — guardrail body copy lives in i18n + is load-bearing ============
  // After ITEM 5 the load-bearing copy moved into en.json behind the
  // guardrail.body_html key. T7 now asserts:
  //   (a) the component pulls the body from i18n (no inline regression)
  //   (b) en.json's guardrail.body_html carries the load-bearing phrases
  //   (c) the body is rendered (not a tooltip)
  it('[T7] SurveillanceGuardrail renders the load-bearing body copy from i18n ("rating the role", "not rating each other")', () => {
    const guardrail = corpus.find(c => c.path.endsWith('SurveillanceGuardrail.tsx'))
    expect(guardrail, 'SurveillanceGuardrail.tsx must exist').toBeTruthy()
    const s = guardrail!.code
    // (a) Component pulls body from i18n
    expect(s).toMatch(/useT\(\)/)
    expect(s).toMatch(/t\('guardrail\.body_html'\)/)
    expect(s).not.toMatch(/title=["'][^"']*not rating/i)

    // (b) en.json carries the load-bearing phrases for the key
    const en = JSON.parse(readFileSync(join(ROOT, '..', '..', 'i18n', 'en.json'), 'utf8')) as Record<string, string>
    const body = en['guardrail.body_html'] ?? ''
    expect(body).toMatch(/rating\s*<strong>the role<\/strong>/i)
    expect(body).toMatch(/not rating each other/i)
    expect(body).toMatch(/SCIENCE-SPEC §7/)
  })

  // ============ T8 — Stage 2 RatingForm renders the guardrail before any input ============
  it('[T8] RatingForm imports + renders SurveillanceGuardrail above the rating inputs', () => {
    const rating = corpus.find(c => c.path.endsWith('RatingForm.tsx'))
    expect(rating, 'RatingForm.tsx must exist').toBeTruthy()
    const s = rating!.src
    expect(s).toMatch(/import\s*\{\s*SurveillanceGuardrail\s*\}\s*from/)
    // Guardrail JSX appears before the first input/textarea/select tag.
    const guardrailIdx = s.search(/<SurveillanceGuardrail\b/)
    const firstInputIdx = s.search(/<(input|textarea|select)\b/)
    expect(guardrailIdx).toBeGreaterThan(-1)
    expect(firstInputIdx).toBeGreaterThan(-1)
    expect(guardrailIdx).toBeLessThan(firstInputIdx)
  })

  // ============ T9 — No peer-personality affordances in UI source ============
  it('[T9] No peer-personality field-shape strings (target_person_id / rater_person_id / rates_person) appear in the rating UI', () => {
    // The test corpus is the team-definition UI sources ONLY (Setup + Rating + Stepper + Header + Guardrail).
    // These keys are in DB-CHECK rejection lists and must never originate from the UI.
    const offenders: string[] = []
    for (const { path, code } of corpus) {
      if (path.includes('__tests__')) continue
      if (/target_person_id|rater_person_id|rates_person/i.test(code)) {
        offenders.push(path + ': ' + (code.match(/.{0,40}(target_person_id|rater_person_id|rates_person).{0,40}/i)?.[0] ?? ''))
      }
    }
    expect(offenders, `Forbidden peer-personality keys leaked into UI sources: ${offenders.join(' | ')}`).toEqual([])
  })

  // ============ T10 — RatingForm only writes via the SECDEF RPC, never direct INSERT ============
  it('[T10] RatingForm never writes to team_definition_evaluations directly — only via rpc_submit_evaluation', () => {
    const rating = corpus.find(c => c.path.endsWith('RatingForm.tsx'))!.src
    expect(rating).not.toMatch(/\.from\(['"]team_definition_evaluations['"]\)/)
    expect(rating).toMatch(/submitEvaluation|rpc_submit_evaluation/)
  })

  // ============ T11 — Run page does not fetch other evaluators' ratings ============
  it('[T11] TeamDefinitionRun page does not call fetchEvaluationsForOwner (would write a read_during_seal audit row)', () => {
    // Page lives one level up at src/pages/TeamDefinitionRun.tsx.
    const runPagePath = join(ROOT, '..', '..', 'pages', 'TeamDefinitionRun.tsx')
    const runPageRaw  = readFileSync(runPagePath, 'utf8')
    const runPageCode = stripComments(runPageRaw)
    expect(runPageCode).not.toMatch(/fetchEvaluationsForOwner/)
    expect(runPageCode).not.toMatch(/rpc_team_definition_evaluations_for_owner/)
    expect(runPageRaw).toMatch(/CP3\.3|divergence|read during seal/i)
  })

  // ============ T12 — guardrail key defined once in en.json, no .tsx leaks ============
  // After ITEM 5 the source of truth is en.json (one definition). The
  // .tsx corpus must NOT carry the literal body — if any later component
  // re-inlines it, drift returns.
  it('[T12] Guardrail copy defined exactly once in en.json, never inlined in a .tsx', () => {
    const phrase = /You are rating\s*<strong>the role<\/strong>/g
    const occurrencesInTsx = joined.match(phrase) ?? []
    expect(occurrencesInTsx.length).toBe(0)
    // And the en.json key exists exactly once.
    const enText = readFileSync(join(ROOT, '..', '..', 'i18n', 'en.json'), 'utf8')
    const enMatches = enText.match(/"guardrail\.body_html"\s*:/g) ?? []
    expect(enMatches.length).toBe(1)
  })

  // ============ T13 — StageStepper renders the four canonical stages ============
  it('[T13] StageStepper sources name all four Delphi stages with the canonical labels', () => {
    const stepper = corpus.find(c => c.path.endsWith('StageStepper.tsx'))!.src
    expect(stepper).toMatch(/Setup/)
    expect(stepper).toMatch(/Independent rating/)
    expect(stepper).toMatch(/Divergence/)
    expect(stepper).toMatch(/Reconciliation/)
  })
})
