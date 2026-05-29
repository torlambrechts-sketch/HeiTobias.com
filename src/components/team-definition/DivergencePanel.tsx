import { useCallback, useEffect, useMemo, useState } from 'react'
import { AlertCircle, GitMerge, Loader2, RotateCw } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { computeDivergence, type DivergenceResult, type RunRow } from '../../lib/teamDefinition.js'
import { Button } from '../ui/button.js'
import { Card, CardBody } from '../ui/card.js'
import { Pill } from '../ui/badges.js'
import { SealCallout } from './SealCallout.js'
import { EvaluatorRoster, type EvaluatorWithPerson } from './EvaluatorRoster.js'
import { DivergenceItem } from './DivergenceItem.js'

// Stage 3 — the divergence review. The owner / reconciler lands here
// after Stage 2 seals. The whole point of this panel is to SURFACE
// per-evaluator positions, not to average them. The summary numbers
// (high/moderate/low counts) are descriptive only — the dot plots
// per criterion are the actual evidence.

export function DivergencePanel({
  run,
  evaluators,
  attemptedReadCount,
  onReadyForReconciliation,
}: {
  run: RunRow
  evaluators: EvaluatorWithPerson[]
  attemptedReadCount: number
  onReadyForReconciliation: () => void
}) {
  const supabase = browserSupabase()
  const [showNames, setShowNames] = useState(false)
  const [result, setResult]       = useState<DivergenceResult | null>(null)
  const [busy, setBusy]           = useState(false)
  const [err, setErr]             = useState<string | null>(null)

  const reload = useCallback(async () => {
    setBusy(true); setErr(null)
    try { setResult(await computeDivergence(supabase, run.id)) }
    catch (e) { setErr(e instanceof Error ? e.message : String(e)) }
    finally { setBusy(false) }
  }, [supabase, run.id])

  useEffect(() => { void reload() }, [reload])

  // Stable E-code ordering: by submitted_at, then id.
  const order = useMemo(
    () => [...evaluators].sort((a, b) => (a.submitted_at ?? '').localeCompare(b.submitted_at ?? '') || a.id.localeCompare(b.id)).map(e => e.id),
    [evaluators],
  )

  const submitted = evaluators.filter(e => e.submitted_at).length

  return (
    <div data-test="divergence-panel">
      <SealCallout sealedAt={run.updated_at} evaluatorCount={submitted} attemptedReadCount={attemptedReadCount} />

      {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust mb-4">{err}</div>}

      {busy && !result && (
        <Card><CardBody>
          <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Computing divergence…</div>
        </CardBody></Card>
      )}

      {result && (
        <>
          {/* Summary — descriptive only, the dot plots below are the evidence */}
          <Card className="mb-5">
            <CardBody>
              <div className="flex items-center gap-7 flex-wrap">
                <Stat n={result.summary.total_criteria}              label="Criteria rated"     />
                <Stat n={result.summary.low}      tone="text-rust"   label="Low consensus"      />
                <Stat n={result.summary.moderate} tone="text-amber"  label="Moderate"           />
                <Stat n={result.summary.high}     tone="text-green"  label="High consensus"     />
                <div className="ml-auto flex items-center gap-2">
                  <Pill tone="internal">cutoff = {result.summary.cutoff} (dev_stub)</Pill>
                  <Button variant="ghost" onClick={reload} className="text-xs border border-line">
                    {busy ? <Loader2 size={12} className="animate-spin" /> : <RotateCw size={12} />} Recompute
                  </Button>
                </div>
              </div>
            </CardBody>
          </Card>

          {/* Roster + anonymisation toggle */}
          <Card className="mb-5">
            <CardBody>
              <h3 className="font-display text-xl font-semibold mb-1">Evaluators &amp; submissions</h3>
              <p className="text-muted text-sm mb-4 max-w-2xl">
                Each evaluator is shown by E-code by default. Names appear only for those who opted
                into named attribution at Stage 1. Toggle below to reveal where consented.
                <span className="block text-xs text-faint mt-1 font-mono">SCIENCE-SPEC §7; Linstone &amp; Turoff (1975)</span>
              </p>
              <EvaluatorRoster evaluators={evaluators} showNames={showNames} setShowNames={setShowNames} />
            </CardBody>
          </Card>

          {/* The actual divergence — criterion by criterion */}
          <Card className="mb-5">
            <CardBody>
              <h3 className="font-display text-xl font-semibold mb-1">Divergence — criterion by criterion</h3>
              <p className="text-muted text-sm mb-4 max-w-2xl">
                For each criterion, the individual positions are surfaced rather than averaged away.
                Low-consensus items are flagged for reconciliation. Spread metrics are computed;
                verdicts are deferred to the human reconciler.
                <span className="block text-xs text-faint mt-1">
                  Per SCIENCE-SPEC §7 "surfaces divergence, never averages it"; spread method: sample SD.
                </span>
              </p>
              {result.criteria.length === 0 && (
                <div className="text-faint text-sm italic border border-dashed border-line rounded p-4">
                  No numeric criteria found in the submitted ratings. Submitted evaluations may have
                  rated only textual fields.
                </div>
              )}
              <div className="flex flex-col gap-4">
                {result.criteria.map(c => (
                  <DivergenceItem key={c.criterion_key} criterion={c} evaluatorOrder={order} />
                ))}
              </div>
            </CardBody>
          </Card>

          <div className="flex items-center gap-3 border-t border-line pt-4">
            <Button onClick={onReadyForReconciliation} disabled={result.summary.low === 0}>
              <GitMerge size={14} /> Begin reconciliation
              {result.summary.low > 0 && <span className="font-mono ml-2 text-xs opacity-80">({result.summary.low} flagged)</span>}
            </Button>
            <span className="text-xs text-faint flex items-center gap-1.5 max-w-md">
              {result.summary.low === 0
                ? <><AlertCircle size={12} /> Nothing flagged — but the reconciler may still want to review moderates before sign-off.</>
                : <>Reconciliation will record per-criterion decisions with per-evaluator attribution + a decision_artefact each.</>}
            </span>
          </div>
        </>
      )}
    </div>
  )
}

function Stat({ n, label, tone }: { n: number; label: string; tone?: string }) {
  return (
    <div className="flex flex-col">
      <div className={'font-display text-3xl font-semibold leading-none ' + (tone ?? '')}>{n}</div>
      <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted mt-1.5">{label}</div>
    </div>
  )
}
