import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Check, ChevronRight, Loader2, MessageCircle, Shield, Sparkles, TrendingUp, X } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Select } from '../components/ui/select.js'
import { ConsentChip, Pill, type PillTone, StubBadge } from '../components/ui/badges.js'

type ConsentPurpose = 'hiring_decision' | 'profile_portability' | 'ongoing_management' | 'research_anonymized'

type Grant = {
  id: string
  org_id: string
  org_name: string
  org_type: 'agency' | 'employer'
  purpose: ConsentPurpose
  status: 'active' | 'revoked' | 'expired'
  legal_basis: string
  scope_json: Record<string, unknown>
  granted_at: string
  revoked_at: string | null
  expires_at: string | null
}

type Employer = { id: string; name: string }

type State = {
  person: { id: string; full_name: string; primary_email: string }
  grants: Grant[]
  employers: Employer[]
}

type LifecycleSelfView = {
  pulses:   Array<{ id: string; submitted_at: string; org_id: string; body_json: { answers?: Array<{ key: string; value: number }> } }>
  signals:  Array<{ id: string; kind: string; value_json: { mean?: number; n?: number }; source_json: { key?: string; pulse_ids?: string[] }; generated_at: string; _dev_stub: boolean }>
  refit:    Array<{ id: string; quadrant: 'stable_fit' | 'growth_gap' | 'flight_risk' | 'emerging_misfit'; computed_at: string; fit_json: { overall_summary?: { competency_alignment?: { weighted_score?: number } } }; _dev_stub: boolean }>
  guidance: Array<{ id: string; kind: string; output_json: { items?: Array<{ framework_key: string; prompt?: string }> }; action: string | null; action_at: string | null; generated_at: string }>
  outcomes: Array<{ id: string; kind: string; happened_at: string; notes: string | null }>
}

export function CandidateConsentsPage() {
  const { token } = useParams<{ token: string }>()
  const supabase = browserSupabase()

  const [state, setState] = useState<State | null>(null)
  const [lifecycle, setLifecycle] = useState<LifecycleSelfView | null>(null)
  const [errMsg, setErrMsg] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState<string | null>(null)
  const [selectedEmployer, setSelectedEmployer] = useState<string>('')

  const load = useCallback(async () => {
    if (!token) {
      setErrMsg('Missing consent token in URL.')
      setLoading(false)
      return
    }
    const [stateRes, lifecycleRes] = await Promise.all([
      supabase.rpc('consent_dashboard_state', { p_token: token }),
      supabase.rpc('lifecycle_self_view',     { p_token: token } as never),
    ])
    if (stateRes.error) {
      setErrMsg(stateRes.error.message)
      setLoading(false)
      return
    }
    const s = stateRes.data as unknown as State
    setState(s)
    setLifecycle((lifecycleRes.data as unknown as LifecycleSelfView) ?? null)
    if (s.employers.length > 0 && !selectedEmployer) {
      setSelectedEmployer(s.employers[0]!.id)
    }
    setLoading(false)
  }, [supabase, token, selectedEmployer])

  useEffect(() => {
    void load()
  }, [load])

  const grantPortability = useCallback(async () => {
    if (!token || !selectedEmployer) return
    setBusy('grant')
    setErrMsg(null)
    const { error } = await supabase.rpc('portability_grant', {
      p_token: token,
      p_employer_org_id: selectedEmployer,
    } as never)
    setBusy(null)
    if (error) {
      setErrMsg(error.message)
      return
    }
    await load()
  }, [supabase, token, selectedEmployer, load])

  const revoke = useCallback(
    async (consentId: string) => {
      if (!token) return
      setBusy(`revoke:${consentId}`)
      setErrMsg(null)
      const { error } = await supabase.rpc('consent_revoke', {
        p_token: token,
        p_consent_id: consentId,
      } as never)
      setBusy(null)
      if (error) {
        setErrMsg(error.message)
        return
      }
      await load()
    },
    [supabase, token, load],
  )

  if (loading) {
    return (
      <Shell>
        <div className="min-h-[50vh] flex flex-col items-center justify-center">
          <Loader2 className="w-6 h-6 animate-spin text-muted" />
          <p className="eyebrow mt-3">Loading your consents…</p>
        </div>
      </Shell>
    )
  }

  if (errMsg && !state) {
    return (
      <Shell>
        <Card className="max-w-md mx-auto">
          <CardBody>
            <CardEyebrow className="text-rust">Consent dashboard problem</CardEyebrow>
            <CardTitle className="mt-1 text-xl">We couldn't open your consents</CardTitle>
            <p className="mt-3 text-sm text-muted">{errMsg}</p>
            <p className="mt-3 text-xs text-muted">
              The link may have expired. Ask your recruiter to send a fresh one.
            </p>
          </CardBody>
        </Card>
      </Shell>
    )
  }

  if (!state) return null

  const activePortability = state.grants.filter(
    (g) => g.purpose === 'profile_portability' && g.status === 'active',
  )
  const otherGrants = state.grants.filter((g) => !(g.purpose === 'profile_portability' && g.status === 'active'))

  // Employer orgs the candidate hasn't already granted to.
  const grantableEmployers = state.employers.filter(
    (e) => !activePortability.some((g) => g.org_id === e.id),
  )

  return (
    <Shell>
      <div className="max-w-2xl mx-auto space-y-5">
        <Card>
          <CardBody>
            <CardEyebrow>Consent dashboard</CardEyebrow>
            <CardTitle className="mt-1 text-3xl">Your profile is yours.</CardTitle>
            <p className="mt-3 text-sm text-ink leading-relaxed">
              Hi <strong>{state.person.full_name}</strong>. Below is every consent you've granted —
              and you can revoke any of them at any time. Revoking a consent immediately removes
              the corresponding access; we log it in our immutable audit trail.
            </p>
          </CardBody>
        </Card>

        {errMsg && (
          <Card className="border-rust/40 bg-reject-bg/30">
            <CardBody className="flex items-start gap-2 py-3">
              <X className="w-4 h-4 text-rust mt-0.5" />
              <span className="text-sm text-rust">{errMsg}</span>
            </CardBody>
          </Card>
        )}

        <Card>
          <CardBody>
            <div className="flex items-center justify-between mb-1">
              <CardEyebrow>Grant your profile to an employer</CardEyebrow>
              <Shield className="w-4 h-4 text-role" strokeWidth={2} />
            </div>
            <CardTitle className="text-xl">Portable profile</CardTitle>
            <p className="mt-2 text-sm text-muted leading-relaxed">
              If you want a named employer to see the profile your recruiter built with you, grant
              them a <code className="text-xs bg-canvas-2 px-1 py-0.5 rounded">profile_portability</code>{' '}
              consent. They'll only see what this consent permits, for as long as it's active.
            </p>

            {grantableEmployers.length > 0 ? (
              <div className="mt-4 flex flex-col sm:flex-row gap-2">
                <Select
                  value={selectedEmployer}
                  onChange={(e) => setSelectedEmployer(e.target.value)}
                  className="sm:flex-1"
                >
                  {grantableEmployers.map((e) => (
                    <option key={e.id} value={e.id}>
                      {e.name}
                    </option>
                  ))}
                </Select>
                <button
                  onClick={grantPortability}
                  disabled={busy !== null || !selectedEmployer}
                  className="bg-forest hover:bg-forest-2 text-white px-5 py-2.5 rounded text-sm font-semibold flex items-center justify-center gap-2 disabled:opacity-50"
                >
                  {busy === 'grant' ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
                  Grant portability
                </button>
              </div>
            ) : (
              <p className="mt-4 text-xs text-muted italic">
                You've already granted portability to every available employer.
              </p>
            )}
          </CardBody>
        </Card>

        {activePortability.length > 0 && (
          <Card>
            <CardBody>
              <CardEyebrow>Active portability grants</CardEyebrow>
              <CardTitle className="text-xl mt-1">Who can receive your profile right now</CardTitle>
              <div className="mt-4 space-y-3">
                {activePortability.map((g) => (
                  <GrantRow key={g.id} g={g} onRevoke={() => revoke(g.id)} busy={busy} />
                ))}
              </div>
            </CardBody>
          </Card>
        )}

        {otherGrants.length > 0 && (
          <Card>
            <CardBody>
              <CardEyebrow>Full consent ledger</CardEyebrow>
              <CardTitle className="text-xl mt-1">Every consent on your record</CardTitle>
              <p className="mt-2 text-xs text-muted">
                Including hiring_decision (used by recruiters to consider you for a role) and
                revoked grants — the audit trail is permanent even after revocation.
              </p>
              <div className="mt-4 space-y-3">
                {otherGrants.map((g) => (
                  <GrantRow key={g.id} g={g} onRevoke={() => revoke(g.id)} busy={busy} />
                ))}
              </div>
            </CardBody>
          </Card>
        )}

        {lifecycle && (lifecycle.pulses.length + lifecycle.signals.length + lifecycle.refit.length + lifecycle.guidance.length > 0) && (
          <LifecycleSection lifecycle={lifecycle} />
        )}
      </div>
    </Shell>
  )
}

function LifecycleSection({ lifecycle }: { lifecycle: LifecycleSelfView }) {
  const latestRefit = lifecycle.refit[0]
  const quadrantTone = (q: LifecycleSelfView['refit'][number]['quadrant']): PillTone =>
    q === 'stable_fit' ? 'open'
      : q === 'growth_gap' ? 'draft'
      : q === 'flight_risk' ? 'interview'
      : 'reject'
  return (
    <Card>
      <CardBody>
        <div className="flex items-center justify-between gap-2 flex-wrap mb-1">
          <CardEyebrow>Lifecycle · what your manager sees</CardEyebrow>
          <Shield className="w-4 h-4 text-role" strokeWidth={2} />
        </div>
        <CardTitle className="text-xl">Your living profile</CardTitle>
        <p className="mt-2 text-xs text-muted leading-relaxed">
          The exact same data and signals your manager has visibility into. There is no
          manager-only score about you. To stop all of this immediately, revoke the
          {' '}<code className="text-xs">ongoing_management</code>{' '} consent above.
        </p>

        {latestRefit && (
          <div className="mt-5 border border-line rounded-lg p-4 bg-canvas/40">
            <div className="flex items-center gap-2 flex-wrap mb-2">
              <CardEyebrow>Latest re-fit</CardEyebrow>
              <Pill tone={quadrantTone(latestRefit.quadrant)}>{latestRefit.quadrant.replace('_', ' ')}</Pill>
              {latestRefit._dev_stub && <StubBadge />}
            </div>
            <p className="font-display text-3xl font-semibold mt-1">
              {latestRefit.fit_json?.overall_summary?.competency_alignment?.weighted_score ?? '—'}
            </p>
            <p className="text-[11px] text-muted font-mono mt-1">
              measured {new Date(latestRefit.computed_at).toLocaleDateString()} ·
              full history: {lifecycle.refit.length} measurement{lifecycle.refit.length === 1 ? '' : 's'}
            </p>
          </div>
        )}

        {lifecycle.signals.length > 0 && (
          <div className="mt-4">
            <p className="eyebrow flex items-center gap-1.5"><TrendingUp className="w-3.5 h-3.5" /> Signals from your pulses</p>
            <div className="mt-2 grid grid-cols-3 gap-2">
              {lifecycle.signals.slice(0, 3).map((s) => (
                <div key={s.id} className="border border-line rounded p-3 bg-surface">
                  <p className="eyebrow">{s.source_json.key ?? s.kind}</p>
                  <p className="mt-1 font-display text-2xl font-semibold">{s.value_json.mean ?? '—'}</p>
                  <p className="text-[10px] text-muted font-mono mt-1">n={s.value_json.n}</p>
                </div>
              ))}
            </div>
          </div>
        )}

        {lifecycle.guidance.length > 0 && (
          <div className="mt-4">
            <p className="eyebrow flex items-center gap-1.5"><MessageCircle className="w-3.5 h-3.5" /> Guidance written about you</p>
            <p className="text-[11px] text-muted mt-1">Grounded in framework citations · informing, not deciding.</p>
            <div className="mt-2 space-y-2">
              {lifecycle.guidance.slice(0, 3).map((g) => {
                const firstItem = (g.output_json.items ?? [])[0]
                return (
                  <div key={g.id} className="border border-line rounded p-3 bg-surface">
                    <div className="flex items-center justify-between gap-2 flex-wrap">
                      <Pill tone="interview"><Sparkles size={11} strokeWidth={2.5} /> {g.kind.replace(/_/g, ' ')}</Pill>
                      {g.action && <span className="eyebrow">action: {g.action.replace('_', ' ')}</span>}
                    </div>
                    {firstItem && (
                      <p className="mt-2 text-sm text-ink">{firstItem.prompt ?? '(no prompt)'}</p>
                    )}
                    {firstItem?.framework_key && (
                      <p className="eyebrow mt-1 flex items-center gap-1.5">
                        <ChevronRight size={11} /> grounded · {firstItem.framework_key}
                      </p>
                    )}
                  </div>
                )
              })}
            </div>
          </div>
        )}

        <p className="eyebrow flex items-center gap-1.5 mt-5 pt-3 border-t border-dashed border-line">
          <Shield className="w-3 h-3" strokeWidth={2.5} /> Developmental, never surveillance — same view your manager has
        </p>
      </CardBody>
    </Card>
  )
}

function GrantRow({
  g,
  onRevoke,
  busy,
}: {
  g: Grant
  onRevoke: () => void
  busy: string | null
}) {
  const purposeTone = purposePillTone(g.purpose)
  const isActive = g.status === 'active'
  return (
    <div className="border border-line rounded-lg px-4 py-3 bg-canvas/50">
      <div className="flex items-start gap-3 flex-wrap">
        <div className="flex-1 min-w-[180px]">
          <p className="font-semibold text-ink">{g.org_name}</p>
          <p className="text-xs text-muted mt-0.5 uppercase tracking-wider">{g.org_type}</p>
          <div className="flex flex-wrap gap-1.5 mt-2">
            <Pill tone={purposeTone}>{g.purpose.replace('_', ' ')}</Pill>
            <ConsentChip active={isActive} purpose={g.purpose.replace('_', ' ')} />
          </div>
          <p className="text-[11px] text-muted mt-2 font-mono">
            granted {new Date(g.granted_at).toLocaleDateString()}
            {g.revoked_at && ` · revoked ${new Date(g.revoked_at).toLocaleDateString()}`}
          </p>
        </div>
        {isActive && (
          <button
            onClick={onRevoke}
            disabled={busy !== null}
            className="text-xs text-rust hover:underline font-semibold flex items-center gap-1.5 disabled:opacity-50"
          >
            {busy === `revoke:${g.id}` ? <Loader2 className="w-3 h-3 animate-spin" /> : <X className="w-3.5 h-3.5" />}
            Revoke
          </button>
        )}
      </div>
    </div>
  )
}

function purposePillTone(purpose: ConsentPurpose): PillTone {
  switch (purpose) {
    case 'hiring_decision':       return 'internal'
    case 'profile_portability':   return 'interview'
    case 'ongoing_management':    return 'offer'
    case 'research_anonymized':   return 'draft'
  }
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-canvas px-4 py-8 sm:py-12">
      <header className="max-w-2xl mx-auto mb-6 flex items-center gap-3">
        <span className="w-10 h-10 rounded-lg bg-forest text-white flex items-center justify-center font-display font-bold text-xl">
          T
        </span>
        <div>
          <p className="eyebrow">HeiTobias</p>
          <p className="font-display text-lg text-ink leading-tight">Your consents</p>
        </div>
      </header>
      {children}
      <footer className="max-w-2xl mx-auto mt-8 pt-5 border-t border-line">
        <p className="eyebrow flex items-center gap-1.5">
          <Shield className="w-3 h-3" strokeWidth={2.5} />
          EU-region hosted · purpose-limited · revocable · audited
        </p>
        <p className="text-[11px] text-muted mt-2 flex items-center gap-1.5">
          <ChevronRight className="w-3 h-3" />
          Every action on this page is logged. Revoking a consent removes the corresponding access
          immediately.
        </p>
      </footer>
    </main>
  )
}
