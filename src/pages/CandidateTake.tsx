import { useCallback, useEffect, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import { AlertTriangle, ArrowRight, Check, Loader2, Shield, Timer } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { ValidityChip, Pill } from '../components/ui/badges.js'

// ============================================================
// Unified candidate assessment session (/take/<token>)
//
// Four sections in one continuous flow with shared session state:
//   1. Consent (existing)
//   2. Personality   (existing personality items via assessment_take_state)
//   3. Cognitive     (new, timed, no back-button)
//   4. Values        (new, Likert-6)
//   5. Structured-interview prep (new, STAR free-text per competency)
//   6. Completion (existing; recruiter handoff)
//
// Demo mode (?demo=true): abbreviated item counts on every section AND
// a persistent banner. The demo_mode flag is recorded server-side so
// recruiters see it on the candidate detail surface — no recruiter can
// mistake a demo session for production.
//
// Dev-stub discipline: every rendered item carries _dev_stub=true; the
// ValidityChip shows dev_stub adjacent to every score / item. Real
// items + IRT calibration land per H-1 / H-2.
// ============================================================

type SectionKey = 'personality' | 'cognitive' | 'values' | 'structured_prep'

type SessionItem = {
  id: string
  key: string
  prompt: string
  item_json: { choices?: number[]; time_limit_seconds?: number; scale_anchor_low?: string; scale_anchor_high?: string }
  _dev_stub: boolean
  answered: boolean
}
type PrepItem = { key: string; label: string; prompt_text: string; response_text: string; answered: boolean }

type SectionSummary = {
  items?: SessionItem[]
  total: number
  answered: number
  _dev_stub: boolean
  validity_status?: string
  methodology_note?: string
}

type PrepSectionSummary = Omit<SectionSummary, 'items'> & {
  items: PrepItem[]
  methodology_note?: string
}

type SessionState = {
  session_id: string
  invite_token: string
  demo_mode: boolean
  status: 'initializing' | 'in_progress' | 'completed' | 'abandoned'
  org_id: string
  person_id: string
  consent_captured: boolean
  expires_at: string
  sections: {
    cognitive: SectionSummary
    values: SectionSummary
    structured_prep: PrepSectionSummary
  }
}

type LegacyTakeItem = { id: string; key: string; prompt: string; choices: number[] | null; _dev_stub: boolean; answered: boolean }
type LegacyTakeState = {
  invite_id: string
  assessment_id: string
  instrument_name: string
  validity_status: 'dev_stub' | 'licensed' | 'validated'
  consent_captured: boolean
  completed: boolean
  expires_at: string
  items: LegacyTakeItem[]
}

type Brand = { org_id: string | null; org_name: string | null; accent_color: string | null; logo_url: string | null }

type Phase = 'loading' | 'error' | 'consent' | 'personality' | 'cognitive' | 'values' | 'structured_prep' | 'completed'

const SECTION_ORDER: SectionKey[] = ['personality', 'cognitive', 'values', 'structured_prep']

export function CandidateTakePage() {
  const { token } = useParams<{ token: string }>()
  const [searchParams] = useSearchParams()
  const demoParam = searchParams.get('demo') === 'true'
  const supabase = browserSupabase()

  const [phase, setPhase] = useState<Phase>('loading')
  const [errMsg, setErrMsg] = useState<string | null>(null)
  const [brand, setBrand] = useState<Brand | null>(null)
  const [legacy, setLegacy] = useState<LegacyTakeState | null>(null)
  const [session, setSession] = useState<SessionState | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [consentDashToken, setConsentDashToken] = useState<string | null>(null)

  // Initialise session + load both the legacy take state (for personality)
  // and the new session state (cognitive / values / prep).
  const refresh = useCallback(async () => {
    if (!token) { setErrMsg('Missing invite token in URL.'); setPhase('error'); return }
    // 1. Ensure session row exists (idempotent)
    const { error: initErr } = await supabase.rpc('assessment_session_init' as never, { p_token: token, p_demo: demoParam } as never)
    if (initErr) { setErrMsg(initErr.message); setPhase('error'); return }
    // 2. Read legacy take state (personality items + consent + completion)
    const { data: legacyData, error: legacyErr } = await supabase.rpc('assessment_take_state', { p_token: token })
    if (legacyErr) { setErrMsg(legacyErr.message); setPhase('error'); return }
    const ls = legacyData as unknown as LegacyTakeState
    setLegacy(ls)
    // 3. Read session state
    const { data: sessData, error: sessErr } = await supabase.rpc('assessment_session_state' as never, { p_token: token } as never)
    if (sessErr) { setErrMsg(sessErr.message); setPhase('error'); return }
    const ss = sessData as unknown as SessionState
    setSession(ss)
    // 4. Consent token (for the post-completion dashboard link)
    if (ls.consent_captured) {
      const { data: ct } = await supabase.rpc('consent_token_for_invite', { p_invite_token: token })
      if (ct) setConsentDashToken(ct as unknown as string)
    }
    // 5. Pick current phase
    if (ss.status === 'completed' || ls.completed) { setPhase('completed'); return }
    if (!ls.consent_captured) { setPhase('consent'); return }
    // First incomplete section is the current phase
    for (const sec of SECTION_ORDER) {
      if (sec === 'personality') {
        const allAnswered = ls.items.every(i => i.answered)
        if (!allAnswered) { setPhase('personality'); return }
        continue
      }
      const summary = ss.sections[sec as keyof typeof ss.sections]
      if (!summary) { setPhase(sec); return }
      if (summary.answered < summary.total) { setPhase(sec); return }
    }
    setPhase('completed')
  }, [supabase, token, demoParam])

  useEffect(() => { void refresh() }, [refresh])
  useEffect(() => {
    if (!token) return
    void supabase.rpc('assessment_take_brand' as never, { p_token: token } as never)
      .then(({ data }) => { if (data) setBrand(data as unknown as Brand) })
  }, [supabase, token])

  // Section completion + advance helper
  const markSectionDone = useCallback(async (section: SectionKey) => {
    if (!token) return
    await supabase.rpc('assessment_session_mark_section' as never, { p_token: token, p_section: section } as never)
    await refresh()
  }, [supabase, token, refresh])

  // ---------- Common chrome ----------
  if (phase === 'loading') {
    return <Shell><Loading /></Shell>
  }
  if (phase === 'error') {
    return <Shell><ErrorCard msg={errMsg ?? 'Unknown error.'} /></Shell>
  }
  if (!legacy || !session) return null

  const showDemoBanner = session.demo_mode

  // ---------- Section content ----------
  if (phase === 'consent') {
    return (
      <Shell>
        <BrandStrip brand={brand} />
        {showDemoBanner && <DemoBanner />}
        <Card className="max-w-lg mx-auto">
          <CardBody>
            <div className="flex items-center justify-between flex-wrap gap-2">
              <CardEyebrow>Consent · purpose-limited</CardEyebrow>
              <ValidityChip status="dev_stub" />
            </div>
            <CardTitle className="mt-2 text-3xl">Your profile is yours.</CardTitle>
            <p className="mt-4 text-sm text-ink leading-relaxed">
              We need your consent to process your responses for one specific purpose:
              <strong> hiring_decision</strong>. This session includes four parts:
            </p>
            <ul className="mt-4 space-y-2 text-sm text-ink">
              <li className="flex gap-2.5"><Check className="w-4 h-4 mt-0.5 text-green flex-shrink-0" strokeWidth={2.5} /> <span>Personality (short questions about you)</span></li>
              <li className="flex gap-2.5"><Check className="w-4 h-4 mt-0.5 text-green flex-shrink-0" strokeWidth={2.5} /> <span>Cognitive (timed pattern items — no back button)</span></li>
              <li className="flex gap-2.5"><Check className="w-4 h-4 mt-0.5 text-green flex-shrink-0" strokeWidth={2.5} /> <span>Values (how similar are you to short personality portraits)</span></li>
              <li className="flex gap-2.5"><Check className="w-4 h-4 mt-0.5 text-green flex-shrink-0" strokeWidth={2.5} /> <span>Structured-interview prep (a few short written examples)</span></li>
            </ul>
            <p className="mt-4 text-xs text-muted leading-relaxed">
              Honest length: a real session runs 45–75 minutes. {showDemoBanner ? 'This walkthrough is in DEMO MODE with abbreviated counts.' : 'You can save and resume across all parts.'}
            </p>
            <ul className="mt-5 space-y-2.5 text-sm text-ink">
              {['Purpose-limited to the role you applied for.',
                'You can revoke at any time. Revocation removes recruiter access immediately.',
                'Data stored in the EU region only.',
                'Every access is logged in an immutable audit trail.',
              ].map((line) => (
                <li key={line} className="flex gap-2.5"><Check className="w-4 h-4 mt-0.5 text-green flex-shrink-0" strokeWidth={2.5} /><span>{line}</span></li>
              ))}
            </ul>
            <div className="mt-7 flex flex-col gap-3">
              <button
                onClick={async () => {
                  if (!token) return
                  setSubmitting(true)
                  const { error } = await supabase.rpc('assessment_capture_consent', { p_token: token })
                  setSubmitting(false)
                  if (error) { setErrMsg(error.message); setPhase('error'); return }
                  await refresh()
                }}
                disabled={submitting}
                className="w-full bg-forest hover:bg-forest-2 text-white py-3.5 rounded font-semibold flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : 'I consent — start the assessment'}
              </button>
              <p className="eyebrow text-center">Closing without consenting stores nothing.</p>
            </div>
          </CardBody>
        </Card>
      </Shell>
    )
  }

  if (phase === 'completed') {
    return (
      <Shell>
        <BrandStrip brand={brand} />
        {showDemoBanner && <DemoBanner />}
        <Card className="max-w-md mx-auto">
          <CardBody>
            <CardEyebrow>Assessment complete</CardEyebrow>
            <CardTitle className="mt-1 text-2xl">Thanks for finishing.</CardTitle>
            <p className="mt-3 text-sm text-muted leading-relaxed">
              Your responses are scored and shared — under your active consent — with the team you
              applied through. You can revoke this consent at any time.
            </p>
            {consentDashToken && (
              <div className="mt-5 border-t border-line pt-5">
                <p className="eyebrow mb-2">Your profile is yours</p>
                <p className="text-sm text-ink leading-relaxed">
                  Review every consent on your record — and revoke any of them at any time — from your consent dashboard.
                </p>
                <Link to={`/me/${consentDashToken}`} className="mt-3 inline-flex items-center gap-2 text-green font-bold text-xs uppercase tracking-wider hover:underline">
                  <Shield className="w-3.5 h-3.5" strokeWidth={2} /> Open my consent dashboard
                </Link>
              </div>
            )}
          </CardBody>
        </Card>
      </Shell>
    )
  }

  return (
    <Shell>
      <BrandStrip brand={brand} />
      {showDemoBanner && <DemoBanner />}
      <SessionProgress legacy={legacy} session={session} phase={phase} />
      <div className="max-w-lg mx-auto">
        {phase === 'personality' && <PersonalitySection token={token!} legacy={legacy} supabase={supabase} onComplete={() => markSectionDone('personality')} onSubmit={refresh} />}
        {phase === 'cognitive'   && <CognitiveSection   token={token!} section={session.sections.cognitive} supabase={supabase} onComplete={() => markSectionDone('cognitive')} onSubmit={refresh} />}
        {phase === 'values'      && <ValuesSection      token={token!} section={session.sections.values}    supabase={supabase} onComplete={() => markSectionDone('values')}    onSubmit={refresh} />}
        {phase === 'structured_prep' && <PrepSection    token={token!} section={session.sections.structured_prep} supabase={supabase} onComplete={() => markSectionDone('structured_prep')} onSubmit={refresh} />}
      </div>
    </Shell>
  )
}

// ============================================================
// Sub-components
// ============================================================

function SessionProgress({ legacy, session, phase }: { legacy: LegacyTakeState; session: SessionState; phase: Phase }) {
  const personalityAnswered = legacy.items.filter(i => i.answered).length
  const personalityTotal = legacy.items.length
  const items: { key: SectionKey; label: string; answered: number; total: number }[] = [
    { key: 'personality',     label: 'Personality',  answered: personalityAnswered, total: personalityTotal },
    { key: 'cognitive',       label: 'Cognitive',    answered: session.sections.cognitive.answered, total: session.sections.cognitive.total },
    { key: 'values',          label: 'Values',       answered: session.sections.values.answered,    total: session.sections.values.total },
    { key: 'structured_prep', label: 'Interview prep', answered: session.sections.structured_prep.answered, total: session.sections.structured_prep.total },
  ]
  return (
    <div className="max-w-lg mx-auto mb-4">
      <div className="flex items-center gap-2 text-xs">
        {items.map((s, i) => {
          const active = s.key === phase
          const done = s.answered >= s.total && s.total > 0
          return (
            <div key={s.key} className="flex items-center gap-1.5 flex-1">
              <span className={'w-5 h-5 rounded-full flex items-center justify-center font-bold text-[10px] ' +
                (done ? 'bg-green text-white' : active ? 'bg-forest text-white' : 'bg-canvas-2 text-muted')}>
                {done ? '✓' : i + 1}
              </span>
              <span className={'font-semibold ' + (active ? 'text-ink' : 'text-muted')}>{s.label}</span>
              <span className="text-faint font-mono">{s.answered}/{s.total}</span>
              {i < items.length - 1 && <span className="text-faint">·</span>}
            </div>
          )
        })}
      </div>
    </div>
  )
}

function PersonalitySection({ token, legacy, supabase, onComplete, onSubmit }: {
  token: string; legacy: LegacyTakeState
  supabase: ReturnType<typeof browserSupabase>
  onComplete: () => void; onSubmit: () => Promise<void>
}) {
  const [submitting, setSubmitting] = useState(false)
  const remaining = legacy.items.filter(i => !i.answered)
  const current = remaining[0]
  const total = legacy.items.length
  const done = total - remaining.length

  useEffect(() => {
    if (!current && total > 0) void onComplete()
  }, [current, total, onComplete])

  if (!current) {
    return (
      <Card><CardBody>
        <CardEyebrow>Personality complete</CardEyebrow>
        <p className="text-sm text-muted mt-2">Advancing to the next section…</p>
      </CardBody></Card>
    )
  }
  const submit = async (value: number) => {
    setSubmitting(true)
    await supabase.rpc('assessment_submit_response', { p_token: token, p_item_id: current.id, p_response_json: { value } as never })
    setSubmitting(false)
    await onSubmit()
  }
  return (
    <Card>
      <CardBody>
        <div className="flex items-center justify-between flex-wrap gap-2">
          <CardEyebrow>Personality · {done + 1} of {total}</CardEyebrow>
          <ValidityChip status="dev_stub" />
        </div>
        <h2 className="mt-3 font-display text-2xl leading-snug text-ink">{current.prompt}</h2>
        <p className="mt-2 eyebrow">1 = strongly disagree · 5 = strongly agree</p>
        <div className="mt-6 grid grid-cols-5 gap-2.5">
          {(current.choices ?? [1,2,3,4,5]).map(v => (
            <button key={v} disabled={submitting} onClick={() => void submit(v)}
              className="aspect-square rounded border border-line-2 font-display text-3xl font-semibold bg-surface text-ink hover:bg-forest hover:text-white hover:border-forest active:translate-y-px disabled:opacity-50 transition-colors">
              {v}
            </button>
          ))}
        </div>
      </CardBody>
    </Card>
  )
}

function CognitiveSection({ token, section, supabase, onComplete, onSubmit }: {
  token: string; section: SectionSummary
  supabase: ReturnType<typeof browserSupabase>
  onComplete: () => void; onSubmit: () => Promise<void>
}) {
  const [submitting, setSubmitting] = useState(false)
  const items = section.items ?? []
  const current = items.find(i => !i.answered)
  const total = items.length
  const done = items.filter(i => i.answered).length

  // per-item timer (production discipline: cognitive is time-limited)
  const timeLimit = current?.item_json?.time_limit_seconds ?? 90
  const [seconds, setSeconds] = useState(timeLimit)
  useEffect(() => { setSeconds(timeLimit) }, [current?.id, timeLimit])
  useEffect(() => {
    if (!current) return
    const t = setInterval(() => setSeconds(s => Math.max(0, s - 1)), 1000)
    return () => clearInterval(t)
  }, [current])

  useEffect(() => {
    if (!current && total > 0) void onComplete()
  }, [current, total, onComplete])

  if (!current) {
    return (
      <Card><CardBody>
        <CardEyebrow>Cognitive complete</CardEyebrow>
        <p className="text-sm text-muted mt-2">Advancing to the next section…</p>
      </CardBody></Card>
    )
  }
  const submit = async (value: number) => {
    setSubmitting(true)
    await supabase.rpc('assessment_session_submit_item' as never,
      { p_token: token, p_item_id: current.id, p_value: value } as never)
    setSubmitting(false)
    await onSubmit()
  }
  return (
    <Card>
      <CardBody>
        <div className="flex items-center justify-between flex-wrap gap-2">
          <CardEyebrow>Cognitive · {done + 1} of {total}</CardEyebrow>
          <div className="flex items-center gap-2">
            <span className="inline-flex items-center gap-1 text-xs font-mono text-amber"><Timer size={12} /> {seconds}s</span>
            <ValidityChip status="dev_stub" />
          </div>
        </div>
        <h2 className="mt-3 font-display text-xl leading-snug text-ink">{current.prompt}</h2>
        <p className="mt-2 text-xs text-rust">No back button — cognitive sections are anti-revision by design.</p>
        <div className="mt-6 grid grid-cols-5 gap-2.5">
          {(current.item_json.choices ?? [1,2,3,4,5]).map(v => (
            <button key={v} disabled={submitting || seconds === 0} onClick={() => void submit(v)}
              className="aspect-square rounded border border-line-2 font-display text-3xl font-semibold bg-surface text-ink hover:bg-forest hover:text-white hover:border-forest disabled:opacity-50 transition-colors">
              {v}
            </button>
          ))}
        </div>
      </CardBody>
    </Card>
  )
}

function ValuesSection({ token, section, supabase, onComplete, onSubmit }: {
  token: string; section: SectionSummary
  supabase: ReturnType<typeof browserSupabase>
  onComplete: () => void; onSubmit: () => Promise<void>
}) {
  const [submitting, setSubmitting] = useState(false)
  const items = section.items ?? []
  const current = items.find(i => !i.answered)
  const total = items.length
  const done = items.filter(i => i.answered).length

  useEffect(() => { if (!current && total > 0) void onComplete() }, [current, total, onComplete])

  if (!current) {
    return <Card><CardBody><CardEyebrow>Values complete</CardEyebrow><p className="text-sm text-muted mt-2">Advancing…</p></CardBody></Card>
  }
  const submit = async (value: number) => {
    setSubmitting(true)
    await supabase.rpc('assessment_session_submit_item' as never,
      { p_token: token, p_item_id: current.id, p_value: value } as never)
    setSubmitting(false)
    await onSubmit()
  }
  const lo = current.item_json.scale_anchor_low  ?? 'Not at all like me'
  const hi = current.item_json.scale_anchor_high ?? 'Very much like me'
  return (
    <Card>
      <CardBody>
        <div className="flex items-center justify-between flex-wrap gap-2">
          <CardEyebrow>Values · {done + 1} of {total}</CardEyebrow>
          <ValidityChip status="dev_stub" />
        </div>
        <h2 className="mt-3 font-display text-lg leading-snug text-ink">{current.prompt}</h2>
        <div className="mt-2 flex items-center justify-between text-[10.5px] uppercase tracking-wider font-bold text-muted">
          <span>{lo}</span><span>{hi}</span>
        </div>
        <div className="mt-3 grid grid-cols-6 gap-2">
          {(current.item_json.choices ?? [1,2,3,4,5,6]).map(v => (
            <button key={v} disabled={submitting} onClick={() => void submit(v)}
              className="aspect-square rounded border border-line-2 font-display text-2xl font-semibold bg-surface text-ink hover:bg-forest hover:text-white hover:border-forest disabled:opacity-50 transition-colors">
              {v}
            </button>
          ))}
        </div>
      </CardBody>
    </Card>
  )
}

function PrepSection({ token, section, supabase, onComplete, onSubmit }: {
  token: string; section: PrepSectionSummary
  supabase: ReturnType<typeof browserSupabase>
  onComplete: () => void; onSubmit: () => Promise<void>
}) {
  const items = section.items
  const current = items.find(i => !i.answered)
  const total = items.length
  const done = items.filter(i => i.answered).length
  const [text, setText] = useState('')
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => { setText(current?.response_text ?? '') }, [current?.key])
  useEffect(() => { if (!current && total > 0) void onComplete() }, [current, total, onComplete])

  if (!current) {
    return <Card><CardBody><CardEyebrow>Structured-interview prep complete</CardEyebrow><p className="text-sm text-muted mt-2">Wrapping up the session…</p></CardBody></Card>
  }
  const submit = async () => {
    if (text.trim().length < 20) return
    setSubmitting(true)
    await supabase.rpc('assessment_session_submit_prep' as never,
      { p_token: token, p_competency_key: current.key, p_response_text: text.trim() } as never)
    setSubmitting(false)
    setText('')
    await onSubmit()
  }
  return (
    <Card>
      <CardBody>
        <div className="flex items-center justify-between flex-wrap gap-2">
          <CardEyebrow>Structured-interview prep · {done + 1} of {total}</CardEyebrow>
          <ValidityChip status="dev_stub" />
        </div>
        {section.methodology_note && (
          <div className="mt-3 rounded border border-role border-l-4 border-l-role bg-interview-bg p-3 text-xs text-ink/90 leading-relaxed">
            <strong>Why this section exists.</strong> {section.methodology_note}
          </div>
        )}
        <h2 className="mt-4 font-display text-xl leading-snug text-ink">{current.label}</h2>
        <p className="mt-2 text-sm text-muted leading-relaxed">{current.prompt_text}</p>
        <textarea
          value={text} onChange={e => setText(e.target.value)}
          rows={8} placeholder="Situation, Task, Action, Result — 200-400 characters."
          className="mt-3 w-full border border-line rounded px-3 py-2 text-sm font-body"
        />
        <div className="mt-2 flex items-center justify-between text-xs">
          <span className={'font-mono ' + (text.trim().length >= 20 ? 'text-green' : 'text-faint')}>
            {text.trim().length} chars (min 20)
          </span>
          <button onClick={submit} disabled={submitting || text.trim().length < 20}
            className="bg-forest hover:bg-forest-2 text-white px-4 py-2 rounded text-sm font-semibold flex items-center gap-1.5 disabled:opacity-50">
            {submitting ? <Loader2 size={12} className="animate-spin" /> : <ArrowRight size={12} />} Save &amp; continue
          </button>
        </div>
      </CardBody>
    </Card>
  )
}

// ============================================================
// Common chrome
// ============================================================

function BrandStrip({ brand }: { brand: Brand | null }) {
  if (!brand?.org_name) return null
  const accent = brand.accent_color ?? '#3a4d3f'
  return (
    <div data-test="brand-strip" className="max-w-lg mx-auto flex items-center gap-3 px-4 py-3 border-b border-line mb-4" style={{ borderTop: `3px solid ${accent}` }}>
      {brand.logo_url && <img src={brand.logo_url} alt={`${brand.org_name ?? 'Inviting org'} logo`} className="h-8 w-auto" />}
      <div>
        <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Invited by</div>
        <div className="text-sm font-semibold" style={{ color: accent }}>{brand.org_name}</div>
      </div>
    </div>
  )
}

function DemoBanner() {
  return (
    <div data-test="demo-banner" className="max-w-lg mx-auto rounded border border-amber bg-internal-bg/60 px-4 py-2.5 mb-4 flex items-center gap-2 text-xs text-internal-fg">
      <AlertTriangle size={14} className="flex-shrink-0" />
      <span>
        <strong>Demo mode — abbreviated for walkthrough.</strong>{' '}
        Production session uses full item counts and takes 45–75 minutes.
      </span>
      <Pill tone="reject" className="ml-auto">demo</Pill>
    </div>
  )
}

function Loading() {
  return (
    <div className="min-h-[50vh] flex flex-col items-center justify-center">
      <Loader2 className="w-6 h-6 animate-spin text-muted" />
      <p className="eyebrow mt-3">Loading…</p>
    </div>
  )
}

function ErrorCard({ msg }: { msg: string }) {
  return (
    <Card className="max-w-md mx-auto">
      <CardBody>
        <CardEyebrow className="text-rust">Invite problem</CardEyebrow>
        <CardTitle className="mt-1 text-xl">We couldn't open this assessment</CardTitle>
        <p className="mt-3 text-sm text-muted">{msg}</p>
        <p className="mt-3 text-xs text-muted">If your link expired, ask your recruiter to send a new one.</p>
      </CardBody>
    </Card>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-canvas px-4 py-8 sm:py-12">
      <header className="max-w-lg mx-auto mb-6 flex items-center gap-3">
        <span className="w-9 h-9 rounded-lg bg-forest text-white flex items-center justify-center font-display font-bold text-lg">T</span>
        <div>
          <p className="eyebrow">HeiTobias</p>
          <p className="font-display text-base text-ink leading-tight">Candidate assessment session</p>
        </div>
      </header>
      {children}
      <footer className="max-w-lg mx-auto mt-8 pt-5 border-t border-line">
        <p className="eyebrow flex items-center gap-1.5">
          <Shield className="w-3 h-3" strokeWidth={2.5} />
          EU-region hosted · purpose-limited · revocable · audited
        </p>
      </footer>
    </main>
  )
}
