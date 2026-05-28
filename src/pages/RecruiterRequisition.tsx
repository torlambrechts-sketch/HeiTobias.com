import { useCallback, useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import {
  AlertCircle,
  Check,
  ChevronDown,
  ChevronRight,
  ClipboardCopy,
  LogOut,
  Loader2,
  Mail,
  TrendingUp,
} from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Card, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Select } from '../components/ui/select.js'
import { Table, TBody, TD, TH, THead, TR } from '../components/ui/table.js'
import { ConsentChip, StubBadge, ValidityChip } from '../components/ui/badges.js'
import { HitlNotice } from '../components/HitlNotice.js'

const DEMO_USERS = [
  { email: 'astrid.berg@nordic-recruit.test', label: 'Astrid Berg — org_admin' },
  { email: 'magnus.holm@nordic-recruit.test', label: 'Magnus Holm — recruiter' },
] as const

type Requisition = {
  id: string
  org_id: string
  role_id: string
  status: string
}
type Role = { id: string; title: string; version: number; family: string | null }
type Candidate = {
  id: string // requisition_candidates.id
  person_id: string
  stage: string
  decision: string
  fit_score_json: Record<string, unknown>
  person: { full_name: string; primary_email: string }
}
type Invite = {
  id: string
  assessment_id: string
  token: string
  expires_at: string
  used_at: string | null
  consent_recorded_id: string | null
}
type Assessment = { id: string; status: string; completed_at: string | null; instrument_key: string }
type FitResult = { id: string; fit_json: Record<string, unknown>; validity_status: string; computed_at: string }
type Decision = {
  id: string
  decision: string
  rationale: string
  overrode_recommendation: boolean
  decided_at: string
}

type CandidateView = Candidate & {
  invite: Invite | null
  assessment: Assessment | null
  fit: FitResult | null
  latest_decision: Decision | null
  port_consent_id: string | null
}

export function RecruiterRequisitionPage() {
  const { id } = useParams<{ id: string }>()
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [authBusy, setAuthBusy] = useState(false)
  const [selectedDemo, setSelectedDemo] = useState<string>(DEMO_USERS[0].email)
  const [req, setReq] = useState<Requisition | null>(null)
  const [role, setRole] = useState<Role | null>(null)
  const [candidates, setCandidates] = useState<CandidateView[]>([])
  const [topErr, setTopErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState<string | null>(null)

  // ----- auth -----
  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setSignedIn(data.session?.user?.email ?? null)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      setSignedIn(s?.user?.email ?? null)
    })
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  const signIn = useCallback(async () => {
    setAuthBusy(true)
    setTopErr(null)
    const { error } = await supabase.auth.signInWithPassword({ email: selectedDemo, password: 'demo' })
    setAuthBusy(false)
    if (error) setTopErr(`Sign-in failed: ${error.message}`)
  }, [supabase, selectedDemo])

  const signOut = useCallback(async () => {
    await supabase.auth.signOut()
    setReq(null)
    setRole(null)
    setCandidates([])
  }, [supabase])

  // ----- data -----
  const load = useCallback(async () => {
    if (!id || !signedIn) return
    setLoading(true)
    setTopErr(null)

    const { data: r, error: rErr } = await supabase
      .from('requisitions')
      .select('id, org_id, role_id, status')
      .eq('id', id)
      .maybeSingle()
    if (rErr || !r) {
      setTopErr(rErr?.message ?? 'Requisition not visible at your RLS scope.')
      setLoading(false)
      return
    }
    setReq(r)

    const { data: rc } = await supabase
      .from('roles_catalog')
      .select('id, title, version, family')
      .eq('id', r.role_id)
      .maybeSingle()
    setRole(rc ?? null)

    const { data: rcs } = await supabase
      .from('requisition_candidates')
      .select('id, person_id, stage, decision, fit_score_json, person:people(full_name, primary_email)')
      .eq('requisition_id', id)
      .order('created_at', { ascending: true })

    const candidateRows = (rcs ?? []) as unknown as Candidate[]
    if (candidateRows.length === 0) {
      setCandidates([])
      setLoading(false)
      return
    }

    const personIds = candidateRows.map((c) => c.person_id)
    const [invitesRes, assessmentsRes, fitsRes, decisionsRes, consentsRes] = await Promise.all([
      supabase
        .from('assessment_invites')
        .select('id, assessment_id, token, expires_at, used_at, consent_recorded_id, person_id')
        .in('person_id', personIds)
        .eq('org_id', r.org_id),
      supabase.from('assessments').select('id, status, completed_at, instrument_key, person_id').in('person_id', personIds).eq('org_id', r.org_id),
      supabase.from('fit_results').select('id, fit_json, validity_status, computed_at, person_id').in('person_id', personIds).eq('requisition_id', id),
      supabase
        .from('hiring_decisions')
        .select('id, decision, rationale, overrode_recommendation, decided_at, requisition_candidate_id')
        .in('requisition_candidate_id', candidateRows.map((c) => c.id))
        .order('decided_at', { ascending: false }),
      supabase
        .from('consent_grants')
        .select('id, person_id, purpose, status')
        .in('person_id', personIds)
        .eq('purpose', 'profile_portability')
        .eq('status', 'active'),
    ])

    const invitesByPerson = new Map<string, Invite>()
    for (const i of (invitesRes.data ?? []) as Array<Invite & { person_id: string }>) {
      // most recent wins
      const cur = invitesByPerson.get(i.person_id)
      if (!cur || new Date(i.expires_at) > new Date(cur.expires_at)) invitesByPerson.set(i.person_id, i)
    }
    const assessmentByPerson = new Map<string, Assessment>()
    for (const a of (assessmentsRes.data ?? []) as Array<Assessment & { person_id: string }>) {
      assessmentByPerson.set(a.person_id, a)
    }
    const fitByPerson = new Map<string, FitResult>()
    for (const f of (fitsRes.data ?? []) as Array<FitResult & { person_id: string }>) {
      fitByPerson.set(f.person_id, f)
    }
    const decisionByRc = new Map<string, Decision>()
    for (const d of (decisionsRes.data ?? []) as Array<Decision & { requisition_candidate_id: string }>) {
      if (!decisionByRc.has(d.requisition_candidate_id)) decisionByRc.set(d.requisition_candidate_id, d)
    }
    const portConsentByPerson = new Map<string, string>()
    for (const c of (consentsRes.data ?? []) as Array<{ id: string; person_id: string }>) {
      portConsentByPerson.set(c.person_id, c.id)
    }

    setCandidates(
      candidateRows.map((c) => ({
        ...c,
        invite: invitesByPerson.get(c.person_id) ?? null,
        assessment: assessmentByPerson.get(c.person_id) ?? null,
        fit: fitByPerson.get(c.person_id) ?? null,
        latest_decision: decisionByRc.get(c.id) ?? null,
        port_consent_id: portConsentByPerson.get(c.person_id) ?? null,
      })),
    )
    setLoading(false)
  }, [supabase, id, signedIn])

  useEffect(() => {
    void load()
  }, [load])

  // ----- actions -----
  const wrap = useCallback(
    async (key: string, fn: () => Promise<void>) => {
      setBusy(key)
      setTopErr(null)
      try {
        await fn()
        await load()
      } catch (e) {
        setTopErr(e instanceof Error ? e.message : String(e))
      }
      setBusy(null)
    },
    [load],
  )

  const invite = (c: CandidateView) =>
    wrap(`invite:${c.id}`, async () => {
      if (!req) throw new Error('no requisition')
      const { error } = await supabase.rpc('assessment_invite_create', {
        p_org_id: req.org_id,
        p_person_id: c.person_id,
        p_instrument_key: 'sample_personality_v0',
      } as never)
      if (error) throw error
    })
  const computeFit = (c: CandidateView) =>
    wrap(`fit:${c.id}`, async () => {
      const { error } = await supabase.rpc('compute_fit_for_candidate', {
        p_requisition_id: id!,
        p_person_id: c.person_id,
      } as never)
      if (error) throw error
    })
  const generateReport = (c: CandidateView) =>
    wrap(`report:${c.id}`, async () => {
      const { data, error } = await supabase.rpc('placement_report_generate', {
        p_requisition_id: id!,
        p_person_id: c.person_id,
      } as never)
      if (error) throw error
      const reportId = data as unknown as string
      const { data: rep } = await supabase.from('placement_reports').select('report_html').eq('id', reportId).maybeSingle()
      if (rep?.report_html) {
        const w = window.open('', '_blank')
        if (w) {
          w.document.write(rep.report_html)
          w.document.close()
        }
      }
    })
  const recordDecision = (c: CandidateView, decision: string, rationale: string) =>
    wrap(`decision:${c.id}`, async () => {
      if (rationale.trim().length === 0) throw new Error('Rationale is required.')
      const { error } = await supabase.rpc('hiring_decision_record', {
        p_requisition_id: id!,
        p_person_id: c.person_id,
        p_decision: decision,
        p_rationale: rationale,
        p_overrode_recommendation: false,
      } as never)
      if (error) throw error
    })
  const place = (c: CandidateView, toOrgId: string) =>
    wrap(`place:${c.id}`, async () => {
      if (!c.port_consent_id) throw new Error('Candidate has no active profile_portability consent.')
      const { error } = await supabase.rpc('placement_execute', {
        p_requisition_id: id!,
        p_person_id: c.person_id,
        p_to_org_id: toOrgId,
        p_consent_id: c.port_consent_id,
      } as never)
      if (error) throw error
    })

  // ----- render -----
  if (!signedIn) {
    return (
      <Shell>
        <Card className="max-w-md mx-auto">
          <CardEyebrow>Phase 0 sign-in</CardEyebrow>
          <CardTitle className="mt-1">Sign in to drive the requisition</CardTitle>
          <p className="mt-3 font-body text-sm text-muted">
            Pick a seeded recruiter. RLS filters everything you see by their org + role.
          </p>
          <div className="mt-4 space-y-3">
            <Select value={selectedDemo} onChange={(e) => setSelectedDemo(e.target.value)} className="w-full">
              {DEMO_USERS.map((u) => (
                <option key={u.email} value={u.email}>
                  {u.label}
                </option>
              ))}
            </Select>
            <Button onClick={signIn} disabled={authBusy} className="w-full">
              {authBusy ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Sign in (password: demo)'}
            </Button>
            {topErr && <p className="font-body text-xs text-accent">{topErr}</p>}
          </div>
        </Card>
      </Shell>
    )
  }

  return (
    <Shell>
      <header className="flex items-start justify-between flex-wrap gap-3 mb-6">
        <div>
          <p className="font-mono text-[0.65rem] uppercase tracking-wider text-muted">Phase 1 · Requisition</p>
          <h1 className="font-display text-3xl text-ink mt-1">
            {role ? role.title : 'Loading…'}
            {role && <span className="ml-2 font-mono text-base text-muted">v{role.version}</span>}
          </h1>
          <p className="mt-1 font-body text-sm text-muted">
            Status:{' '}
            <span className="font-mono text-xs uppercase tracking-wider">
              {req?.status ?? '—'}
            </span>
          </p>
        </div>
        <div className="flex items-center gap-3">
          <p className="font-mono text-[0.65rem] uppercase tracking-wider text-muted">{signedIn}</p>
          <Button variant="ghost" onClick={signOut} className="text-xs">
            <LogOut className="w-3.5 h-3.5" /> sign out
          </Button>
        </div>
      </header>

      {topErr && (
        <div className="mb-4 border-l-4 border-accent bg-paper p-3 rounded text-sm text-accent flex items-start gap-2">
          <AlertCircle className="w-4 h-4 mt-0.5" /> {topErr}
        </div>
      )}

      <div className="mb-4">
        <HitlNotice />
      </div>

      {loading ? (
        <p className="font-mono text-xs uppercase tracking-wider text-muted">Loading…</p>
      ) : candidates.length === 0 ? (
        <Card>
          <p className="font-body text-sm text-muted">
            No candidates on this requisition yet. (Use SQL to add one; an "add candidate" UI is
            out of scope for this demo slice.)
          </p>
        </Card>
      ) : (
        <div className="space-y-4">
          {candidates.map((c) => (
            <CandidateRow
              key={c.id}
              c={c}
              busy={busy}
              onInvite={() => invite(c)}
              onComputeFit={() => computeFit(c)}
              onGenerateReport={() => generateReport(c)}
              onDecide={(d, r) => recordDecision(c, d, r)}
              onPlace={(toOrg) => place(c, toOrg)}
            />
          ))}
        </div>
      )}
    </Shell>
  )
}

function CandidateRow({
  c,
  busy,
  onInvite,
  onComputeFit,
  onGenerateReport,
  onDecide,
  onPlace,
}: {
  c: CandidateView
  busy: string | null
  onInvite: () => void
  onComputeFit: () => void
  onGenerateReport: () => void
  onDecide: (d: string, r: string) => void
  onPlace: (toOrgId: string) => void
}) {
  const [showDecide, setShowDecide] = useState(false)
  const [decision, setDecision] = useState<'advance' | 'hire' | 'reject' | 'withdraw'>('advance')
  const [rationale, setRationale] = useState('')
  const [showPlace, setShowPlace] = useState(false)
  const [toOrg, setToOrg] = useState('a1000000-0000-0000-0000-000000000002')
  const [showToken, setShowToken] = useState(false)
  const [copied, setCopied] = useState(false)

  const stub = useMemo(() => (c.fit?.fit_json as { _dev_stub?: boolean })?._dev_stub === true, [c.fit])
  const weighted = useMemo(() => {
    const summary = c.fit?.fit_json as { overall_summary?: { competency_alignment?: { weighted_score?: number } } } | undefined
    return summary?.overall_summary?.competency_alignment?.weighted_score ?? null
  }, [c.fit])

  const tokenUrl = c.invite ? `${window.location.origin}/take/${c.invite.token}` : null

  return (
    <Card className="border-person/40">
      <header className="flex items-start justify-between flex-wrap gap-2 mb-4">
        <div>
          <CardEyebrow>Candidate · {c.stage}</CardEyebrow>
          <CardTitle className="mt-1">{c.person.full_name}</CardTitle>
          <p className="font-mono text-xs text-muted mt-0.5">{c.person.primary_email}</p>
        </div>
        <div className="flex flex-wrap gap-2 items-center">
          {c.fit && <ValidityChip status={c.fit.validity_status as 'dev_stub'} />}
          {c.port_consent_id ? (
            <ConsentChip active={true} purpose="profile_portability" />
          ) : (
            <ConsentChip active={false} purpose="profile_portability" />
          )}
        </div>
      </header>

      <Table>
        <THead>
          <TR>
            <TH>Assessment</TH>
            <TH>Fit</TH>
            <TH>Decision</TH>
          </TR>
        </THead>
        <TBody>
          <TR>
            <TD>
              {c.assessment ? (
                <span className="font-mono text-xs uppercase tracking-wider">
                  {c.assessment.status}
                </span>
              ) : (
                <span className="text-muted text-xs">not invited</span>
              )}
            </TD>
            <TD>
              {c.fit ? (
                <span className="flex items-center gap-2">
                  <TrendingUp className="w-4 h-4 text-person" />
                  <span className="font-display text-lg text-ink">{weighted ?? '—'}</span>
                  {stub && <StubBadge />}
                </span>
              ) : (
                <span className="text-muted text-xs">not computed</span>
              )}
            </TD>
            <TD>
              {c.latest_decision ? (
                <span className="font-mono text-xs uppercase tracking-wider">
                  {c.latest_decision.decision}
                </span>
              ) : (
                <span className="text-muted text-xs">pending</span>
              )}
            </TD>
          </TR>
        </TBody>
      </Table>

      {tokenUrl && (
        <div className="mt-4 border border-dashed border-hairline rounded p-3">
          <button
            onClick={() => setShowToken((v) => !v)}
            className="flex items-center gap-2 font-mono text-[0.7rem] uppercase tracking-wider text-muted hover:text-ink"
          >
            {showToken ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
            Invite magic link {c.invite?.used_at ? '· used' : ''}
          </button>
          {showToken && (
            <div className="mt-2 flex items-center gap-2">
              <code className="font-mono text-xs text-ink break-all flex-1">{tokenUrl}</code>
              <Button
                variant="secondary"
                onClick={() => {
                  void navigator.clipboard.writeText(tokenUrl)
                  setCopied(true)
                  setTimeout(() => setCopied(false), 1500)
                }}
                className="text-xs"
              >
                {copied ? <Check className="w-3 h-3" /> : <ClipboardCopy className="w-3 h-3" />}
                {copied ? 'copied' : 'copy'}
              </Button>
            </div>
          )}
        </div>
      )}

      <div className="mt-4 flex flex-wrap gap-2">
        <Button variant="secondary" onClick={onInvite} disabled={busy === `invite:${c.id}`} className="text-xs">
          {busy === `invite:${c.id}` ? <Loader2 className="w-3 h-3 animate-spin" /> : <Mail className="w-3 h-3" />}
          Invite to assess
        </Button>
        <Button
          variant="secondary"
          onClick={onComputeFit}
          disabled={!c.assessment || c.assessment.status !== 'completed' || busy === `fit:${c.id}`}
          className="text-xs"
        >
          {busy === `fit:${c.id}` ? <Loader2 className="w-3 h-3 animate-spin" /> : null}
          Compute fit
        </Button>
        <Button
          variant="secondary"
          onClick={onGenerateReport}
          disabled={!c.fit || busy === `report:${c.id}`}
          className="text-xs"
        >
          {busy === `report:${c.id}` ? <Loader2 className="w-3 h-3 animate-spin" /> : null}
          Generate report
        </Button>
        <Button variant="secondary" onClick={() => setShowDecide((v) => !v)} className="text-xs">
          Record decision
        </Button>
        <Button
          variant="secondary"
          onClick={() => setShowPlace((v) => !v)}
          disabled={!c.port_consent_id || c.latest_decision?.decision !== 'hire'}
          className="text-xs"
        >
          Place
        </Button>
      </div>

      {showDecide && (
        <div className="mt-4 border-2 border-ink rounded p-4 bg-paper">
          <p className="eyebrow mb-2">Record human decision</p>
          <div className="grid sm:grid-cols-[160px_1fr] gap-3 items-start">
            <Select value={decision} onChange={(e) => setDecision(e.target.value as never)}>
              <option value="advance">advance</option>
              <option value="hire">hire</option>
              <option value="reject">reject</option>
              <option value="withdraw">withdraw</option>
            </Select>
            <textarea
              value={rationale}
              onChange={(e) => setRationale(e.target.value)}
              placeholder="Rationale (required). Describe what informed this decision."
              rows={3}
              className="w-full border-2 border-ink rounded p-2 font-body text-sm bg-surface"
            />
          </div>
          <div className="mt-3 flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setShowDecide(false)} className="text-xs">
              cancel
            </Button>
            <Button
              onClick={() => {
                onDecide(decision, rationale)
                setShowDecide(false)
                setRationale('')
              }}
              disabled={rationale.trim().length === 0 || busy === `decision:${c.id}`}
              className="text-xs"
            >
              {busy === `decision:${c.id}` ? <Loader2 className="w-3 h-3 animate-spin" /> : null}
              Record decision
            </Button>
          </div>
        </div>
      )}

      {showPlace && (
        <div className="mt-4 border-2 border-role rounded p-4 bg-paper">
          <p className="eyebrow mb-2">Place into employer org (Phase 0 hand-off RPC)</p>
          <p className="font-body text-xs text-muted mb-3">
            Requires latest decision = <code>hire</code> + active <code>profile_portability</code>{' '}
            consent. Atomic with: agency membership → removed, candidate stage → placed, requisition → placed.
          </p>
          <Select value={toOrg} onChange={(e) => setToOrg(e.target.value)} className="w-full mb-3">
            <option value="a1000000-0000-0000-0000-000000000002">FjordTech AS (seeded employer)</option>
          </Select>
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setShowPlace(false)} className="text-xs">
              cancel
            </Button>
            <Button onClick={() => { onPlace(toOrg); setShowPlace(false) }} disabled={busy === `place:${c.id}`} className="text-xs">
              {busy === `place:${c.id}` ? <Loader2 className="w-3 h-3 animate-spin" /> : null}
              Execute placement
            </Button>
          </div>
        </div>
      )}
    </Card>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-paper px-4 py-8">
      <div className="max-w-4xl mx-auto">{children}</div>
    </main>
  )
}
