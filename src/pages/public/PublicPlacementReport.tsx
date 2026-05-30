import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Loader2 } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { PublicShareFrame, ShareError } from '../../components/public/PublicShareFrame.js'
import { StubBadge } from '../../components/ui/badges.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /public/placement-report/:token — field-stripped public placement
// report. public_placement_report_view() strips recruiter free-text
// notes server-side; only the structured recommendation, fit summary,
// methodology callout, and fairness status are visible. dev_stub label
// stays visible. The candidate can revoke this share from /me/privacy.

type ReportView = {
  ok: boolean
  reason?: string
  shared_by_org?: string
  shared_at?: string
  validity_status?: string
  dev_stub?: boolean
  generated_at?: string
  version?: number
  report?: Record<string, unknown>
}

export function PublicPlacementReportPage() {
  usePageTitle('Shared placement report')
  const { token } = useParams<{ token: string }>()
  const supabase = browserSupabase()
  const [view, setView] = useState<ReportView | null>(null)

  useEffect(() => {
    if (!token) return
    void (async () => {
      const { data, error } = await supabase.rpc('public_placement_report_view' as never, {
        p_token: token, p_ua: navigator.userAgent,
      } as never)
      if (error) { setView({ ok: false, reason: error.message }); return }
      setView(data as unknown as ReportView)
    })()
  }, [supabase, token])

  if (!view) {
    return <div className="min-h-screen flex items-center justify-center text-muted text-sm"><Loader2 className="animate-spin mr-2" size={16} /> Loading shared report…</div>
  }
  if (!view.ok) return <ShareError reason={view.reason} />

  const report = view.report ?? {}
  const recommendation = report.recommendation_summary as string | undefined
  const candidate = report.candidate as { name?: string; anonymized?: boolean } | undefined
  const role = report.role as { title?: string } | undefined
  const fit = report.fit_summary as Record<string, unknown> | undefined
  const fairness = report.fairness_status as { four_fifths?: string; note?: string } | undefined

  return (
    <PublicShareFrame sharedByOrg={view.shared_by_org} sharedAt={view.shared_at} kind="placement report">
      <div className="flex items-baseline gap-3 flex-wrap">
        <h1 className="font-display text-3xl font-bold">Placement report</h1>
        {view.dev_stub && <StubBadge />}
      </div>
      <p className="text-sm text-muted mt-1">
        {candidate?.anonymized === false && candidate?.name ? candidate.name : 'Candidate (anonymised)'}
        {role?.title ? ` · for ${role.title}` : ''}
      </p>

      <div className="mt-4 rounded-lg border-l-2 border-forest bg-canvas-2 px-4 py-3 text-sm">
        <strong>Human decision required.</strong> This report informs a hiring decision. It does
        not make one — a named human records the decision with rationale.
      </div>

      {recommendation && (
        <Section title="Structured recommendation">
          <p className="text-sm leading-relaxed">{recommendation}</p>
        </Section>
      )}

      {fit && (
        <Section title="Fit summary">
          <ul className="flex flex-col gap-1.5 text-sm">
            {Object.entries(fit).map(([k, v]) => (
              <li key={k} className="flex justify-between border-b border-line py-1">
                <span className="text-muted">{k.replace(/_/g, ' ')}</span>
                <span className="font-mono text-xs">{typeof v === 'object' ? JSON.stringify(v) : String(v)}</span>
              </li>
            ))}
          </ul>
          {view.dev_stub && (
            <p className="text-xs text-faint mt-2">
              Fit values are <code>dev_stub</code> — the scoring is pending I/O-psychology
              validation. They illustrate the structure, not a validated result.
            </p>
          )}
        </Section>
      )}

      {fairness && (
        <Section title="Fairness status">
          <p className="text-sm">Four-fifths inspection: <strong>{fairness.four_fifths ?? '—'}</strong></p>
          {fairness.note && <p className="text-xs text-muted mt-1">{fairness.note}</p>}
          <p className="text-xs text-faint mt-2">
            Fairness figures are a computation surfaced for expert interpretation — not a
            system verdict of acceptability.
          </p>
        </Section>
      )}

      <Section title="Methodology">
        <p className="text-sm text-muted leading-relaxed">
          This report combines structured-interview preparation, an assessment session, and
          role-fit signals. The strongest single predictor weighted here is the structured
          interview (Sackett et al. 2022). All values carry provenance labels; nothing is
          presented as validated until expert sign-off.
        </p>
      </Section>
    </PublicShareFrame>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-6">
      <h2 className="font-display text-lg font-semibold border-b border-line pb-1 mb-2">{title}</h2>
      {children}
    </section>
  )
}
