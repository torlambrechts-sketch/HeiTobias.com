// Vercel edge function: POST /api/dsr/request
//
// Opens a Data Subject Request ledger row. Body shape:
//
//   { "kind": "export" | "erase", "org_id": "<uuid|null>" }
//
// Behaviour:
//   * Calls `dsr_open(p_kind, p_org_id)` with the caller's token.
//   * The RPC enforces authentication and writes the audit_log entry.
//   * 'erase' requests are queued; fulfilment is privileged operator
//     work (see dsr_fulfil RPC + docs/RETENTION.md).
//
// Returns 200 with `{ request_id }` on success.
//
// Why we keep this thin: the database is the system of record. The HTTP
// layer's job is to forward an authenticated POST to the right RPC and
// surface its error verbatim. No business logic in the edge function.

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

  let payload: { kind?: string; org_id?: string | null } = {}
  try {
    payload = await req.json() as typeof payload
  } catch {
    return new Response(JSON.stringify({ error: 'invalid_json' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    })
  }
  if (payload.kind !== 'export' && payload.kind !== 'erase') {
    return new Response(JSON.stringify({ error: 'invalid_kind', detail: 'expected "export" or "erase"' }), {
      status: 400,
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
    const r = await fetch(`${url}/rest/v1/rpc/dsr_open`, {
      method: 'POST',
      headers: {
        apikey: anon,
        Authorization: auth,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_kind: payload.kind, p_org_id: payload.org_id ?? null }),
    })
    const body = await r.text()
    return new Response(
      r.ok ? JSON.stringify({ request_id: body.replace(/^"|"$/g, '') }) : body,
      {
        status: r.status,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
      }
    )
  } catch (e) {
    return new Response(JSON.stringify({ error: 'rpc_failed', detail: (e as Error).message }), {
      status: 502,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    })
  }
}
