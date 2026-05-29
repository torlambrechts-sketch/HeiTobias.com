import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Briefcase, ChevronRight, Loader2, LogOut, Plus } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'
import { formatStage, type TeamDefinitionStage } from '../lib/teamDefinition.js'

// /team-def — list of all team-based-definition runs the caller can see.
// The query is org-scoped by RLS (team_def_runs_select policy requires
// role.read in the run's org), so we just SELECT *.

type RunListRow = {
  id: string
  org_id: string
  role_family: string
  purpose: 'initial_definition' | 'evolution_revision' | 'periodic_review'
  stage: TeamDefinitionStage
  deadline_at: string
  starts_at: string
  completed_at: string | null
  target_role_version_id: string | null
}

export function TeamDefinitionListPage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [runs, setRuns]         = useState<RunListRow[] | undefined>(undefined)
  const [err, setErr]           = useState<string | null>(null)

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  useEffect(() => {
    if (!signedIn) return
    void (async () => {
      const { data, error } = await supabase
        .from('team_definition_runs' as never)
        .select('id, org_id, role_family, purpose, stage, deadline_at, starts_at, completed_at, target_role_version_id')
        .order('starts_at', { ascending: false })
      if (error) setErr(error.message)
      else setRuns((data ?? []) as unknown as RunListRow[])
    })()
  }, [supabase, signedIn])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>Team-based definition</span>}>
        <Card><CardBody>
          <p>You must sign in to view team-based definition runs.</p>
          <Button onClick={async () => {
            await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' })
          }}>Sign in as Linnea (demo)</Button>
        </CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell breadcrumb={<>Hiring · <strong>Team-based definition</strong></>} signedInLabel={signedIn}>
      <div className="flex flex-col gap-4">
        <div className="flex items-end justify-between gap-4 flex-wrap pb-3 border-b border-line">
          <div>
            <h1 className="font-display text-3xl font-bold tracking-tight">Team-based definition</h1>
            <p className="text-muted text-sm mt-1 max-w-2xl">
              Delphi-style independent rating for role definitions. Multiple evaluators rate
              the role independently; the system surfaces divergence rather than averaging it
              away. The signed-off output is a new role version with full provenance attached.
              <span className="block text-xs font-mono text-faint mt-1">SCIENCE-SPEC §7; Linstone &amp; Turoff (1975)</span>
            </p>
          </div>
          <Link to="/team-def/new">
            <Button><Plus size={14} /> Start a new run</Button>
          </Link>
        </div>

        {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust">{err}</div>}

        {runs === undefined && (
          <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading runs…</div>
        )}

        {runs && runs.length === 0 && (
          <Card><CardBody className="text-center py-12">
            <Briefcase size={28} className="text-faint mx-auto mb-3" />
            <h2 className="font-display text-xl font-semibold mb-1">No runs yet</h2>
            <p className="text-muted text-sm mb-4 max-w-md mx-auto">
              Start your first team-based definition run. Invite 4+ evaluators with role-balanced
              representation; each rates the role independently before the seal.
            </p>
            <Link to="/team-def/new">
              <Button><Plus size={14} /> Start a new run</Button>
            </Link>
          </CardBody></Card>
        )}

        {runs && runs.length > 0 && (
          <div className="flex flex-col gap-2">
            {runs.map(r => {
              const stage = formatStage(r.stage)
              return (
                <Link key={r.id} to={`/team-def/runs/${r.id}`}>
                  <Card className="hover:bg-canvas-2 transition-colors cursor-pointer">
                    <CardBody className="flex items-center gap-4">
                      <div className="flex-1 min-w-0">
                        <div className="text-sm font-semibold text-ink">{r.role_family}</div>
                        <div className="text-xs text-muted mt-0.5 flex items-center gap-2 flex-wrap">
                          <span className="font-mono">run #{r.id.slice(0, 8)}</span>
                          <span className="text-faint">·</span>
                          <span>{r.purpose.replace('_', ' ')}</span>
                          <span className="text-faint">·</span>
                          <span>Started {new Date(r.starts_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })}</span>
                          {r.completed_at && <>
                            <span className="text-faint">·</span>
                            <span className="text-green">Completed {new Date(r.completed_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })}</span>
                          </>}
                        </div>
                      </div>
                      <Pill tone={stageTone(r.stage)}>
                        Stage {stage.num} · {stage.label}
                      </Pill>
                      <ChevronRight size={16} className="text-faint" />
                    </CardBody>
                  </Card>
                </Link>
              )
            })}
          </div>
        )}

        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}

function stageTone(stage: TeamDefinitionStage): 'open' | 'draft' | 'internal' | 'reject' | 'interview' | 'offer' {
  switch (stage) {
    case 'setup':          return 'draft'
    case 'rating':         return 'interview'
    case 'divergence':     return 'internal'
    case 'reconciliation': return 'internal'
    case 'signed_off':     return 'open'
    case 'abandoned':      return 'reject'
  }
}
