import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs'
import { execSync } from 'node:child_process'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it, expect, beforeAll } from 'vitest'

const __filename = fileURLToPath(import.meta.url)
const here = dirname(__filename)
const PROJECT_ROOT = join(here, '..', '..', '..')
const APP_TSX = join(PROJECT_ROOT, 'src', 'App.tsx')
const DIST    = join(PROJECT_ROOT, 'dist')

// CP6 — code splitting. Vite's Rollup produces one chunk per dynamic
// import boundary; route-level React.lazy is the cheap, mechanical way
// to get the main chunk under the 500 kB warning threshold. These tests
// freeze the boundary so a future refactor that goes back to eager
// imports trips a red flag.
//
// We let the test KICK A BUILD if no dist/ exists. That's slow (~4s)
// but means the test catches real regressions on a fresh checkout.

const LAZY_ROUTES = [
  'PeoplePage',
  'CandidateTakePage',
  'CandidateConsentsPage',
  'RecruiterRequisitionPage',
  'EmployerActivationsPage',
  'ManagerEmployeeDetailPage',
  'ModelingAdminPage',
  'WorkspaceAdminPage',
  'AcceptInvitePage',
  'RoleProfilePage',
  'TeamDefinitionListPage',
  'TeamDefinitionNewPage',
  'TeamDefinitionRunPage',
]

describe('CP6 — Route-level code splitting', () => {
  // ============ T71 — App.tsx lazy-loads heavy routes ============
  it('[T71] App.tsx wraps every non-home route in lazy()', () => {
    const app = readFileSync(APP_TSX, 'utf8')
    expect(app).toMatch(/import\s*\{[^}]*\blazy\b[^}]*\bSuspense\b/)
    for (const name of LAZY_ROUTES) {
      const re = new RegExp(`const\\s+${name}\\s*=\\s*lazy\\(`)
      expect(re.test(app), `${name} must be lazy()-loaded`).toBe(true)
    }
    // Suspense wraps the Routes.
    expect(app).toMatch(/<Suspense[\s\S]*<Routes>/)
  })

  // ============ T72 — Home stays eager (it's the landing) ============
  it('[T72] HomePage stays eager (landing entry — no first-paint penalty)', () => {
    const app = readFileSync(APP_TSX, 'utf8')
    expect(app).toMatch(/import\s*\{\s*HomePage\s*\}\s*from\s*['"]\.\/pages\/Home\.js['"]/)
    expect(app).not.toMatch(/const\s+HomePage\s*=\s*lazy\(/)
  })

  // ============ T73 — dist/ has split chunks (build evidence) ============
  beforeAll(() => {
    if (!existsSync(DIST)) {
      // Kick a build so the test has artefacts to inspect on a fresh
      // checkout. ~4s; acceptable for a structural test that runs once.
      execSync('npm run build', { cwd: PROJECT_ROOT, stdio: 'pipe' })
    }
  })

  it('[T73] dist/assets contains a per-route chunk for every lazy() boundary', () => {
    const assetsDir = join(DIST, 'assets')
    expect(existsSync(assetsDir), 'dist/assets must exist after build').toBe(true)
    const files = readdirSync(assetsDir)
    // Each route should produce a file named like RouteName-<hash>.js.
    const routeNamesInChunks = LAZY_ROUTES.map(name => name.replace(/Page$/, ''))
    for (const route of routeNamesInChunks) {
      const re = new RegExp(`^${route}-[A-Za-z0-9_-]+\\.js$`)
      const matched = files.some(f => re.test(f))
      expect(matched, `dist/assets must contain a chunk matching ${re}`).toBe(true)
    }
  })

  // ============ T74 — Main entry chunk under 500 kB warning ============
  it('[T74] Main entry chunk (index-*.js) is under the 500 kB rollup warning', () => {
    const assetsDir = join(DIST, 'assets')
    const files = readdirSync(assetsDir)
    const main = files.find(f => /^index-[A-Za-z0-9_-]+\.js$/.test(f))
    expect(main, 'main entry chunk index-*.js must exist').toBeTruthy()
    const sizeKb = statSync(join(assetsDir, main!)).size / 1024
    expect(sizeKb).toBeLessThan(500)
  })
})
