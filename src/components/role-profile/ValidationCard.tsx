import { useCallback, useState } from 'react'
import { FileDown, Loader2, ShieldCheck } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import type { RoleProfileRow } from '../../types/roleProfile.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../ui/card.js'
import { Pill } from '../ui/badges.js'
import { Button } from '../ui/button.js'
import { StubPill } from './StubBanner.js'
import { SectionAnchor } from './Sections.js'

// 11 · Validation & defensibility metadata + document-export chips.
// Each chip calls rpc_role_export_assemble which wraps
// compliance_artifact_assemble — the system NEVER self-attests; the
// resulting artifact carries sign_off_status='draft' + payload
// self_attestation=null until an external legal sign-off lands.

const EXPORT_KINDS: { kind: string; label: string }[] = [
  { kind: 'annex_iv_technical_doc', label: 'Annex IV tech doc' },
  { kind: 'dpia',                   label: 'GDPR Art. 35 DPIA' },
  { kind: 'fria',                   label: 'AI Act Art. 27 FRIA' },
  { kind: 'validity_dossier',       label: 'Validity dossier' },
  { kind: 'fairness_audit_report',  label: 'Fairness audit report' },
]

export function ValidationCard({ row }: { row: RoleProfileRow }) {
  const supabase = browserSupabase()
  const meta = row.definition_json.validation_and_defensibility_metadata
  const [exporting, setExporting] = useState<string | null>(null)
  const [lastExport, setLastExport] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)

  const runExport = useCallback(async (kind: string) => {
    if (row.org_id === null) {
      setErr('Exports for global templates run org-level, not role-scoped.')
      return
    }
    setExporting(kind); setErr(null); setLastExport(null)
    const { data, error } = await supabase.rpc('rpc_role_export_assemble' as never, { p_role_id: row.id, p_kind: kind } as never)
    setExporting(null)
    if (error) setErr(error.message)
    else setLastExport(`${kind} → artifact ${String(data)}`)
  }, [supabase, row.id, row.org_id])

  return (
    <SectionAnchor id="validation">
      <Card>
        <CardEyebrow><ShieldCheck size={12} /> 11 · Validation & defensibility</CardEyebrow>
        <CardTitle>Validity status, audit trail, exports</CardTitle>
        <CardBody>
          {meta ? (
            <div className="grid lg:grid-cols-2 gap-2 text-sm mb-4">
              <Row k="Validation method" v={meta.validation_method ?? <em className="text-faint">pending</em>} />
              <Row k="Framing default" v={<Pill>{meta.framing_default ?? 'developmental'}</Pill>} />
              <Row k="SME Delphi record" v={meta.sme_delphi_record_ref ?? <em className="text-faint">pending</em>} />
              <Row k="Inter-rater agreement (ICC)" v={meta.inter_rater_agreement ?? <em className="text-faint">pending</em>} />
              <Row k="Adverse-impact log ref" v={meta.adverse_impact_log_ref ?? <em className="text-faint">pending</em>} />
              <Row k="Differential-prediction log ref" v={meta.differential_prediction_log_ref ?? <em className="text-faint">pending</em>} />
              <Row k="Last review" v={meta.last_review_date ?? <em className="text-faint">never</em>} />
              <Row k="Next review" v={meta.next_review_date ?? <em className="text-faint">unscheduled</em>} />
              <Row k="AI Act Annex IV ref" v={meta.ai_act_annex_iv_ref ?? <em className="text-faint">pending</em>} />
              <Row k="DPIA ref" v={meta.dpia_ref ?? <em className="text-faint">pending</em>} />
              <div className="lg:col-span-2"><StubPill on={Boolean(meta._dev_stub)} /></div>
            </div>
          ) : (
            <p className="text-faint text-sm mb-4"><em>No validation metadata recorded yet.</em></p>
          )}

          <div className="border-t border-line pt-3">
            <div className="text-xs uppercase tracking-wider font-bold text-muted mb-2">Assemble documents</div>
            <div className="flex flex-wrap gap-2">
              {EXPORT_KINDS.map(({ kind, label }) => (
                <Button
                  key={kind}
                  variant="ghost"
                  disabled={exporting !== null}
                  onClick={() => runExport(kind)}
                  className="border border-line"
                >
                  {exporting === kind ? <Loader2 size={12} className="animate-spin" /> : <FileDown size={12} />}
                  {label}
                </Button>
              ))}
            </div>
            <p className="text-xs text-faint mt-3">
              Documents are <strong>assembled from real logged data</strong>; the system never self-attests.
              The artifact lands as <code>sign_off_status=draft</code> + <code>self_attestation=null</code> until an external legal sign-off is recorded.
            </p>
            {lastExport && <div className="text-xs text-green-700 mt-2 font-mono">✓ {lastExport}</div>}
            {err && <div className="text-xs text-red-700 mt-2">{err}</div>}
          </div>
        </CardBody>
      </Card>
    </SectionAnchor>
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
