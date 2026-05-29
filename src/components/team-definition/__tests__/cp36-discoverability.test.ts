import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it, expect } from 'vitest'

const __filename = fileURLToPath(import.meta.url)
const here = dirname(__filename)
const SRC = join(here, '..', '..', '..')

// CP3.6 — discoverability of the team-based-definition module.
// The schema + RPCs + per-stage UI all work, but unless a user can find
// the module from the Shell + from a role profile, it might as well not
// exist. These tests freeze the entry points into the test suite so
// future work doesn't silently unwire them.

describe('CP3.6 — Team-Based Role Definition discoverability', () => {
  // ============ T46 — Shell nav points to /team-def ============
  it('[T46] Shell nav "Team-based definition" links to /team-def (not the # placeholder)', () => {
    const shell = readFileSync(join(SRC, 'components', 'Shell.tsx'), 'utf8')
    expect(shell).toMatch(/<NavSub\s+to="\/team-def"\s*>\s*Team-based definition/)
    // The previous placeholder is gone — no more <NavSub to="#">Team-based definition.
    expect(shell).not.toMatch(/<NavSub\s+to="#"\s*>\s*Team-based definition/)
  })

  // ============ T47 — All three team-def routes wired (now ModuleGate-wrapped) ============
  it('[T47] App.tsx wires /team-def, /team-def/new, /team-def/runs/:id (gated by ModuleGate)', () => {
    const app = readFileSync(join(SRC, 'App.tsx'), 'utf8')
    expect(app).toMatch(/path="\/team-def"\s+element=\{<ModuleGate[^>]*><TeamDefinitionListPage/)
    expect(app).toMatch(/path="\/team-def\/new"\s+element=\{<ModuleGate[^>]*><TeamDefinitionNewPage/)
    expect(app).toMatch(/path="\/team-def\/runs\/:id"\s+element=\{<ModuleGate[^>]*><TeamDefinitionRunPage/)
  })

  // ============ T48 — RoleProfile PageHeader exposes the CTA ============
  it('[T48] Role profile page header offers "Start team-based revision" → /team-def/new', () => {
    const ph = readFileSync(join(SRC, 'components', 'role-profile', 'PageHeader.tsx'), 'utf8')
    expect(ph).toMatch(/Start team-based revision/)
    expect(ph).toMatch(/to="\/team-def\/new"/)
    // CTA must be gated on role.create — same gate as other write actions.
    expect(ph).toMatch(/disabled=\{!canEdit\}/)
  })

  // ============ T49 — Empty state has its own "Start a new run" CTA ============
  it('[T49] TeamDefinitionList empty state offers a primary CTA, not a dead-end message', () => {
    const list = readFileSync(join(SRC, 'pages', 'TeamDefinitionList.tsx'), 'utf8')
    expect(list).toMatch(/No runs yet/i)
    // Empty state contains a Link to /team-def/new with a Button.
    expect(list).toMatch(/<Link[\s\S]{0,40}to="\/team-def\/new"[\s\S]{0,200}<Button>[\s\S]{0,40}Start a new run/)
  })

  // ============ T50 — List page is org-scoped by RLS, not by client filter ============
  it('[T50] TeamDefinitionList does NOT filter by org client-side (RLS handles it)', () => {
    const list = readFileSync(join(SRC, 'pages', 'TeamDefinitionList.tsx'), 'utf8')
    // We rely on the team_def_runs_select policy which requires
    // has_permission(org_id, 'role.read'). A client-side .eq('org_id', ...)
    // would be a code smell (and tempt later devs to bypass RLS).
    expect(list).not.toMatch(/\.eq\(['"]org_id['"]/)
  })
})
