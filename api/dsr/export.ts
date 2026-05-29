// Vercel edge function: POST /api/dsr/export
//
// GDPR Article 15: the data subject may obtain a copy of their personal
// data. This endpoint wraps the `dsr_export_my_data()` RPC. The caller
// must be authenticated (Supabase access token in Authorization header).
//
// We deliberately do not expose this to anon users — anyone can ask, but
// they must prove they are the data subject first. Authentication is the
// proof. The RPC is SECURITY DEFINER and reads only the caller's own rows
// (gated by current_person_id() inside the function); the worst a leaked
// token can do is export the data of the token's owner, which is exactly
// who Article 15 permits.
//
// Audit: the RPC writes a `dsr.export_my_data` audit_log entry. The HTTP
// layer adds nothing the RPC doesn't already record.
//
// Returns 200 with a JSON body containing the export bundle, or 401 / 5xx
// on failure. The body is `Content-Type: application/json` and not cached.

export const config = { runtime: 'edge' }

interface EnvLike {
  process?: { env?: Record<string, string | undefined> }
}

function env(key: string): string | undefined {
  return (globalThis as EnvLike).process?.env?.[key]
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', Allow: 'POST' },
    })
  }

  const auth = req.headers.get('authorization') ?? ''
  if (!/^Bearer\s+\S+/i.test(auth)) {
    return new Response(JSON.stringify({ error: 'unauthenticated' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    })
  }

  const url = env('SUPABASE_URL')
  const anon = env('SUPABASE_ANON_KEY')
  if (!url || !anon) {
    return new Response(JSON.stringify({ error: 'misconfigured' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    })
  }

  try {
    const r = await fetch(`${url}/rest/v1/rpc/dsr_export_my_data`, {
      method: 'POST',
      headers: {
        apikey: anon,
        Authorization: auth,
        'Content-Type': 'application/json',
      },
      body: '{}',
    })
    const body = await r.text()
    return new Response(body, {
      status: r.status,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
        'Content-Disposition': 'attachment; filename="personal-data-export.json"',
      },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: 'rpc_failed', detail: (e as Error).message }), {
      status: 502,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    })
  }
}
