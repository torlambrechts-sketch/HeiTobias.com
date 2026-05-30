// Vercel edge function: POST /api/dsr/unauth
//
// Unauthenticated data-subject-request intake for people with no active
// account (former candidates, etc.). GDPR Art. 15 / 17 still apply to
// them.
//
// Flow (the RPCs do the work; this layer forwards + would email the link):
//   action=open   { email, kind }      → mints a verify token; in prod the
//                                         token is emailed as a magic link,
//                                         NEVER returned to the caller.
//   action=verify { token }            → marks the request verified.
//   action=summary{ token }            → post-verify, returns what's held.
//
// Existence-leak discipline: `open` always returns the same body whether
// or not the email matches a person. Only after the requester proves they
// own the email (the magic link) does `summary` reveal anything.
//
// In this build SMTP is operator-wired (see docs/). Until then, in a
// non-production environment, `open` echoes the token so the flow is
// testable; in production it never does.

export const config = { runtime: 'edge' }

interface EnvLike { process?: { env?: Record<string, string | undefined> } }
function env(key: string): string | undefined {
  return (globalThis as EnvLike).process?.env?.[key]
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const url = env('SUPABASE_URL')
  const anon = env('SUPABASE_ANON_KEY')
  if (!url || !anon) return json({ error: 'misconfigured' }, 500)

  let body: { action?: string; email?: string; kind?: string; token?: string } = {}
  try { body = await req.json() as typeof body } catch { return json({ error: 'invalid_json' }, 400) }

  const isProd = (env('NODE_ENV') ?? env('VERCEL_ENV')) === 'production'

  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const r = await fetch(`${url}/rest/v1/rpc/${fn}`, {
      method: 'POST',
      headers: { apikey: anon, Authorization: `Bearer ${anon}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(args),
    })
    return { ok: r.ok, status: r.status, text: await r.text() }
  }

  if (body.action === 'open') {
    if (!body.email) return json({ error: 'email_required' }, 400)
    const r = await rpc('dsr_unauth_open', { p_email: body.email, p_kind: body.kind ?? 'export' })
    if (!r.ok) return json({ error: 'rpc_failed', detail: r.text }, 502)
    let parsed: { verify_token?: string; message?: string } = {}
    try { parsed = JSON.parse(r.text) as typeof parsed } catch { /* keep */ }
    // In production, NEVER return the token — it's emailed. The user
    // sees only the neutral message (no existence leak).
    if (isProd) {
      return json({ ok: true, message: parsed.message ?? 'If this email is associated with data, a verification link has been sent.' })
    }
    // Non-prod: echo the token so the flow is walkable without SMTP.
    return json({ ok: true, message: parsed.message, dev_verify_token: parsed.verify_token })
  }

  if (body.action === 'verify') {
    if (!body.token) return json({ error: 'token_required' }, 400)
    const r = await rpc('dsr_unauth_verify', { p_token: body.token })
    return new Response(r.text, { status: r.ok ? 200 : 502, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
  }

  if (body.action === 'summary') {
    if (!body.token) return json({ error: 'token_required' }, 400)
    const r = await rpc('dsr_unauth_summary', { p_token: body.token })
    return new Response(r.text, { status: r.ok ? 200 : 502, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
  }

  return json({ error: 'unknown_action' }, 400)
}
