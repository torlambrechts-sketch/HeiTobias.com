import { useCallback, useMemo, useState } from 'react'
import { Check, GitMerge, Loader2 } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { recordReconciliation, type DivergenceCriterion } from '../../lib/teamDefinition.js'
import { Button } from '../ui/button.js'
import { Card, CardBody } from '../ui/card.js'

// Per-criterion reconciliation. Shows the spread the evaluators
// produced + a discussion-notes textarea (>=20 chars, enforced both
// here and at the rpc_record_reconciliation SECDEF guard) + a final
// value picker that defaults to the mean but the reconciler can
// override. Attribution captures which evaluator position(s) the
// final value most closely follows — that's the audit-grade trail.

const MIN_NOTES = 20

const PALETTE = ['#42729e','#3f7d5a','#a8862f','#7a5fa0','#b8584a','#3aa3a3','#c87a4a']

export function ReconciliationForm({
  runId,
  criterion,
  evaluatorOrder,
  onDone,
}: {
  runId: string
  criterion: DivergenceCriterion
  evaluatorOrder: string[]
  onDone: () => void
}) {
  const supabase = browserSupabase()
  const isWeight = criterion.criterion_key.includes('weight')
  const step = isWeight ? 0.01 : 1
  const lo   = isWeight ? 0    : Math.floor(criterion.min)
  const hi   = isWeight ? 1    : Math.ceil(criterion.max)

  const [finalValue, setFinalValue] = useState<number>(+criterion.mean.toFixed(isWeight ? 2 : 0))
  const [notes, setNotes]           = useState<string>('')
  const [attribution, setAttribution] = useState<Record<string, boolean>>({})
  const [busy, setBusy]             = useState(false)
  const [err, setErr]               = useState<string | null>(null)

  const notesValid = notes.trim().length >= MIN_NOTES
  const attributionList = useMemo(
    () => Object.entries(attribution).filter(([, v]) => v).map(([k]) => k),
    [attribution],
  )

  const submit = useCallback(async () => {
    if (!notesValid) { setErr(`Discussion notes need at least ${MIN_NOTES} characters.`); return }
    setBusy(true); setErr(null)
    try {
      await recordReconciliation(supabase, {
        p_run_id: runId,
        p_criterion_key: criterion.criterion_key,
        p_discussion_notes: notes.trim(),
        p_final_value_json: { value: finalValue },
        p_attribution_json: {
          followed_evaluators: attributionList,
          rationale_excerpt: notes.trim().slice(0, 200),
        },
      })
      onDone()
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }, [supabase, runId, criterion.criterion_key, notes, finalValue, attributionList, notesValid, onDone])

  return (
    <Card>
      <CardBody className="flex flex-col gap-4">
        <div>
          <h4 className="font-display text-lg font-semibold">Reconcile · {prettyName(criterion.criterion_key)}</h4>
          <p className="text-muted text-sm mt-1 max-w-2xl">
            The spread on this criterion was real. The reconciler decides — informed by the
            evaluator positions below, not averaging them away. The decision_artefact will
            carry the per-evaluator positions, your final value, and a 200-char excerpt of
            the rationale.
          </p>
        </div>

        {/* Evaluator positions for context */}
        <div>
          <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted mb-2">Evaluator positions</div>
          <div className="flex flex-wrap gap-2">
            {criterion.values.map((v, i) => {
              const idx = Math.max(0, evaluatorOrder.indexOf(v.evaluator_id))
              const code = `E${idx + 1}`
              const color = PALETTE[idx % PALETTE.length]
              const id = v.evaluator_id
              const followed = !!attribution[id]
              return (
                <label
                  key={i}
                  className={'inline-flex items-center gap-2 px-2.5 py-1.5 rounded border cursor-pointer text-xs ' +
                    (followed ? 'border-forest bg-canvas-2' : 'border-line bg-surface hover:bg-canvas')}
                >
                  <input
                    type="checkbox"
                    checked={followed}
                    onChange={e => setAttribution(a => ({ ...a, [id]: e.target.checked }))}
                  />
                  <span className="w-4 h-4 rounded-full inline-block" style={{ backgroundColor: color }} />
                  <span className="font-bold">{code}</span>
                  <span className="font-mono">{v.value.toFixed(isWeight ? 2 : 0)}</span>
                </label>
              )
            })}
          </div>
          <div className="text-xs text-faint mt-2">
            Check the evaluators whose positions your final value most closely follows. This becomes
            the <code className="font-mono">attribution_json</code> on the reconciliation row.
          </div>
        </div>

        {/* Final value */}
        <div className="grid lg:grid-cols-[1fr_auto] gap-3 items-end">
          <label className="flex flex-col gap-1.5">
            <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Final value</span>
            <input
              type="range"
              min={lo} max={hi} step={step}
              value={finalValue}
              onChange={e => setFinalValue(Number(e.target.value))}
              className="accent-role"
              aria-label={`Final value for ${criterion.criterion_key}`}
            />
            <span className="text-xs text-muted">Range used by evaluators: {criterion.min.toFixed(2)} – {criterion.max.toFixed(2)} · mean {criterion.mean.toFixed(2)}</span>
          </label>
          <div className="font-mono text-xl font-semibold text-ink">
            {finalValue.toFixed(isWeight ? 2 : 0)}
          </div>
        </div>

        {/* Discussion notes */}
        <label className="flex flex-col gap-1.5">
          <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">
            Discussion notes <span className="text-faint normal-case font-normal">(audit-grade — ≥{MIN_NOTES} chars)</span>
          </span>
          <textarea
            value={notes}
            onChange={e => setNotes(e.target.value)}
            rows={4}
            placeholder="What did the reconciliation discussion surface? Which considerations swayed the final value?"
            className="border border-line rounded px-3 py-2 bg-surface text-sm font-body"
          />
          <span className={'text-xs font-mono ' + (notesValid ? 'text-green' : 'text-faint')}>
            {notes.trim().length} / {MIN_NOTES}{notesValid ? ' ✓' : ''}
          </span>
        </label>

        {err && <div className="text-sm text-rust border border-rust/40 rounded p-3 bg-reject-bg">{err}</div>}

        <div className="flex items-center gap-3 border-t border-line pt-3">
          <Button onClick={submit} disabled={busy || !notesValid}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <Check size={14} />}
            Record reconciliation
          </Button>
          <span className="text-xs text-faint">
            <GitMerge size={11} className="inline mr-1" />
            Writes a row to <code className="font-mono">team_definition_reconciliations</code> + audit_log.
          </span>
        </div>
      </CardBody>
    </Card>
  )
}

function prettyName(key: string): string {
  return key
    .split('.')
    .map(p => p.replace(/_/g, ' '))
    .map(p => p.replace(/\b\w/g, c => c.toUpperCase()))
    .join(' · ')
}
