import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { AlertCircle, Loader2, LogOut } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { fetchEvaluators, fetchRun, type EvaluatorRow, type RunRow } from '../lib/teamDefinition.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody } from '../components/ui/card.js'
import { StageStepper } from '../components/team-definition/StageStepper.js'
import { RunHeader } from '../components/team-definition/RunHeader.js'
import { RatingForm } from '../components/team-definition/RatingForm.js'
import { DivergencePanel } from '../components/team-definition/DivergencePanel.js'
import { ReconciliationPanel } from '../components/team-definition/ReconciliationPanel.js'
import { type EvaluatorWithPerson } from '../components/team-definition/EvaluatorRoster.js'

// Main run page. Renders the stepper + header, then either:
//   * Stage 1 (setup): forward to /team-def/new for first creation
//   * Stage 2 (rating): RatingForm if the caller is an invited evaluator
//   * Stage 3 (divergence): DivergencePanel (CP3.3)
//   * Stage 4 (reconciliation / signed_off): placeholder, lands CP3.4
//
// The Stage 2 view DELIBERATELY never reads other evaluators' rows —
// the schema RLS already blocks them, but the page also doesn't try.
// The audited owner-reveal path lives in DivergencePanel via
// rpc_compute_divergence (which internally walks the just-sealed rows
// as the SECDEF function owner).
export function TeamDefinitionRunPage() {
  const { id } = useParams<{ id: string }>()
  const supabase = browserSupabase()
  const [signedIn, setSignedIn]               = useState<string | null>(null)
  const [personId, setPersonId]               = useState<string | null>(null)
  const [run, setRun]                         = useState<RunRow | null | undefined>(undefined)
  const [me, setMe]                           = useState<EvaluatorRow | null>(null)
  const [evaluators, setEvaluators]           = useState<EvaluatorWithPerson[]>([])
  const [attemptedReadCount, setAttemptedReadCount] = useState<number>(0)
  const [forceStage4, setForceStage4]         = useState(false)
  const [err, setErr]                         = useState<string | null>(null)

  useEffect(() => {
    void supabase.auth.getSession().then(async ({ data }) => {
      const email = data.session?.user?.email ?? null
      setSignedIn(email)
      const authUser = data.session?.user?.id
      if (authUser) {
        const { data: p } = await supabase.from('people').select('id').eq('auth_user_id', authUser).maybeSingle()
        setPersonId((p as { id: string } | null)?.id ?? null)
      }
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  const reload = useCallback(() => {
    if (!id) return
    setRun(undefined); setErr(null)
    fetchRun(supabase, id)
      .then(async r => {
        setRun(r)
        if (!r) return
        const evs = await fetchEvaluators(supabase, r.id)
        setMe(evs.find(e => e.user_id === personId) ?? null)

        // Hydrate person names for the roster.
        const personIds = Array.from(new Set(evs.map(e => e.user_id)))
        const { data: people } = await supabase
          .from('people')
          .select('id, full_name, primary_email')
          .in('id', personIds)
        const byId = new Map<string, { full_name: string; primary_email: string }>(
          (people as { id: string; full_name: string; primary_email: string }[] | null ?? []).map(p => [p.id, p]),
        )
        const enriched: EvaluatorWithPerson[] = evs.map(e => ({
          ...e,
          full_name:     byId.get(e.user_id)?.full_name ?? null,
          primary_email: byId.get(e.user_id)?.primary_email ?? null,
        }))
        setEvaluators(enriched)

        // Count read-during-seal attempts for the SealCallout.
        const { count } = await supabase
          .from('audit_log')
          .select('*', { count: 'exact', head: true })
          .eq('entity_id', r.id)
          .eq('action', 'team_def.read_during_seal')
        setAttemptedReadCount(count ?? 0)
      })
      .catch(e => { setErr(e instanceof Error ? e.message : 'Failed to load run'); setRun(null) })
  }, [supabase, id, personId])

  useEffect(() => { reload() }, [reload])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>Team-based definition</span>}>
        <Card><CardBody>
          <p>You must sign in to view a definition run.</p>
          <Button onClick={async () => {
            await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' })
          }}>Sign in as Linnea (demo)</Button>
        </CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell
      breadcrumb={<>Hiring · Team-based definition · <strong>{run?.role_family ?? '…'}</strong></>}
      signedInLabel={signedIn}
    >
      <div className="flex flex-col gap-4">
        {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust">{err}</div>}
        {run === undefined && (
          <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading run…</div>
        )}
        {run === null && !err && (
          <Card><CardBody><p className="text-faint">Run not found, or you don't have access to it.</p></CardBody></Card>
        )}

        {run && (
          <>
            <RunHeader run={run} />
            <StageStepper stage={run.stage} />

            {run.stage === 'setup' && (
              <Card><CardBody>
                <p className="text-faint text-sm">
                  Run is still in setup. Open <code className="font-mono">/team-def/new</code> to invite evaluators
                  and advance to Stage 2 (rating). This usually happens immediately on creation.
                </p>
              </CardBody></Card>
            )}

            {run.stage === 'rating' && me && me.submitted_at === null && (
              <RatingForm run={run} evaluatorId={me.id} alreadySubmitted={false} onSubmitted={reload} />
            )}
            {run.stage === 'rating' && me && me.submitted_at !== null && (
              <RatingForm run={run} evaluatorId={me.id} alreadySubmitted={true} onSubmitted={() => {}} />
            )}
            {run.stage === 'rating' && !me && (
              <Card><CardBody className="flex items-start gap-3">
                <AlertCircle size={18} className="text-amber flex-shrink-0 mt-0.5" />
                <div className="text-sm">
                  <div className="font-semibold mb-1">You're not an evaluator on this run.</div>
                  <p className="text-muted leading-relaxed">
                    Stage 2 is sealed: even the run owner can't see ratings during this phase.
                    The owner-side view comes in Stage 3 (divergence), which is intentionally
                    audited because any read during seal is a methodology event.
                  </p>
                </div>
              </CardBody></Card>
            )}

            {run.stage === 'divergence' && (
              <DivergencePanel
                run={run}
                evaluators={evaluators}
                attemptedReadCount={attemptedReadCount}
                onReadyForReconciliation={() => setForceStage4(true)}
              />
            )}
            {(run.stage === 'reconciliation' || run.stage === 'signed_off' || (run.stage === 'divergence' && forceStage4)) && (
              <ReconciliationPanel
                run={run}
                evaluatorCount={evaluators.length}
                evaluatorOrder={evaluatorOrderForReconciliation(evaluators)}
              />
            )}
          </>
        )}

        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}

function evaluatorOrderForReconciliation(evs: EvaluatorWithPerson[]): string[] {
  return [...evs]
    .sort((a, b) => (a.submitted_at ?? '').localeCompare(b.submitted_at ?? '') || a.id.localeCompare(b.id))
    .map(e => e.id)
}
