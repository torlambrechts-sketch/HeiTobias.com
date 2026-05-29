// CSRF token helper. Supabase Auth uses bearer tokens (cookieless), so
// classical CSRF doesn't apply to the SECDEF RPC layer. BUT — any
// future state-changing route we add (DSR endpoints, webhook receivers)
// must carry a CSRF token if it accepts cookie auth. This helper exists
// so we have one place for the policy when those land.
//
// The implementation:
//   * Generates a per-session token stored in sessionStorage (browser)
//   * Exposes a fetch-wrapper that adds X-CSRF-Token header to non-GET
//   * Server-side validates against the env CSRF_SECRET (when wired)

const STORAGE_KEY = 'heitobias.csrf'

function rand(): string {
  const a = new Uint8Array(32)
  if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
    crypto.getRandomValues(a)
  } else {
    for (let i = 0; i < a.length; i++) a[i] = Math.floor(Math.random() * 256)
  }
  return Array.from(a, b => b.toString(16).padStart(2, '0')).join('')
}

export function getCsrfToken(): string {
  try {
    const existing = window.sessionStorage.getItem(STORAGE_KEY)
    if (existing) return existing
    const t = rand()
    window.sessionStorage.setItem(STORAGE_KEY, t)
    return t
  } catch {
    // SSR / non-browser: ephemeral per-call (caller should not rely on
    // server-side CSRF without a real cookie/session backing).
    return rand()
  }
}

// Wraps fetch to add the CSRF header on state-changing methods.
// Use this anywhere we add a real REST endpoint (DSR export/delete,
// webhook receivers, etc.).
export async function csrfFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const method = (init?.method ?? 'GET').toUpperCase()
  const needsToken = method !== 'GET' && method !== 'HEAD' && method !== 'OPTIONS'
  if (!needsToken) return fetch(input, init)
  const headers = new Headers(init?.headers)
  headers.set('X-CSRF-Token', getCsrfToken())
  return fetch(input, { ...init, headers, credentials: 'same-origin' })
}
