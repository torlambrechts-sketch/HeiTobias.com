import { useEffect, useState } from 'react'
import { AlertTriangle, X } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'

// Persistent banner when the signed-in user's primary org is a demo
// org (is_demo_data=true). Sits at the very top of the app so a
// customer reading audit history can never confuse demo data for live.
// Dismissable on the current tab only — re-appears on reload.
export function DemoBanner() {
  const supabase = browserSupabase()
  const [demoOrg, setDemoOrg] = useState<{ name: string } | null>(null)
  const [dismissed, setDismissed] = useState(false)

  useEffect(() => {
    void (async () => {
      const { data: sess } = await supabase.auth.getSession()
      const authId = sess.session?.user?.id
      if (!authId) return
      const { data: p } = await supabase.from('people').select('id').eq('auth_user_id', authId).maybeSingle()
      const pid = (p as { id: string } | null)?.id
      if (!pid) return
      const { data: m } = await supabase
        .from('memberships')
        .select('org_id, status, organizations:organizations(name, is_demo_data)')
        .eq('person_id', pid)
        .eq('status', 'active')
        .limit(5)
      const rows = (m as { organizations: { name: string; is_demo_data: boolean } | null }[] | null) ?? []
      const demo = rows.find(r => r.organizations?.is_demo_data)
      if (demo?.organizations) setDemoOrg({ name: demo.organizations.name })
    })()
  }, [supabase])

  if (!demoOrg || dismissed) return null
  return (
    <div data-test="demo-banner" className="bg-amber/90 text-white px-4 py-2 flex items-center gap-3 text-sm font-semibold">
      <AlertTriangle size={15} />
      <span><strong>DEMO DATA — {demoOrg.name}.</strong> Synthetic candidates and roles for demonstration only.</span>
      <a href="/demo" className="underline hover:no-underline ml-auto">Open demo overview</a>
      <button onClick={() => setDismissed(true)} aria-label="Dismiss banner" className="hover:opacity-70"><X size={14} /></button>
    </div>
  )
}
