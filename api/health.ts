// Vercel serverless function: /api/health
//
// Returns the operational health of the platform for uptime monitors
// and the hosting platform's health check. Touch points:
//   * Supabase connectivity (anon-key auth probe)
//   * Env presence (no values exposed; presence only)
//
// SMTP connectivity is not probed here (each provider has its own
// liveness API; the cost of probing on every health check isn't worth
// it). The notifications outbox + email_mark feedback loop catches
// real send failures.
//
// Returns 200 when healthy, 503 otherwise. No PII in the body.

interface HealthBody {
  status: 'ok' | 'degraded' | 'down'
  ts: string
  checks: Record<string, { ok: boolean; msg?: string }>
}

export const config = { runtime: 'edge' }

export default async function handler(_req: Request): Promise<Response> {
  const checks: HealthBody['checks'] = {}

  // Env presence (production-required only)
  const REQUIRED = ['SUPABASE_URL', 'SUPABASE_ANON_KEY']
  for (const k of REQUIRED) {
    const v = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env?.[k]
    checks[`env.${k}`] = { ok: !!v }
  }

  // Supabase connectivity — anon GET against a known-public RPC. If the
  // platform is unreachable, this hangs / 5xxs. We bound it at 3s.
  const url = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env?.SUPABASE_URL
  const key = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env?.SUPABASE_ANON_KEY
  if (url && key) {
    try {
      const ctl = new AbortController()
      const t = setTimeout(() => ctl.abort(), 3000)
      const r = await fetch(`${url}/rest/v1/`, {
        headers: { apikey: key },
        signal: ctl.signal,
      })
      clearTimeout(t)
      checks['supabase'] = { ok: r.ok || r.status === 404, msg: `http ${r.status}` }
    } catch (e) {
      checks['supabase'] = { ok: false, msg: (e as Error).message }
    }
  } else {
    checks['supabase'] = { ok: false, msg: 'env missing' }
  }

  const allOk = Object.values(checks).every(c => c.ok)
  const body: HealthBody = {
    status: allOk ? 'ok' : 'degraded',
    ts: new Date().toISOString(),
    checks,
  }
  return new Response(JSON.stringify(body, null, 2), {
    status: allOk ? 200 : 503,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}
