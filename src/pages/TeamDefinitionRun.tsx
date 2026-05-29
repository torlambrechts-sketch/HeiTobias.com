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

// Main run page. Renders the stepper + header, then either:
//   * Stage 1 (setup): forward to /team-def/new for first creation
//   * Stage 2 (rating): show the RatingForm if the caller is an invited
//     evaluator; otherwise show a "you're not on this run" notice
//   * Stage 3/4: placeholders shipped in CP3.3 / CP3.4
//
// CRITICAL: we never fetch other evaluators' rows on this page. The
// owner reveal flow is reserved for the dedicated Stage 3 view (CP3.3),
// which will call rpc_team_definition_evaluations_for_owner and accept
// the audit-log consequence.
export function TeamDefinitionRunPage() {
  const { id } = useParams<{ id: string }>()
  const supabase = browserSupabase()
  const [signedIn, setSignedIn]   = useState<string | null>(null)
  const [personId, setPersonId]   = useState<string | null>(null)
  const [run, setRun]             = useState<RunRow | null | undefined>(undefined)
  const [me, setMe]               = useState<EvaluatorRow | null>(null)
  const [err, setErr]             = useState<string | null>(null)

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
        if (r) {
          const evs = await fetchEvaluators(supabase, r.id)
          setMe(evs.find(e => e.user_id === personId) ?? null)
        }
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

            {(run.stage === 'divergence' || run.stage === 'reconciliation' || run.stage === 'signed_off') && (
              <Card><CardBody>
                <p className="text-faint text-sm">
                  Stage 3 (divergence) + Stage 4 (reconciliation + sign-off) UI lands in CP3.3 / CP3.4.
                  For now, the run is in <code className="font-mono">{run.stage}</code> — query via SQL or wait.
                </p>
              </CardBody></Card>
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
