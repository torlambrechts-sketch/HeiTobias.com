// Structured logger used everywhere the app needs to emit operational
// logs. Every line carries: timestamp, level, request-id, user-id (when
// known), org-id (when known), action, plus structured fields.
//
// In production: emits JSON to stdout (so the hosting platform's log
// pipeline ingests them).
// In dev: emits human-readable lines.
//
// Sentry capture: error-level lines also send to Sentry when SENTRY_DSN
// is set. The Sentry init is a no-op without DSN, so dev/CI environments
// don't need the dep.

import { env } from './env.js'

type Level = 'error' | 'warn' | 'info' | 'debug'
type Fields = Record<string, unknown>

const LEVEL_RANK: Record<Level, number> = { error: 0, warn: 1, info: 2, debug: 3 }

function shouldLog(level: Level): boolean {
  return LEVEL_RANK[level] <= LEVEL_RANK[env().logLevel]
}

let _requestIdGenerator: (() => string) | null = null
export function setRequestIdGenerator(fn: () => string): void { _requestIdGenerator = fn }

function rid(): string {
  if (_requestIdGenerator) return _requestIdGenerator()
  // Cheap fallback. Real distributed-tracing IDs come from the middleware
  // when we add server routes. The browser side uses one-per-page.
  if (typeof window !== 'undefined') {
    const w = window as unknown as { __heitobias_rid?: string }
    if (!w.__heitobias_rid) w.__heitobias_rid = randomId()
    return w.__heitobias_rid
  }
  return randomId()
}

function randomId(): string {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID()
  return Math.random().toString(36).slice(2, 14)
}

interface LogContext {
  user_id?: string
  org_id?: string
  action?: string
}
let _ambientCtx: LogContext = {}
export function withContext(ctx: LogContext): void { _ambientCtx = { ..._ambientCtx, ...ctx } }
export function clearContext(): void { _ambientCtx = {} }

function emit(level: Level, msg: string, fields?: Fields): void {
  if (!shouldLog(level)) return
  const line = {
    ts: new Date().toISOString(),
    level,
    request_id: rid(),
    ..._ambientCtx,
    msg,
    ...(fields ?? {}),
  }
  const e = env()
  if (e.isProd || e.isStaging) {
    // JSON for log pipelines
    // eslint-disable-next-line no-console
    console[level === 'debug' ? 'log' : level](JSON.stringify(line))
  } else {
    // eslint-disable-next-line no-console
    console[level === 'debug' ? 'log' : level](
      `[${line.ts}] ${level.toUpperCase().padEnd(5)} ${line.request_id.slice(0, 8)} ${msg}`,
      fields ?? '',
    )
  }
  if (level === 'error') captureToSentry(msg, fields)
}

export const log = {
  error: (msg: string, fields?: Fields) => emit('error', msg, fields),
  warn:  (msg: string, fields?: Fields) => emit('warn',  msg, fields),
  info:  (msg: string, fields?: Fields) => emit('info',  msg, fields),
  debug: (msg: string, fields?: Fields) => emit('debug', msg, fields),
}

// ─── Sentry stub ──────────────────────────────────────────────────
// Real init lands in src/lib/sentry.ts (loaded lazily so the dep doesn't
// bloat dev builds). For now this is a structural seam: if you wire
// Sentry, point its capture function here.
let _sentryCapture: ((msg: string, fields?: Fields) => void) | null = null
export function setSentryCapture(fn: (msg: string, fields?: Fields) => void): void {
  _sentryCapture = fn
}
function captureToSentry(msg: string, fields?: Fields): void {
  if (_sentryCapture) _sentryCapture(msg, fields)
}

// ─── Custom metrics ───────────────────────────────────────────────
// Counter-only metric emitter. Logs at info level so the hosting
// platform's log pipeline can ship to a metrics backend (Vercel Analytics,
// Grafana, etc.). Specific named metrics for the platform's defensibility
// alerts:
//
//   read_during_seal_count    — methodology incident; alert on >0
//   failed_rls_attempts       — auth / data-leak signal; alert on spikes
//   cross_org_bridge          — placement RPC invocations
//   consent_grant / revoke    — by purpose
//   decision_artefact_written — by action_type
//
// Usage:  metric.inc('read_during_seal_count', { run_id })
export const metric = {
  inc: (name: string, fields?: Fields) => emit('info', `metric.${name}`, { _metric: name, ...(fields ?? {}) }),
}
