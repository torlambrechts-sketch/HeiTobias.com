// Environment helper used by every file that needs to know runtime mode.
// One place to read NODE_ENV / Vite mode / production-vs-staging — no
// scattered `process.env.NODE_ENV === 'production'` checks.
//
// Server-side (Node — seed scripts, SQL test runner) uses process.env.
// Browser-side (Vite-bundled) uses import.meta.env. Both code paths
// produce the same Env interface.

type Mode = 'development' | 'staging' | 'production' | 'test'

export interface Env {
  mode: Mode
  isProd: boolean
  isStaging: boolean
  isDev: boolean
  isTest: boolean
  seedDemoData: boolean
  logLevel: 'error' | 'warn' | 'info' | 'debug'
  appUrl: string
}

function fromString(v: string | undefined, fallback: Mode = 'development'): Mode {
  if (v === 'production' || v === 'staging' || v === 'development' || v === 'test') return v
  return fallback
}

// Read once per process. The browser-side and Node-side both call this;
// the file is module-scoped so re-imports are cheap.
function read(): Env {
  // Browser (Vite bundles import.meta.env at build time)
  if (typeof import.meta !== 'undefined' && import.meta.env) {
    const v = import.meta.env as Record<string, string | boolean | undefined>
    const mode = fromString(
      (v.MODE as string) ?? (v.NODE_ENV as string),
      v.PROD ? 'production' : v.DEV ? 'development' : 'development',
    )
    return {
      mode,
      isProd:    mode === 'production',
      isStaging: mode === 'staging',
      isDev:     mode === 'development',
      isTest:    mode === 'test',
      seedDemoData: String(v.VITE_SEED_DEMO_DATA ?? 'false').toLowerCase() === 'true',
      logLevel: ((v.VITE_LOG_LEVEL as string) ?? 'info') as Env['logLevel'],
      appUrl: (v.VITE_APP_URL as string) ?? 'http://localhost:5173',
    }
  }
  // Node
  const p = (typeof process !== 'undefined' ? process.env : {}) as Record<string, string | undefined>
  const mode = fromString(p.NODE_ENV)
  return {
    mode,
    isProd:    mode === 'production',
    isStaging: mode === 'staging',
    isDev:     mode === 'development',
    isTest:    mode === 'test',
    seedDemoData: String(p.SEED_DEMO_DATA ?? 'false').toLowerCase() === 'true',
    logLevel: ((p.LOG_LEVEL ?? 'info') as Env['logLevel']),
    appUrl: p.APP_URL ?? 'http://localhost:5173',
  }
}

let cached: Env | null = null
export function env(): Env {
  if (!cached) cached = read()
  return cached
}

// Reset for tests
export function _resetEnv(): void { cached = null }
