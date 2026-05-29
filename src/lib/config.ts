// Startup config validation. Called once from main.tsx (browser) and
// from scripts that need server-side env (seed:demo, test runner).
// Fails FAST with a clear list of missing variables — never a silent
// runtime crash three requests in.

import { env } from './env.js'

type Source = 'browser' | 'node'

const REQUIRED_BROWSER = [
  { key: 'VITE_SUPABASE_URL',      example: 'https://YOUR-REF.supabase.co' },
  { key: 'VITE_SUPABASE_ANON_KEY', example: '<anon key from Supabase dashboard>' },
]

const REQUIRED_NODE_BASE = [
  { key: 'SUPABASE_URL',              example: 'https://YOUR-REF.supabase.co' },
  { key: 'SUPABASE_ANON_KEY',         example: '<anon key>' },
  { key: 'SUPABASE_SERVICE_ROLE_KEY', example: '<service role key (server-side only)>' },
  { key: 'SUPABASE_DB_URL',           example: 'postgresql://postgres:...@db.<ref>.supabase.co:5432/postgres' },
]

const REQUIRED_PROD_EXTRA = [
  { key: 'APP_URL',         example: 'https://app.heitobias.com' },
  { key: 'ALLOWED_ORIGINS', example: 'https://app.heitobias.com' },
  { key: 'SMTP_PROVIDER',   example: 'postmark | sendgrid_eu | ses_eu_central_1' },
  { key: 'FROM_EMAIL',      example: 'no-reply@heitobias.com' },
  { key: 'SESSION_SECRET',  example: '<64-char random hex>' },
  { key: 'CSRF_SECRET',     example: '<64-char random hex>' },
]

function readEnvVar(key: string, source: Source): string | undefined {
  if (source === 'browser') {
    // Vite inlines VITE_-prefixed vars at build time.
    if (typeof import.meta === 'undefined' || !import.meta.env) return undefined
    const v = (import.meta.env as Record<string, string | undefined>)[key]
    return v && v.length > 0 && !v.includes('YOUR-REF') ? v : undefined
  }
  if (typeof process === 'undefined') return undefined
  const v = process.env[key]
  return v && v.length > 0 ? v : undefined
}

export type ConfigValidationResult =
  | { ok: true }
  | { ok: false; missing: { key: string; example: string }[]; source: Source }

export function validateConfig(source: Source): ConfigValidationResult {
  const e = env()
  const required = source === 'browser'
    ? [...REQUIRED_BROWSER]
    : [...REQUIRED_NODE_BASE, ...(e.isProd ? REQUIRED_PROD_EXTRA : [])]
  const missing = required.filter(r => !readEnvVar(r.key, source))
  if (missing.length === 0) return { ok: true }
  return { ok: false, missing, source }
}

export function formatValidationError(r: Exclude<ConfigValidationResult, { ok: true }>): string {
  const e = env()
  return [
    `\n========================================================`,
    ` HeiTobias config error — missing required environment vars`,
    `========================================================`,
    ` Source: ${r.source}`,
    ` Mode:   ${e.mode}`,
    ``,
    ` Missing:`,
    ...r.missing.map(m => `   • ${m.key}\n     example: ${m.example}`),
    ``,
    ` Fix:`,
    `   1. Copy .env.example to .env.local`,
    `   2. Fill in the values from your Supabase dashboard / hosting platform`,
    `   3. Restart`,
    ` `,
    ` In production these MUST live in your hosting platform's`,
    ` secret manager (Vercel project env vars / equivalent),`,
    ` NEVER in a .env file checked into git.`,
    `========================================================\n`,
  ].join('\n')
}

export function assertConfigOrThrow(source: Source): void {
  const r = validateConfig(source)
  if (!r.ok) throw new Error(formatValidationError(r))
}
