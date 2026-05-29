import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it, expect } from 'vitest'

const __filename = fileURLToPath(import.meta.url)
const here = dirname(__filename)
const PAGE = join(here, '..', 'WorkspaceAdmin.tsx')
const src = readFileSync(PAGE, 'utf8')

// CP7 — Admin polish. Two rough edges in WorkspaceAdmin got resolved
// in this commit:
//   1. Audit log surfaces before/after JSON per row (compliance need)
//   2. "My profile" tab is no longer a placeholder — it wires to the
//      new i18n locale preference

describe('CP7 — WorkspaceAdmin polish', () => {
  // ============ T75 — Audit log is row-expandable ============
  it('[T75] Audit log table marker exists + rows expand to show before/after JSON', () => {
    expect(src).toMatch(/data-test="audit-log-table"/)
    expect(src).toMatch(/data-test="audit-log-detail"/)
    // Toggling adds a setOpenIdx state pattern.
    expect(src).toMatch(/setOpenIdx\(/)
    // The detail body renders both before_json and after_json.
    expect(src).toMatch(/e\.before_json/)
    expect(src).toMatch(/e\.after_json/)
  })

  // ============ T76 — AuditEvent type carries before/after fields ============
  it('[T76] AuditEvent type carries before_json + after_json + entity_id', () => {
    expect(src).toMatch(/before_json\??:\s*Record<string,\s*unknown>\s*\|\s*null/)
    expect(src).toMatch(/after_json\??:\s*Record<string,\s*unknown>\s*\|\s*null/)
    expect(src).toMatch(/entity_id\??:\s*string\s*\|\s*null/)
  })

  // ============ T77 — "My profile" tab is no longer a placeholder ============
  it('[T77] "My profile" tab no longer carries the "scaffolded; backend wiring is outside" placeholder copy', () => {
    expect(src).not.toMatch(/scaffolded; backend wiring is outside/i)
    expect(src).toMatch(/data-test="my-profile-locale"/)
  })

  // ============ T78 — "My profile" wires to i18n LOCALES + useLocale ============
  it('[T78] MyProfileTab uses useLocale + LOCALES list to drive the language selector', () => {
    expect(src).toMatch(/import\s*\{[^}]*\bLOCALES\b[^}]*\buseLocale\b/)
    expect(src).toMatch(/const\s*\{\s*locale,\s*setLocale\s*\}\s*=\s*useLocale\(\)/)
    expect(src).toMatch(/LOCALES\.map/)
  })

  // ============ T79 — "My profile" surfaces the signed-in email read-only ============
  it('[T79] MyProfileTab shows the signed-in email as a read-only field', () => {
    expect(src).toMatch(/<input[^>]*value=\{signedIn\s*\?\?\s*['"]{2}\}[^>]*readOnly/)
  })
})
