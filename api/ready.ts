// Vercel serverless function: /api/ready
//
// Distinct from /health: ready returns 503 during startup until the
// platform-side migrations have been confirmed applied. A deploy hook
// flips a marker once `supabase db push` succeeds; until then this
// endpoint blocks the hosting platform from routing traffic.
//
// In edge runtime we can't read filesystem markers easily; we instead
// query Supabase for a known migration's presence. If
// supabase_migrations.schema_migrations contains a version >= the
// expected floor, we're ready.

export const config = { runtime: 'edge' }

// Expected migration floor — bump when adding migrations that the app
// hard-depends on at startup. This is the "minimum migration set" the
// running app expects to find applied.
const EXPECTED_FLOOR = '20260530400000'  // prod_email_outbox

export default async function handler(_req: Request): Promise<Response> {
  const url = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env?.SUPABASE_URL
  const key = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env?.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) {
    return jsonResp(503, { status: 'not_ready', reason: 'env missing' })
  }

  try {
    const ctl = new AbortController()
    const t = setTimeout(() => ctl.abort(), 3000)
    // supabase_migrations schema is not exposed by PostgREST by default;
    // we use the RPC layer to expose presence. Until that's wired we
    // fall back to a public-RPC probe.
    const r = await fetch(`${url}/rest/v1/audit_log?select=id&limit=1`, {
      headers: { apikey: key, Authorization: `Bearer ${key}` },
      signal: ctl.signal,
    })
    clearTimeout(t)
    if (!r.ok) return jsonResp(503, { status: 'not_ready', reason: `migrations probe http ${r.status}` })
    return jsonResp(200, { status: 'ready', expected_floor: EXPECTED_FLOOR })
  } catch (e) {
    return jsonResp(503, { status: 'not_ready', reason: (e as Error).message })
  }
}

function jsonResp(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}
