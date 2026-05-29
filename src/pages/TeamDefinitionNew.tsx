import { useEffect, useState } from 'react'
import { LogOut } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody } from '../components/ui/card.js'
import { SetupForm } from '../components/team-definition/SetupForm.js'

// /team-def/new — the Stage 1 setup wizard. Picks the user's org via
// the FIRST membership where they have role.create (could be replaced
// by an explicit org switcher; this is sufficient for the demo).
export function TeamDefinitionNewPage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [orgId, setOrgId]       = useState<string | null>(null)

  useEffect(() => {
    void supabase.auth.getSession().then(async ({ data }) => {
      const email = data.session?.user?.email ?? null
      setSignedIn(email)
      const authUser = data.session?.user?.id
      if (!authUser) return
      const { data: p } = await supabase.from('people').select('id').eq('auth_user_id', authUser).maybeSingle()
      const pid = (p as { id: string } | null)?.id
      if (!pid) return
      const { data: m } = await supabase
        .from('memberships')
        .select('org_id, status')
        .eq('person_id', pid)
        .eq('status', 'active')
        .limit(1)
      setOrgId(((m as { org_id: string }[]) ?? [])[0]?.org_id ?? null)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>Team-based definition · new</span>}>
        <Card><CardBody>
          <p>You must sign in to start a new definition run.</p>
          <Button onClick={async () => {
            import.meta.env.DEV && (await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' }))
          }}>Sign in as Linnea (demo)</Button>
        </CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell breadcrumb={<>Hiring · Team-based definition · <strong>New run</strong></>} signedInLabel={signedIn}>
      <div className="flex flex-col gap-4">
        {orgId
          ? <SetupForm orgId={orgId} />
          : <Card><CardBody><p className="text-faint">Loading your org membership…</p></CardBody></Card>}
        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}
