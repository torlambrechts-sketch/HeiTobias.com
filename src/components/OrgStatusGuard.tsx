import { useEffect, useState, type ReactNode } from 'react'
import { AlertTriangle } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'

// Client-side suspension guard.
//
// On mount + every 60s while the app is open, calls
// current_user_org_status(). If the result is 'suspended' or 'archived',
// signs the user out and shows a static "your organisation is suspended"
// screen. Cannot bypass by reloading — sign-in immediately re-checks.
//
// This is defense-in-depth on top of:
//   * The DB-level CHECK that consequential RPCs apply (each SECDEF RPC
//     gating placements / sign-offs etc. checks the org status).
//   * The login flow itself (no Supabase-level integration yet; the
//     check happens on the first authenticated render).
//
// Not bullet-proof — a determined attacker with a token can still
// query Supabase directly until their access is revoked at the
// service-role level. That belongs in the operator runbook, not in a
// client component. What this delivers is: the normal user experience
// of a suspended org is "you are immediately signed out and told why."

const POLL_MS = 60_000

export function OrgStatusGuard({ children }: { children: ReactNode }) {
  const supabase = browserSupabase()
  const [state, setState] = useState<'ok' | 'suspended' | 'archived'>('ok')

  useEffect(() => {
    let cancelled = false

    const check = async () => {
      // Skip when there is no session — anonymous flows are fine.
      const { data: sess } = await supabase.auth.getSession()
      if (!sess.session) return
      const { data, error } = await supabase.rpc('current_user_org_status' as never)
      if (cancelled || error) return
      const status = (data ?? 'active') as string
      if (status === 'suspended') {
        await supabase.auth.signOut()
        setState('suspended')
      } else if (status === 'archived') {
        await supabase.auth.signOut()
        setState('archived')
      }
    }

    void check()
    const id = window.setInterval(() => { void check() }, POLL_MS)
    const { data: sub } = supabase.auth.onAuthStateChange(() => { void check() })
    return () => { cancelled = true; window.clearInterval(id); sub.subscription.unsubscribe() }
  }, [supabase])

  if (state !== 'ok') {
    return (
      <main className="min-h-screen flex items-center justify-center px-4 bg-canvas" role="alert">
        <div className="max-w-md text-center">
          <div className="w-14 h-14 mx-auto rounded-full bg-reject-bg flex items-center justify-center mb-3">
            <AlertTriangle size={24} className="text-rust" aria-hidden />
          </div>
          <h1 className="font-display text-2xl font-bold text-ink mb-2">
            {state === 'suspended' ? 'Organisation suspended' : 'Organisation archived'}
          </h1>
          <p className="text-sm text-muted leading-relaxed mb-4">
            Your organisation's access to HeiTobias is currently{' '}
            {state === 'suspended' ? 'paused' : 'archived'}. Contact your organisation
            administrator for details. If you reach the administrator and they cannot
            reactivate, the platform owner is the point of escalation.
          </p>
          <p className="text-xs text-faint">
            Your data is preserved and not deleted. When access is restored you can sign
            back in from the same address.
          </p>
        </div>
      </main>
    )
  }

  return <>{children}</>
}
