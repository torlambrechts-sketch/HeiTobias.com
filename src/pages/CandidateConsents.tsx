import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Check, ChevronRight, Loader2, Shield, X } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Select } from '../components/ui/select.js'
import { ConsentChip, Pill, type PillTone } from '../components/ui/badges.js'

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

export function CandidateConsentsPage() {
  const { token } = useParams<{ token: string }>()
  const supabase = browserSupabase()

  const [state, setState] = useState<State | null>(null)
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
    const { data, error } = await supabase.rpc('consent_dashboard_state', { p_token: token })
    if (error) {
      setErrMsg(error.message)
      setLoading(false)
      return
    }
    const s = data as unknown as State
    setState(s)
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
      </div>
    </Shell>
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
