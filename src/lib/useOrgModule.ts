import { useEffect, useState } from 'react'
import { browserSupabase } from './browser-supabase.js'

// Tiny hook: returns the enabled state of `moduleKey` for the signed-in
// user's first active org. Used by <ModuleGate> to gate routes.
// Returns:
//   undefined — loading
//   true      — module enabled (or no org_modules row, default-open)
//   false     — explicitly disabled by an admin via WorkspaceAdmin Modules tab
export function useOrgModule(moduleKey: string): boolean | undefined {
  const supabase = browserSupabase()
  const [state, setState] = useState<boolean | undefined>(undefined)

  useEffect(() => {
    let live = true
    void (async () => {
      const { data: sess } = await supabase.auth.getSession()
      const authId = sess.session?.user?.id
      if (!authId) { if (live) setState(true); return }
      const { data: p } = await supabase.from('people').select('id').eq('auth_user_id', authId).maybeSingle()
      const pid = (p as { id: string } | null)?.id
      if (!pid) { if (live) setState(true); return }
      const { data: m } = await supabase
        .from('memberships').select('org_id').eq('person_id', pid).eq('status', 'active').limit(1)
      const orgId = ((m as { org_id: string }[]) ?? [])[0]?.org_id
      if (!orgId) { if (live) setState(true); return }
      const { data: om } = await supabase
        .from('org_modules').select('enabled').eq('org_id', orgId).eq('module_key', moduleKey).maybeSingle()
      const enabled = (om as { enabled: boolean } | null)?.enabled
      // Default-open: if no row, the module is on. Admins flip OFF via the toggle.
      if (live) setState(enabled === false ? false : true)
    })()
    return () => { live = false }
  }, [supabase, moduleKey])

  return state
}
