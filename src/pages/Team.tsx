import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Loader2, LogOut, Users } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'

// /team — manager workspace minimum. Lists members of the signed-in
// user's orgs (proxy for direct reports until reporting_relationships
// is wired). Each row links to the existing ManagerEmployeeDetail
// surface at /employees/:id.
//
// SURVEILLANCE GUARDRAIL: the per-row signals (re-fit / pulse) are
// derived from each person's OWN profile, never from peer rating.
// The detail surface displays the existing CLAUDE.md §5 stub seam.
type TeamMember = { person_id: string; full_name: string | null; primary_email: string | null; org_id: string; org_name: string }

export function TeamPage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [team, setTeam] = useState<TeamMember[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  useEffect(() => {
    if (!signedIn) return
    void (async () => {
      const { data, error } = await supabase.rpc('rpc_my_team' as never)
      if (!error) setTeam(((data ?? []) as unknown as TeamMember[]))
      setLoading(false)
    })()
  }, [supabase, signedIn])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>Team</span>}>
        <Card><CardBody><p>You must sign in to view your team.</p>
          <Button onClick={async () => await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' })}>Sign in (demo)</Button>
        </CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell breadcrumb={<>People · <strong>Team</strong></>} signedInLabel={signedIn}>
      <div className="flex flex-col gap-4">
        <div className="flex items-end justify-between pb-3 border-b border-line">
          <div>
            <h1 className="font-display text-3xl font-bold tracking-tight">My team</h1>
            <p className="text-muted text-sm mt-1 max-w-2xl">
              Members of your org. The detail view surfaces each person's OWN profile —
              re-fit + pulse + growth conversations. Team composition signals are derived
              from <strong>members' own validated profiles</strong>, never from peer rating
              <span className="text-xs font-mono ml-1">(SCIENCE-SPEC §7)</span>.
            </p>
          </div>
        </div>

        {/* Surveillance guardrail — visible body copy, never tooltip */}
        <div className="rounded border border-rust border-l-4 border-l-rust bg-reject-bg p-4 flex items-start gap-3 text-sm leading-relaxed">
          <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-1 rounded bg-white text-rust border border-rust/30 flex-shrink-0">Guardrail</span>
          <div className="text-ink/90">
            This page lets you OPEN team-member profiles to coach them. <strong>It does NOT let you rate them.</strong>
            Personality + re-fit signals come from each member's own profile, gated by their active
            <code className="font-mono text-xs bg-white/60 px-1 rounded mx-1">ongoing_management</code> consent.
          </div>
        </div>

        {loading && <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>}

        {!loading && team.length === 0 && (
          <Card><CardBody className="text-center py-8">
            <Users size={28} className="text-faint mx-auto mb-3" />
            <p className="text-faint text-sm">No team members visible at your scope.</p>
          </CardBody></Card>
        )}

        <ul className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {team.map(t => (
            <li key={t.person_id}>
              <Link to={`/employees/${t.person_id}`} className="block">
                <Card className="hover:shadow-soft transition-shadow cursor-pointer">
                  <CardBody>
                    <div className="font-semibold text-sm">{t.full_name}</div>
                    <div className="text-xs text-muted mt-0.5 truncate">{t.primary_email}</div>
                    <div className="flex items-center gap-2 mt-2">
                      <Pill tone="open">active</Pill>
                      <Pill tone="internal">developmental framing</Pill>
                    </div>
                  </CardBody>
                </Card>
              </Link>
            </li>
          ))}
        </ul>

        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}
