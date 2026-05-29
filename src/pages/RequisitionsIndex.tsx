import { useEffect, useState } from 'react'
import { Link, Navigate } from 'react-router-dom'
import { AlertCircle, Loader2, LogOut } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody } from '../components/ui/card.js'

// /requisitions — resolves to the first requisition the signed-in user
// can see (RLS-scoped). The Shell used to hardcode a specific UUID,
// which was a dead-end for any user not in the owning org. This
// resolver makes the Shell link work for every seeded persona.

export function RequisitionsIndexPage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [target, setTarget]     = useState<string | null | undefined>(undefined)

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  useEffect(() => {
    if (!signedIn) return
    void (async () => {
      const { data } = await supabase
        .from('requisitions')
        .select('id')
        .order('created_at', { ascending: false })
        .limit(1)
      const first = (data as { id: string }[] | null ?? [])[0]?.id
      setTarget(first ?? null)
    })()
  }, [supabase, signedIn])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>Requisitions</span>}>
        <Card><CardBody>
          <p>You must sign in to view requisitions.</p>
          <Button onClick={async () => {
            import.meta.env.DEV && (await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' }))
          }}>Sign in as Linnea (demo)</Button>
        </CardBody></Card>
      </Shell>
    )
  }

  if (target === undefined) {
    return (
      <Shell breadcrumb={<span>Requisitions</span>} signedInLabel={signedIn}>
        <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Finding a requisition you can see…</div>
      </Shell>
    )
  }

  if (target === null) {
    return (
      <Shell breadcrumb={<>Hiring · <strong>Requisitions</strong></>} signedInLabel={signedIn}>
        <Card><CardBody className="flex items-start gap-3">
          <AlertCircle size={18} className="text-amber flex-shrink-0 mt-0.5" />
          <div className="text-sm">
            <div className="font-semibold mb-1">No requisitions visible at your RLS scope.</div>
            <p className="text-muted leading-relaxed">
              You don't currently have <code className="font-mono">requisition.read</code> on any requisition.
              Either your org doesn't have any open yet, or you need a role with hiring permissions.
              You can start a team-based role definition first if you're scoping a role to hire for.
            </p>
            <div className="mt-3">
              <Link to="/team-def/new">
                <Button>Start a team-based role definition</Button>
              </Link>
            </div>
          </div>
        </CardBody></Card>
        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </Shell>
    )
  }

  return <Navigate to={`/requisitions/${target}`} replace />
}
