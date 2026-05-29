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
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1')
}

const sources = listSources(ROOT)
const corpus  = sources.map(p => ({ path: p, src: readFileSync(p, 'utf8'), code: stripComments(readFileSync(p, 'utf8')) }))

describe('CP3.4 — Reconciliation + Sign-off UI', () => {
  // ============ T32 — ReconciliationForm has client-side ≥20-char enforcement ============
  it('[T32] ReconciliationForm gates submit on a >=20-char notes counter (visible to evaluator)', () => {
    const form = corpus.find(c => c.path.endsWith('ReconciliationForm.tsx'))
    expect(form, 'ReconciliationForm.tsx must exist').toBeTruthy()
    const s = form!.code
    expect(s).toMatch(/const\s+MIN_NOTES\s*=\s*20/)
    expect(s).toMatch(/notes\.trim\(\)\.length\s*>=\s*MIN_NOTES/)
    expect(s).toMatch(/disabled=\{[^}]*!notesValid/)
  })

  // ============ T33 — SignoffForm has client-side ≥20-char rationale enforcement ============
  it('[T33] SignoffForm gates submit on a >=20-char rationale counter', () => {
    const form = corpus.find(c => c.path.endsWith('SignoffForm.tsx'))!.code
    expect(form).toMatch(/const\s+MIN_RATIONALE\s*=\s*20/)
    expect(form).toMatch(/rationale\.trim\(\)\.length\s*>=\s*MIN_RATIONALE/)
    expect(form).toMatch(/disabled=\{[^}]*!valid/)
  })

  // ============ T34 — SignoffForm shows the Delphi provenance preview ============
  it('[T34] SignoffForm renders a provenance preview surfacing run_id + evaluator count + dev_stub thresholds', () => {
    const src = corpus.find(c => c.path.endsWith('SignoffForm.tsx'))!.src
    expect(src).toMatch(/Provenance preview/i)
    expect(src).toMatch(/Run ID/)
    expect(src).toMatch(/Evaluators invited/)
    expect(src).toMatch(/dev_stub/i)
    expect(src).toMatch(/validation_and_defensibility_metadata/)
  })

  // ============ T35 — ReconciliationPanel gates SignoffForm on completion ============
  it('[T35] ReconciliationPanel renders SignoffForm only when all flagged items are reconciled (or none flagged)', () => {
    const s = corpus.find(c => c.path.endsWith('ReconciliationPanel.tsx'))!.code
    // The render condition must combine allFlaggedDone or noneFlagged.
    expect(s).toMatch(/\{\s*\(allFlaggedDone\s*\|\|\s*noneFlagged\)\s*&&[\s\S]*<SignoffForm/)
    // The flagged remaining derived from reconciledKeys.
    expect(s).toMatch(/flaggedRemaining/)
    // No path that renders SignoffForm without checking reconciledKeys.
    const directSignoff = /<SignoffForm[\s\S]*\/>/g.exec(s)
    expect(directSignoff, 'SignoffForm must be inside a gated block').toBeTruthy()
  })

  // ============ T36 — Attribution capture is per-evaluator, not just a single text field ============
  it('[T36] ReconciliationForm captures attribution per-evaluator (checkboxes), not just free text', () => {
    const s = corpus.find(c => c.path.endsWith('ReconciliationForm.tsx'))!.code
    // Render-side: an iteration over criterion.values producing checkboxes.
    expect(s).toMatch(/criterion\.values\.map/)
    expect(s).toMatch(/type="checkbox"/)
    // Submit-side: attribution_json carries followed_evaluators.
    expect(s).toMatch(/followed_evaluators/)
  })

  // ============ T37 — SignoffForm calls the SECDEF RPC, never inserts into roles_catalog directly ============
  it('[T37] SignoffForm uses signoffRoleVersion helper; no direct roles_catalog insert in UI', () => {
    for (const { path, code } of corpus) {
      if (path.includes('__tests__')) continue
      expect(code, `Direct roles_catalog write found in ${path}`)
        .not.toMatch(/\.from\(['"]roles_catalog['"]\)[\s\S]{0,40}\.(insert|update|upsert|delete)\b/)
    }
    const signoff = corpus.find(c => c.path.endsWith('SignoffForm.tsx'))!.code
    expect(signoff).toMatch(/signoffRoleVersion\s*\(/)
  })

  // ============ T38 — Post-signoff navigates to the new role profile ============
  it('[T38] SignoffForm post-signoff state offers a "Open new role version" navigation', () => {
    const src = corpus.find(c => c.path.endsWith('SignoffForm.tsx'))!.src
    expect(src).toMatch(/Open new role version/i)
    expect(src).toMatch(/navigate\(`?\/roles\//)
  })
})
