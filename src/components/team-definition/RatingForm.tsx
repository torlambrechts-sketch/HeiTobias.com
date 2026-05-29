import { useCallback, useMemo, useState } from 'react'
import { CheckCircle2, EyeOff, Info, Loader2, Send } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { submitEvaluation, type RunRow } from '../../lib/teamDefinition.js'
import { Button } from '../ui/button.js'
import { Card, CardBody } from '../ui/card.js'
import { Pill } from '../ui/badges.js'
import { SurveillanceGuardrail } from './SurveillanceGuardrail.js'

// Stage 2 — Independent rating. Evaluator rates the ROLE criteria
// independently. The component is INTENTIONALLY ignorant of any other
// evaluator's rating: there is no fetch from
// rpc_team_definition_evaluations_for_owner, no SELECT against
// team_definition_evaluations beyond `is_self`, and no rendering of
// other rows. This is the client-side lock of the three-lock seal.
//
// The criteria are pulled from the run's draft_definition_json
// (seeded from the role template at Stage 1). Each evaluator rates
// the SAME criteria, but their numbers stay sealed until owner triggers
// rpc_seal_evaluations.
//
// PEER-PERSONALITY BLOCK: there is no affordance to pick a person, name
// a teammate, or rate "how Alice is". The UI deliberately offers only
// role-structural criteria. The schema CHECK
// chk_team_def_evaluations_no_peer_personality is the second belt.

type Criticality = {
  task_key: string
  task_label: string
  task_description: string
  outcome_metric: string | null
}

type CompetencyWeight = {
  key: string
  label: string
  description: string
}

function defaultCriticality(): Criticality[] {
  return [
    { task_key: 'design_review',    task_label: 'Lead architectural design review', task_description: 'Run the design-review process for new features and migrations.', outcome_metric: 'review_throughput_per_sprint' },
    { task_key: 'production_oncall', task_label: 'Production on-call rotation',     task_description: 'First responder for production incidents during shift.',          outcome_metric: 'p1_resolution_time_p95' },
    { task_key: 'cross_team',        task_label: 'Cross-team technical liaison',     task_description: 'Represent the team in cross-team design conversations.',          outcome_metric: 'cross_team_proposals_authored' },
    { task_key: 'mentoring',         task_label: 'Mentor junior engineers',          task_description: 'Pair, code-review, and growth-plan for engineers L2-L3.',        outcome_metric: 'mentee_promotion_rate' },
  ]
}
function defaultCompetencies(): CompetencyWeight[] {
  return [
    { key: 'technical_depth',  label: 'Technical depth',                description: 'How much specialised engineering judgment the role needs.' },
    { key: 'leadership',       label: 'People leadership',              description: 'Coaching, mentoring, growth-planning — not management.' },
    { key: 'analysis',         label: 'Analyzing & interpreting data',  description: 'Reading metrics, profiling, postmortems.' },
    { key: 'communication',    label: 'Communicating & influencing',    description: 'Writing, presenting, persuading across teams.' },
    { key: 'adapting',         label: 'Adapting & responding',          description: 'Working under change, ambiguity, shifting priorities.' },
  ]
}

function readCriticality(run: RunRow): Criticality[] {
  const fromDef = (run.draft_definition_json['tasks'] as Criticality[] | undefined)
  return Array.isArray(fromDef) && fromDef.length > 0 ? fromDef : defaultCriticality()
}
function readCompetencies(run: RunRow): CompetencyWeight[] {
  const fromDef = (run.draft_definition_json['competencies'] as CompetencyWeight[] | undefined)
  return Array.isArray(fromDef) && fromDef.length > 0 ? fromDef : defaultCompetencies()
}

export function RatingForm({
  run,
  evaluatorId,
  alreadySubmitted,
  onSubmitted,
}: {
  run: RunRow
  evaluatorId: string
  alreadySubmitted: boolean
  onSubmitted: () => void
}) {
  const supabase = browserSupabase()
  const tasks         = useMemo(() => readCriticality(run), [run])
  const competencies  = useMemo(() => readCompetencies(run), [run])
  const [criticality, setCriticality] = useState<Record<string, number>>(() => Object.fromEntries(tasks.map(t => [t.task_key, 3])))
  const [weights, setWeights]         = useState<Record<string, number>>(() => Object.fromEntries(competencies.map(c => [c.key, +(1 / competencies.length).toFixed(2)])))
  const [notes, setNotes]             = useState<string>('')
  const [busy, setBusy]               = useState(false)
  const [err, setErr]                 = useState<string | null>(null)
  const [done, setDone]               = useState(alreadySubmitted)

  const weightTotal = useMemo(() => Object.values(weights).reduce((s, v) => s + v, 0), [weights])
  const weightOk    = Math.abs(weightTotal - 1) < 0.02

  const submit = useCallback(async () => {
    if (!weightOk) { setErr(`Competency weights must sum to 1.00 (currently ${weightTotal.toFixed(2)}).`); return }
    setBusy(true); setErr(null)
    try {
      const rating_json = {
        criticality,
        competency_weights: weights,
        // INTENTIONALLY no target_person_id / rater_person_id / rates_person —
        // the schema CHECK rejects those keys outright.
      }
      const rationale_notes_json = notes.trim() ? { notes: notes.trim() } : {}
      await submitEvaluation(supabase, { p_run_id: run.id, p_rating_json: rating_json, p_rationale_notes_json: rationale_notes_json })
      setDone(true)
      onSubmitted()
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }, [supabase, run.id, criticality, weights, notes, weightOk, weightTotal, onSubmitted])

  if (done) {
    return (
      <Card>
        <CardBody className="flex items-start gap-3">
          <CheckCircle2 size={20} className="text-green flex-shrink-0 mt-0.5" />
          <div className="text-sm">
            <div className="font-semibold mb-1">Your rating is sealed.</div>
            <p className="text-muted leading-relaxed">
              You can't change it now, and no one else (including the run owner) can see it
              until <strong>all evaluators submit</strong> OR the deadline passes — whichever
              comes first. At that point your numbers join the divergence view. Your name will
              appear there only if you opted into named attribution.
            </p>
            <p className="text-faint text-xs font-mono mt-2">evaluator_id = {evaluatorId}</p>
          </div>
        </CardBody>
      </Card>
    )
  }

  return (
    <div data-test="stage2-rating-form">
      {/* The load-bearing UI guardrail. Body copy, not tooltip. */}
      <SurveillanceGuardrail />

      <div className="flex items-center gap-2 mb-3">
        <Pill tone="interview">Stage 2 — Your independent rating</Pill>
        <Pill tone="internal"><EyeOff size={12} /> Sealed until all submit or deadline</Pill>
      </div>

      {/* Task criticality */}
      <Card className="mb-4">
        <CardBody>
          <h3 className="font-display text-xl font-semibold mb-1">Task criticality</h3>
          <p className="text-muted text-sm mb-4 max-w-2xl">
            For each role task, rate how <strong>mission-critical</strong> it is to the role's success.
            You're rating the role, not anyone's performance. 1 = peripheral, 5 = central.
          </p>
          <div className="flex flex-col gap-3">
            {tasks.map(t => (
              <div key={t.task_key} className="grid lg:grid-cols-[1fr_auto_auto] gap-3 items-center border-b border-line pb-3 last:border-b-0">
                <div>
                  <div className="text-sm font-semibold">{t.task_label}</div>
                  <div className="text-xs text-muted mt-0.5">{t.task_description}</div>
                </div>
                <input
                  type="range"
                  min={1} max={5} step={1}
                  value={criticality[t.task_key] ?? 3}
                  onChange={e => setCriticality(c => ({ ...c, [t.task_key]: Number(e.target.value) }))}
                  className="lg:w-48 accent-role"
                  aria-label={`Criticality of ${t.task_label}`}
                />
                <span className="font-mono text-sm w-8 text-right">{criticality[t.task_key] ?? 3}</span>
              </div>
            ))}
          </div>
        </CardBody>
      </Card>

      {/* Competency weights */}
      <Card className="mb-4">
        <CardBody>
          <h3 className="font-display text-xl font-semibold mb-1">Competency weights</h3>
          <p className="text-muted text-sm mb-4 max-w-2xl">
            How much should each competency count in fit scoring for this role? Weights must
            sum to 1.00. You're weighting the <strong>role's needs</strong>, not any person's strengths.
          </p>
          <div className="flex flex-col gap-3">
            {competencies.map(c => (
              <div key={c.key} className="grid lg:grid-cols-[1fr_auto_auto] gap-3 items-center border-b border-line pb-3 last:border-b-0">
                <div>
                  <div className="text-sm font-semibold">{c.label}</div>
                  <div className="text-xs text-muted mt-0.5">{c.description}</div>
                </div>
                <input
                  type="range"
                  min={0} max={1} step={0.05}
                  value={weights[c.key] ?? 0}
                  onChange={e => setWeights(w => ({ ...w, [c.key]: Number(e.target.value) }))}
                  className="lg:w-48 accent-role"
                  aria-label={`Weight of ${c.label}`}
                />
                <span className="font-mono text-sm w-12 text-right">{(weights[c.key] ?? 0).toFixed(2)}</span>
              </div>
            ))}
          </div>
          <div className="flex items-center justify-between mt-3 text-sm">
            <span className="text-muted">Total</span>
            <span className={'font-mono font-semibold ' + (weightOk ? 'text-green' : 'text-rust')}>
              {weightTotal.toFixed(2)} / 1.00
            </span>
          </div>
        </CardBody>
      </Card>

      {/* Rationale notes */}
      <Card className="mb-4">
        <CardBody>
          <h3 className="font-display text-xl font-semibold mb-1">Rationale (optional)</h3>
          <p className="text-muted text-sm mb-3 max-w-2xl">
            Briefly explain your reasoning — what context shaped these numbers? Stay on the role.
            <span className="block text-xs text-faint mt-1 flex items-center gap-1.5">
              <Info size={11} /> Don't name teammates by personality (e.g. "Alice is too quiet").
              The schema will reject it, and the methodology disallows it.
            </span>
          </p>
          <textarea
            value={notes}
            onChange={e => setNotes(e.target.value)}
            placeholder="The team is shifting from monolith → microservices over the next 6 months, so cross-team liaison matters more than it did last cycle…"
            rows={5}
            className="w-full border border-line rounded px-3 py-2 bg-surface text-sm font-body"
          />
        </CardBody>
      </Card>

      {err && <div className="text-sm text-rust border border-rust/40 rounded p-3 bg-reject-bg mb-3">{err}</div>}

      <div className="flex items-center gap-3">
        <Button onClick={submit} disabled={busy || !weightOk}>
          {busy ? <Loader2 size={14} className="animate-spin" /> : <Send size={14} />}
          Submit my rating (sealed)
        </Button>
        <span className="text-xs text-faint max-w-md">
          Once you submit, your row becomes immutable. No edits after submit — that's by design
          (you'd be reacting to others, defeating the Delphi independence).
        </span>
      </div>
    </div>
  )
}
