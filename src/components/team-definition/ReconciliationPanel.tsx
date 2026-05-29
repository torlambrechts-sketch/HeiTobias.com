import { useCallback, useEffect, useMemo, useState } from 'react'
import { ChevronDown, ChevronUp, GitMerge, Loader2 } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import {
  computeDivergence,
  fetchReconciliations,
  type DivergenceCriterion,
  type ReconciliationRow,
  type RunRow,
} from '../../lib/teamDefinition.js'
import { Card, CardBody } from '../ui/card.js'
import { Pill } from '../ui/badges.js'
import { ReconciliationForm } from './ReconciliationForm.js'
import { SignoffForm } from './SignoffForm.js'

// Stage 4 orchestrator. Pulls the divergence + existing reconciliations
// and renders:
//   * Progress strip: N of M flagged criteria reconciled
//   * Per-criterion list — flagged items collapsible to ReconciliationForm
//   * Sign-off card once all flagged items are reconciled (or
//     immediately if nothing was flagged — clean run path)

export function ReconciliationPanel({
  run,
  evaluatorCount,
  evaluatorOrder,
}: {
  run: RunRow
  evaluatorCount: number
  evaluatorOrder: string[]
}) {
  const supabase = browserSupabase()
  const [criteria, setCriteria]               = useState<DivergenceCriterion[]>([])
  const [reconciliations, setReconciliations] = useState<ReconciliationRow[]>([])
  const [openKey, setOpenKey]                 = useState<string | null>(null)
  const [busy, setBusy]                       = useState(false)
  const [err, setErr]                         = useState<string | null>(null)

  const reload = useCallback(async () => {
    setBusy(true); setErr(null)
    try {
      const [d, r] = await Promise.all([
        computeDivergence(supabase, run.id),
        fetchReconciliations(supabase, run.id),
      ])
      setCriteria(d.criteria)
      setReconciliations(r)
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }, [supabase, run.id])

  useEffect(() => { void reload() }, [reload])

  const reconciledKeys = useMemo(
    () => new Set(reconciliations.map(r => r.criterion_key)),
    [reconciliations],
  )
  const flagged = useMemo(() => criteria.filter(c => c.flagged_for_reconciliation), [criteria])
  const flaggedRemaining = useMemo(
    () => flagged.filter(c => !reconciledKeys.has(c.criterion_key)),
    [flagged, reconciledKeys],
  )
  const allFlaggedDone = flagged.length > 0 && flaggedRemaining.length === 0
  const noneFlagged    = flagged.length === 0

  return (
    <div data-test="reconciliation-panel">
      {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust mb-4">{err}</div>}

      {/* Progress */}
      <Card className="mb-5">
        <CardBody>
          <div className="flex items-center gap-6 flex-wrap">
            <div className="flex flex-col">
              <div className="font-display text-3xl font-semibold leading-none">
                {reconciliations.length}{flagged.length > 0 ? ` / ${flagged.length}` : ''}
              </div>
              <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted mt-1.5">
                {flagged.length > 0 ? 'Flagged reconciled' : 'Reconciliations recorded'}
              </div>
            </div>
            <div className="flex flex-col">
              <div className="font-display text-3xl font-semibold leading-none text-rust">{flaggedRemaining.length}</div>
              <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted mt-1.5">Remaining</div>
            </div>
            <div className="ml-auto flex items-center gap-2">
              {busy && <Loader2 size={14} className="animate-spin text-faint" />}
              {noneFlagged && <Pill tone="open">No flagged items — ready for sign-off</Pill>}
              {allFlaggedDone && <Pill tone="open">All flagged reconciled — ready for sign-off</Pill>}
              {!noneFlagged && !allFlaggedDone && <Pill tone="reject">Reconciliation in progress</Pill>}
            </div>
          </div>
        </CardBody>
      </Card>

      {/* Flagged criteria list */}
      {flagged.length > 0 && (
        <Card className="mb-5">
          <CardBody>
            <h3 className="font-display text-xl font-semibold mb-1">Low-consensus criteria</h3>
            <p className="text-muted text-sm mb-4 max-w-2xl">
              Each of these had SD &ge; the low-consensus cutoff. The reconciler runs a structured
              discussion on each and records a decision_artefact carrying per-evaluator attribution
              and a ≥20-char rationale. Click a row to open the reconciliation form.
            </p>
            <div className="flex flex-col gap-2">
              {flagged.map(c => {
                const done = reconciledKeys.has(c.criterion_key)
                const isOpen = openKey === c.criterion_key
                return (
                  <div key={c.criterion_key}>
                    <button
                      type="button"
                      onClick={() => setOpenKey(isOpen ? null : c.criterion_key)}
                      className={'w-full text-left border rounded px-4 py-3 flex items-center gap-3 transition-colors ' +
                        (done ? 'border-green/40 bg-open-bg/40 hover:bg-open-bg/60'
                              : isOpen ? 'border-forest bg-canvas-2'
                                       : 'border-line bg-surface hover:bg-canvas')}
                    >
                      <GitMerge size={15} className={done ? 'text-green' : 'text-rust'} />
                      <div className="flex-1 min-w-0">
                        <div className="text-sm font-semibold">{prettyName(c.criterion_key)}</div>
                        <div className="text-xs text-muted font-mono mt-0.5">
                          {c.criterion_key} · SD {c.spread_value.toFixed(3)} · range {c.min.toFixed(2)}–{c.max.toFixed(2)}
                        </div>
                      </div>
                      {done
                        ? <Pill tone="open">Reconciled</Pill>
                        : <Pill tone="reject">Open</Pill>}
                      {isOpen ? <ChevronUp size={15} /> : <ChevronDown size={15} />}
                    </button>
                    {isOpen && !done && (
                      <div className="mt-2">
                        <ReconciliationForm
                          runId={run.id}
                          criterion={c}
                          evaluatorOrder={evaluatorOrder}
                          onDone={() => { setOpenKey(null); void reload() }}
                        />
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          </CardBody>
        </Card>
      )}

      {/* Sign-off — appears once all flagged are reconciled, or immediately if nothing was flagged */}
      {(allFlaggedDone || noneFlagged) && (
        <SignoffForm
          run={run}
          reconciledCount={reconciliations.length}
          flaggedCount={flagged.length}
          evaluatorCount={evaluatorCount}
        />
      )}
    </div>
  )
}

function prettyName(key: string): string {
  return key
    .split('.')
    .map(p => p.replace(/_/g, ' '))
    .map(p => p.replace(/\b\w/g, c => c.toUpperCase()))
    .join(' · ')
}
