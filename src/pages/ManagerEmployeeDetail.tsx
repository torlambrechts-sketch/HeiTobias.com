import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import {
  Building2,
  ChevronRight,
  Loader2,
  LogOut,
  MessageCircle,
  RefreshCw,
  Shield,
  Sparkles,
  TrendingUp,
} from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Select } from '../components/ui/select.js'
import { Pill, type PillTone, StubBadge } from '../components/ui/badges.js'
import { Shell } from '../components/Shell.js'
import { HitlNotice } from '../components/HitlNotice.js'

const DEMO_USERS = [
  { email: 'linnea.strand@fjordtech.test', label: 'Linnea Strand — FjordTech people_ops_admin' },
  { email: 'erik.lund@fjordtech.test', label: 'Erik Lund — FjordTech hiring_manager' },
  { email: 'sara.vik@fjordtech.test', label: 'Sara Vik — FjordTech manager' },
] as const

const FJORDTECH_ID = 'a1000000-0000-0000-0000-000000000002'

type Person = { id: string; full_name: string; primary_email: string }
type Refit = {
  id: string
  quadrant: 'stable_fit' | 'growth_gap' | 'flight_risk' | 'emerging_misfit'
  computed_at: string
  fit_json: { overall_summary?: { competency_alignment?: { weighted_score?: number } } }
  _dev_stub: boolean
}
type Signal = {
  id: string
  kind: string
  value_json: { mean?: number; n?: number }
  source_json: { pulse_ids?: string[]; key?: string }
  generated_at: string
}
type GuidanceItem = {
  id: string
  kind: string
  framework_ids: string[]
  output_json: { items?: Array<{ framework_id: string; framework_key: string; prompt?: string; manager_prompts?: string[] }> }
  generated_at: string
  action: string | null
  action_at: string | null
  action_notes: string | null
}

export function ManagerEmployeeDetailPage() {
  const { id } = useParams<{ id: string }>()
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [selectedDemo, setSelectedDemo] = useState<string>(DEMO_USERS[0].email)
  const [authBusy, setAuthBusy] = useState(false)
  const [topErr, setTopErr] = useState<string | null>(null)

  const [person, setPerson] = useState<Person | null>(null)
  const [refitHistory, setRefitHistory] = useState<Refit[]>([])
  const [signals, setSignals] = useState<Signal[]>([])
  const [guidance, setGuidance] = useState<GuidanceItem[]>([])
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState<string | null>(null)

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
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
  }, [supabase])

  const load = useCallback(async () => {
    if (!id || !signedIn) return
    setLoading(true)
    setTopErr(null)
    const [pRes, hRes, sRes, gRes] = await Promise.all([
      supabase.from('people').select('id, full_name, primary_email').eq('id', id).maybeSingle(),
      supabase.from('refit_evaluations')
        .select('id, quadrant, computed_at, fit_json, _dev_stub')
        .eq('person_id', id).eq('org_id', FJORDTECH_ID)
        .order('computed_at', { ascending: false }).limit(20),
      supabase.from('signals')
        .select('id, kind, value_json, source_json, generated_at')
        .eq('person_id', id).eq('org_id', FJORDTECH_ID)
        .order('generated_at', { ascending: false }).limit(10),
      supabase.from('guidance_items')
        .select('id, kind, framework_ids, output_json, generated_at, action, action_at, action_notes')
        .eq('person_id', id).eq('org_id', FJORDTECH_ID)
        .order('generated_at', { ascending: false }).limit(10),
    ])
    setLoading(false)
    if (pRes.error) setTopErr(pRes.error.message)
    setPerson((pRes.data as Person) ?? null)
    setRefitHistory((hRes.data as Refit[]) ?? [])
    setSignals((sRes.data as Signal[]) ?? [])
    setGuidance((gRes.data as GuidanceItem[]) ?? [])
  }, [supabase, id, signedIn])

  useEffect(() => { void load() }, [load])

  const recompute = useCallback(async () => {
    if (!id) return
    setBusy('refit')
    const { error } = await supabase.rpc('refit_compute', { p_person_id: id, p_org_id: FJORDTECH_ID } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    else await load()
  }, [supabase, id, load])

  const recomputeSignals = useCallback(async () => {
    if (!id) return
    setBusy('signals')
    const { error } = await supabase.rpc('signal_compute', { p_person_id: id, p_org_id: FJORDTECH_ID, p_window_n: 4 } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    else await load()
  }, [supabase, id, load])

  const composeGuidance = useCallback(async (kind: 'one_on_one_prep' | 'growth_focus') => {
    if (!id) return
    setBusy('guidance')
    const latestQ = refitHistory[0]?.quadrant
    const { error } = await supabase.rpc('guidance_compose', {
      p_person_id: id,
      p_org_id: FJORDTECH_ID,
      p_kind: kind,
      p_context_json: latestQ ? { refit_quadrant: latestQ } : {},
    } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    else await load()
  }, [supabase, id, load, refitHistory])

  const recordAction = useCallback(async (itemId: string, action: 'acted_on' | 'noted' | 'snoozed' | 'dismissed') => {
    setBusy(`action:${itemId}`)
    const { error } = await supabase.rpc('guidance_record_action', {
      p_item_id: itemId, p_action: action, p_notes: null,
    } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    else await load()
  }, [supabase, load])

  if (!signedIn) {
    return (
      <main className="min-h-screen bg-canvas px-4 py-16">
        <Card className="max-w-md mx-auto">
          <CardBody>
            <CardEyebrow>Manager sign-in</CardEyebrow>
            <CardTitle className="mt-1 text-2xl">View employee's living profile</CardTitle>
            <p className="mt-3 text-sm text-muted">
              Pick a FjordTech user with scope on this employee. RLS + active{' '}
              <code className="text-xs">ongoing_management</code> consent gate everything below.
            </p>
            <div className="mt-5 space-y-3">
              <Select value={selectedDemo} onChange={(e) => setSelectedDemo(e.target.value)} className="w-full">
                {DEMO_USERS.map((u) => (
                  <option key={u.email} value={u.email}>{u.label}</option>
                ))}
              </Select>
              <Button onClick={signIn} disabled={authBusy} className="w-full">
                {authBusy ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Sign in (password: demo)'}
              </Button>
              {topErr && <p className="text-xs text-rust">{topErr}</p>}
            </div>
          </CardBody>
        </Card>
      </main>
    )
  }

  const latestRefit = refitHistory[0]
  return (
    <Shell
      breadcrumb={
        <>
          <Building2 size={14} className="text-faint" /> FjordTech <span className="text-faint">›</span>{' '}
          People <span className="text-faint">›</span>{' '}
          <b className="text-ink font-semibold">{person?.full_name ?? '…'}</b>
        </>
      }
      orgLabel="FjordTech AS"
      signedInLabel={signedIn}
    >
      <div className="flex items-start gap-4 mb-6 flex-wrap">
        <div className="flex-1 min-w-[280px]">
          <p className="eyebrow">Phase 3 · Manager workspace</p>
          <h1 className="font-display text-[40px] font-semibold tracking-tight leading-none mt-1">
            {person ? person.full_name : 'Loading…'}
          </h1>
          {person && <p className="mt-2 text-sm text-muted">{person.primary_email}</p>}
          <div className="mt-3 flex flex-wrap gap-2">
            {latestRefit && <QuadrantPill q={latestRefit.quadrant} />}
            {latestRefit?._dev_stub && <StubBadge />}
          </div>
        </div>
        <div className="ml-auto flex items-center gap-2">
          <span className="eyebrow">{signedIn}</span>
          <button onClick={signOut} className="text-xs text-muted hover:text-ink flex items-center gap-1.5">
            <LogOut className="w-3.5 h-3.5" /> sign out
          </button>
        </div>
      </div>

      {topErr && (
        <Card className="mb-4 bg-reject-bg/50">
          <CardBody className="flex items-start gap-2 py-3">
            <span className="text-sm text-rust">{topErr}</span>
          </CardBody>
        </Card>
      )}

      <div className="mb-5"><HitlNotice /></div>

      <div className="grid lg:grid-cols-2 gap-5">
        {/* Re-fit trajectory */}
        <Card>
          <CardBody>
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <div>
                <CardEyebrow>Re-fit trajectory</CardEyebrow>
                <CardTitle className="mt-1 text-2xl">Fit over time</CardTitle>
              </div>
              <Button variant="secondary" onClick={recompute} disabled={busy !== null} className="text-xs px-3 py-1.5">
                {busy === 'refit' ? <Loader2 className="w-3 h-3 animate-spin" /> : <RefreshCw className="w-3 h-3" />}
                Recompute
              </Button>
            </div>
            <p className="mt-2 text-xs text-muted">
              Append-only time-series. Each compute writes a new row; older measurements stay.
            </p>
            {loading ? (
              <p className="mt-3 eyebrow">Loading…</p>
            ) : refitHistory.length === 0 ? (
              <p className="mt-3 text-sm text-muted">No re-fit history yet. Click Recompute to add the first.</p>
            ) : (
              <div className="mt-4 flex flex-wrap gap-2">
                {refitHistory.map((r) => (
                  <div key={r.id} className="border border-line rounded p-3 bg-surface min-w-[120px] flex-1">
                    <QuadrantPill q={r.quadrant} />
                    <p className="mt-2 font-display text-2xl font-semibold">
                      {r.fit_json?.overall_summary?.competency_alignment?.weighted_score ?? '—'}
                    </p>
                    <p className="text-[11px] text-muted font-mono mt-1">
                      {new Date(r.computed_at).toLocaleDateString()}
                    </p>
                  </div>
                ))}
              </div>
            )}
          </CardBody>
        </Card>

        {/* Signals */}
        <Card>
          <CardBody>
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <div>
                <CardEyebrow>Signals (consent-gated)</CardEyebrow>
                <CardTitle className="mt-1 text-2xl">Pulse-derived trends</CardTitle>
              </div>
              <Button variant="secondary" onClick={recomputeSignals} disabled={busy !== null} className="text-xs px-3 py-1.5">
                {busy === 'signals' ? <Loader2 className="w-3 h-3 animate-spin" /> : <TrendingUp className="w-3 h-3" />}
                Recompute
              </Button>
            </div>
            <p className="mt-2 text-xs text-muted">
              Every signal cites the pulse_ids that fed it. The employee sees the same signals on
              their own self-view — no manager-only scoring.
            </p>
            {signals.length === 0 ? (
              <p className="mt-3 text-sm text-muted">No signals yet. Ask the employee to submit a pulse, then recompute.</p>
            ) : (
              <div className="mt-4 grid grid-cols-3 gap-2">
                {signals.slice(0, 3).map((s) => (
                  <div key={s.id} className="border border-line rounded p-3 bg-surface">
                    <p className="eyebrow">{s.source_json.key ?? s.kind}</p>
                    <p className="mt-1 font-display text-3xl font-semibold">{s.value_json.mean ?? '—'}</p>
                    <p className="text-[11px] text-muted font-mono mt-1">
                      n={s.value_json.n} · {(s.source_json.pulse_ids ?? []).length} pulses
                    </p>
                  </div>
                ))}
              </div>
            )}
          </CardBody>
        </Card>

        {/* Guidance */}
        <Card className="lg:col-span-2">
          <CardBody>
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <div>
                <CardEyebrow>Grounded manager guidance</CardEyebrow>
                <CardTitle className="mt-1 text-2xl">1:1 prep + growth focus</CardTitle>
              </div>
              <div className="flex gap-2">
                <Button variant="secondary" onClick={() => composeGuidance('one_on_one_prep')} disabled={busy !== null} className="text-xs px-3 py-1.5">
                  {busy === 'guidance' ? <Loader2 className="w-3 h-3 animate-spin" /> : <MessageCircle className="w-3 h-3" />}
                  Prep 1:1
                </Button>
                <Button variant="secondary" onClick={() => composeGuidance('growth_focus')} disabled={busy !== null} className="text-xs px-3 py-1.5">
                  Growth focus
                </Button>
              </div>
            </div>
            <p className="mt-2 text-xs text-muted flex items-center gap-1.5">
              <Shield className="w-3 h-3 text-role" strokeWidth={2.5} />
              Every prompt cites a framework. Suggestions inform — they never instruct.
            </p>
            {guidance.length === 0 ? (
              <p className="mt-3 text-sm text-muted">No guidance yet. Click a button above to compose.</p>
            ) : (
              <div className="mt-4 space-y-3">
                {guidance.map((g) => (
                  <GuidanceCard key={g.id} g={g} busy={busy} onAction={(a) => recordAction(g.id, a)} />
                ))}
              </div>
            )}
          </CardBody>
        </Card>
      </div>
    </Shell>
  )
}

function QuadrantPill({ q }: { q: Refit['quadrant'] }) {
  const tone: PillTone = q === 'stable_fit' ? 'open'
    : q === 'growth_gap' ? 'draft'
    : q === 'flight_risk' ? 'interview'
    : 'reject'
  const label = q.replace('_', ' ')
  return <Pill tone={tone}>{label}</Pill>
}

function GuidanceCard({ g, busy, onAction }: { g: GuidanceItem; busy: string | null; onAction: (a: 'acted_on' | 'noted' | 'snoozed' | 'dismissed') => void }) {
  const items = g.output_json.items ?? []
  return (
    <div className="border border-line rounded-lg p-4 bg-surface">
      <div className="flex items-center justify-between gap-2 flex-wrap mb-2">
        <Pill tone="interview">
          <Sparkles size={11} strokeWidth={2.5} /> {g.kind.replace(/_/g, ' ')}
        </Pill>
        <StubBadge />
      </div>
      <div className="space-y-2">
        {items.slice(0, 3).map((it, i) => (
          <div key={i} className="border-l-2 border-role pl-3 py-1">
            <p className="text-sm text-ink">{it.prompt ?? (it.manager_prompts ?? [])[0] ?? '(no prompt)'}</p>
            <p className="eyebrow mt-1 flex items-center gap-1.5">
              <ChevronRight size={11} /> grounded · {it.framework_key}
            </p>
          </div>
        ))}
      </div>
      <div className="mt-3 flex flex-wrap gap-2 items-center">
        <span className="eyebrow">Action:</span>
        {(['acted_on', 'noted', 'snoozed', 'dismissed'] as const).map((a) => (
          <button
            key={a}
            onClick={() => onAction(a)}
            disabled={busy !== null}
            className={[
              'text-[11px] uppercase font-bold tracking-wider px-2.5 py-1 rounded border',
              g.action === a
                ? 'bg-forest text-white border-forest'
                : 'bg-surface text-muted border-line-2 hover:text-ink',
            ].join(' ')}
          >
            {a.replace('_', ' ')}
          </button>
        ))}
        {g.action_at && (
          <span className="text-[11px] text-muted font-mono ml-auto">
            {g.action ? `${g.action} · ${new Date(g.action_at).toLocaleDateString()}` : ''}
          </span>
        )}
      </div>
    </div>
  )
}
