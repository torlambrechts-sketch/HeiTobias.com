import { useEffect, useState } from 'react'
import { browserSupabase } from './browser-supabase.js'

// Returns the caller's "current" org_id — defined as the org_id of the
// first active membership in created_at order. Multi-org users get the
// oldest one as their default; a future Org Switcher widget will let
// them flip it explicitly (and persist the choice). Until that ships,
// "first active membership" is the right default — it matches how
// memberships are typically issued (the user joins their first agency /
// employer org and works from there).
//
// Returns:
//   { state: 'loading' }            — initial render, still resolving
//   { state: 'unauthenticated' }    — no Supabase session
//   { state: 'no_membership' }      — signed in but no active membership
//   { state: 'ready', orgId, error: null } — happy path
//   { state: 'error', error }       — RLS or network error; orgId may be null
//
// Why a state machine instead of `string | null`: every page that
// filters by org needs to distinguish "still loading, render skeleton"
// from "logged out, show sign-in" from "no org, show empty state" from
// "loaded, filter queries". Folding all four into a nullable string
// makes those branches indistinguishable and causes the bug where a
// page momentarily renders "no data" while it's still loading.

export type CurrentOrgState =
  | { state: 'loading' }
  | { state: 'unauthenticated' }
  | { state: 'no_membership' }
  | { state: 'error'; error: string; orgId: null }
  | { state: 'ready'; orgId: string; error: null }

export function useCurrentOrgId(): CurrentOrgState {
  const supabase = browserSupabase()
  const [state, setState] = useState<CurrentOrgState>({ state: 'loading' })

  useEffect(() => {
    let live = true

    async function resolve(): Promise<CurrentOrgState> {
      const { data: sess } = await supabase.auth.getSession()
      const authId = sess.session?.user?.id
      if (!authId) return { state: 'unauthenticated' }

      const { data: p, error: pe } = await supabase
        .from('people').select('id').eq('auth_user_id', authId).maybeSingle()
      if (pe) return { state: 'error', error: pe.message, orgId: null }
      const pid = (p as { id: string } | null)?.id
      if (!pid) return { state: 'no_membership' }

      const { data: m, error: me } = await supabase
        .from('memberships').select('org_id, created_at')
        .eq('person_id', pid).eq('status', 'active')
        .order('created_at', { ascending: true }).limit(1)
      if (me) return { state: 'error', error: me.message, orgId: null }
      const row = ((m as { org_id: string }[]) ?? [])[0]
      if (!row) return { state: 'no_membership' }
      return { state: 'ready', orgId: row.org_id, error: null }
    }

    void resolve().then(next => { if (live) setState(next) })

    // Re-resolve on auth changes (sign in / sign out flips this hook
    // through the right transitions without a page reload).
    const { data: sub } = supabase.auth.onAuthStateChange(() => {
      void resolve().then(next => { if (live) setState(next) })
    })

    return () => { live = false; sub.subscription.unsubscribe() }
  }, [supabase])

  return state
}

// Convenience for pages that only care about the happy path and treat
// every other state as "render a generic 'no org' card". Most pages
// should use useCurrentOrgId() directly so they can render proper
// skeletons / sign-in prompts / empty states; this helper exists for
// the few that don't.
export function orgIdOrNull(s: CurrentOrgState): string | null {
  return s.state === 'ready' ? s.orgId : null
}
