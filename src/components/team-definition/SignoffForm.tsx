import { useCallback, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { CheckCircle2, Loader2, ShieldCheck } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { signoffRoleVersion, type RunRow } from '../../lib/teamDefinition.js'
import { Button } from '../ui/button.js'
import { Card, CardBody } from '../ui/card.js'
import { Pill } from '../ui/badges.js'

// Final action of the run. Creates a new role version with the
// Delphi provenance stamped into validation_and_defensibility_metadata.
// Requires >=20-char rationale + role.signoff permission. The new
// version lands in the roles_catalog and is linkable from the run.

const MIN_RATIONALE = 20

export function SignoffForm({
  run,
  reconciledCount,
  flaggedCount,
  evaluatorCount,
}: {
  run: RunRow
  reconciledCount: number
  flaggedCount: number
  evaluatorCount: number
}) {
  const supabase = browserSupabase()
  const navigate = useNavigate()
  const [rationale, setRationale] = useState('')
  const [busy, setBusy]           = useState(false)
  const [err, setErr]             = useState<string | null>(null)
  const [newRoleId, setNewRoleId] = useState<string | null>(run.target_role_version_id)

  const valid = rationale.trim().length >= MIN_RATIONALE
  const submit = useCallback(async () => {
    if (!valid) { setErr(`Sign-off rationale needs at least ${MIN_RATIONALE} characters.`); return }
    setBusy(true); setErr(null)
    try {
      const newId = await signoffRoleVersion(supabase, { p_run_id: run.id, p_rationale: rationale.trim() })
      setNewRoleId(newId)
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }, [supabase, run.id, rationale, valid])

  if (newRoleId) {
    return (
      <Card>
        <CardBody className="flex items-start gap-3">
          <CheckCircle2 size={22} className="text-green flex-shrink-0 mt-0.5" />
          <div className="text-sm flex-1">
            <div className="font-semibold mb-1 text-base">Signed off · new role version created</div>
            <p className="text-muted leading-relaxed">
              The run produced a new <code className="font-mono">roles_catalog</code> row carrying the
              full Delphi provenance — evaluator count, reconciliation count, snapshotted thresholds,
              and your rationale excerpt — under{' '}
              <code className="font-mono">validation_and_defensibility_metadata.team_definition_run_id</code>.
            </p>
            <div className="mt-3 flex items-center gap-3">
              <Button onClick={() => navigate(`/roles/${newRoleId}`)}>
                Open new role version
              </Button>
              <span className="font-mono text-xs text-faint">{newRoleId}</span>
            </div>
          </div>
        </CardBody>
      </Card>
    )
  }

  return (
    <Card data-test="signoff-form">
      <CardBody className="flex flex-col gap-4">
        <div>
          <h3 className="font-display text-xl font-semibold">Sign-off</h3>
          <p className="text-muted text-sm mt-1 max-w-2xl">
            Creates a new versioned role profile from the reconciled definition. The version
            carries the full Delphi provenance in{' '}
            <code className="font-mono">validation_and_defensibility_metadata</code> — the audit trail
            stays attached to the role wherever it's used (requisitions, fit scoring, exports).
          </p>
        </div>

        {/* Provenance preview */}
        <div className="border border-line rounded p-4 bg-canvas">
          <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted mb-3">Provenance preview</div>
          <div className="grid lg:grid-cols-2 gap-x-6 gap-y-2 text-sm">
            <Row k="Run ID"                v={<code className="font-mono text-xs">{run.id}</code>} />
            <Row k="Evaluators invited"    v={<span className="font-mono">{evaluatorCount}</span>} />
            <Row k="Criteria reconciled"   v={<span className="font-mono">{reconciledCount} of {flaggedCount} flagged</span>} />
            <Row k="Validation method"     v={<span>team_definition_delphi</span>} />
            <Row k="Framing default"       v={<Pill tone="interview">developmental</Pill>} />
            <Row k="Thresholds"            v={<Pill tone="reject">dev_stub (snapshot)</Pill>} />
          </div>
          <div className="text-xs text-faint mt-3 leading-snug">
            All of the above lands in <code className="font-mono">validation_and_defensibility_metadata</code>{' '}
            on the new role version row. The role can't transition to{' '}
            <code className="font-mono">validity_status='validated'</code> until the I/O psychologist
            signs off the thresholds (HANDOFF, not engineering).
          </div>
        </div>

        {/* Rationale */}
        <label className="flex flex-col gap-1.5">
          <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">
            Sign-off rationale <span className="text-faint normal-case font-normal">(audit-grade — ≥{MIN_RATIONALE} chars; 200-char excerpt stored)</span>
          </span>
          <textarea
            value={rationale}
            onChange={e => setRationale(e.target.value)}
            rows={5}
            placeholder="Why is this role definition right for the team RIGHT NOW? What strategy / context shaped the reconciliation calls?"
            className="border border-line rounded px-3 py-2 bg-surface text-sm font-body"
          />
          <span className={'text-xs font-mono ' + (valid ? 'text-green' : 'text-faint')}>
            {rationale.trim().length} / {MIN_RATIONALE}{valid ? ' ✓' : ''}
          </span>
        </label>

        {err && <div className="text-sm text-rust border border-rust/40 rounded p-3 bg-reject-bg">{err}</div>}

        <div className="flex items-center gap-3 border-t border-line pt-3">
          <Button onClick={submit} disabled={busy || !valid}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <ShieldCheck size={14} />}
            Sign off &amp; create role version
          </Button>
          <span className="text-xs text-faint">
            Requires <code className="font-mono">role.signoff</code> in the run's org.
          </span>
        </div>
      </CardBody>
    </Card>
  )
}

function Row({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between border-b border-line pb-1">
      <span className="text-xs uppercase tracking-wider font-bold text-muted">{k}</span>
      <span>{v}</span>
    </div>
  )
}
