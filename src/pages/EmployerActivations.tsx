import { useCallback, useEffect, useState } from 'react'
import { ArrowRight, Briefcase, Building2, Check, ChevronDown, ChevronRight, Loader2, LogOut, Shield, Sparkles } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Select } from '../components/ui/select.js'
import { ConsentChip, Pill, RoleBadge, StubBadge } from '../components/ui/badges.js'
import { TabBand, Tab } from '../components/ui/tabband.js'
import { Shell } from '../components/Shell.js'
import { HitlNotice } from '../components/HitlNotice.js'

const DEMO_USERS = [
  { email: 'linnea.strand@fjordtech.test', label: 'Linnea Strand — FjordTech people_ops_admin' },
  { email: 'erik.lund@fjordtech.test',     label: 'Erik Lund — FjordTech hiring_manager' },
] as const

const FJORDTECH_ID = 'a1000000-0000-0000-0000-000000000002'

type PlacementRow = {
  placement_id: string
  person_id: string
  person_name: string
  person_email: string
  from_org_id: string
  from_org_name: string
  transferred_at: string
  status: string
  activated: boolean
  ongoing_consent_id: string | null
}

export function EmployerActivationsPage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [selectedDemo, setSelectedDemo] = useState<string>(DEMO_USERS[0].email)
  const [authBusy, setAuthBusy] = useState(false)
  const [rows, setRows] = useState<PlacementRow[]>([])
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState<string | null>(null)
  const [topErr, setTopErr] = useState<string | null>(null)

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
    setRows([])
  }, [supabase])

  const load = useCallback(async () => {
    if (!signedIn) return
    setLoading(true)
    setTopErr(null)
    const { data, error } = await supabase.rpc('employer_activations_state', { p_org_id: FJORDTECH_ID })
    setLoading(false)
    if (error) {
      setTopErr(error.message)
      return
    }
    const s = data as unknown as { placements: PlacementRow[] }
    setRows(s.placements ?? [])
  }, [supabase, signedIn])

  useEffect(() => {
    void load()
  }, [load])

  const activate = useCallback(
    async (placementId: string) => {
      setBusy(`activate:${placementId}`)
      setTopErr(null)
      const { error } = await supabase.rpc('placement_activate', { p_placement_id: placementId } as never)
      setBusy(null)
      if (error) {
        setTopErr(error.message)
        return
      }
      await load()
    },
    [supabase, load],
  )

  if (!signedIn) {
    return (
      <main className="min-h-screen bg-canvas px-4 py-16">
        <Card className="max-w-md mx-auto">
          <CardBody>
            <CardEyebrow>Employer sign-in</CardEyebrow>
            <CardTitle className="mt-1 text-2xl">Activate inherited candidates</CardTitle>
            <p className="mt-3 text-sm text-muted">
              Pick a seeded FjordTech employer user. RLS filters everything by their org.
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

  const unactivated = rows.filter((r) => !r.activated)
  const activated = rows.filter((r) => r.activated)

  return (
    <Shell
      breadcrumb={
        <>
          <Building2 size={14} className="text-faint" /> FjordTech <span className="text-faint">›</span>{' '}
          <b className="text-ink font-semibold">Activations</b>
        </>
      }
      orgLabel="FjordTech AS"
      signedInLabel={signedIn}
    >
      <div className="flex items-center gap-4 mb-6 flex-wrap">
        <div>
          <p className="eyebrow">Phase 2 · Employer</p>
          <h1 className="font-display text-[40px] font-semibold tracking-tight leading-none mt-1">
            Inherited candidates
          </h1>
          <p className="mt-2 text-sm text-muted max-w-2xl leading-relaxed">
            Candidates placed at FjordTech via the consent-gated hand-off. The profile is already
            here — you just need to capture an{' '}
            <code className="text-xs bg-canvas-2 px-1.5 py-0.5 rounded">ongoing_management</code>{' '}
            consent (legal basis: employment contract) before any post-hire surface can read it.
          </p>
        </div>
        <div className="ml-auto flex items-center gap-2">
          <span className="eyebrow">{signedIn}</span>
          <button
            onClick={signOut}
            className="text-xs text-muted hover:text-ink flex items-center gap-1.5"
          >
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

      <div className="mb-5">
        <HitlNotice />
      </div>

      <TabBand>
        <Tab active>
          <Briefcase size={15} strokeWidth={2} /> Activations ({rows.length})
        </Tab>
      </TabBand>

      <Card attached>
        {loading ? (
          <div className="px-6 py-12 text-center eyebrow">Loading…</div>
        ) : rows.length === 0 ? (
          <div className="px-6 py-12 text-center">
            <Briefcase className="w-8 h-8 text-faint mx-auto mb-2" />
            <p className="text-sm text-muted">
              No inherited candidates yet. Run a placement from the agency-side recruiter desk to
              see one here.
            </p>
          </div>
        ) : (
          <div className="divide-y divide-line">
            {unactivated.length > 0 && (
              <div className="px-6 pt-4 pb-2">
                <p className="eyebrow">Needs activation · {unactivated.length}</p>
              </div>
            )}
            {unactivated.map((r) => (
              <PlacementRowView key={r.placement_id} r={r} busy={busy} onActivate={() => activate(r.placement_id)} />
            ))}
            {activated.length > 0 && (
              <div className="px-6 pt-4 pb-2">
                <p className="eyebrow">Active employees · {activated.length}</p>
              </div>
            )}
            {activated.map((r) => (
              <PlacementRowView key={r.placement_id} r={r} busy={busy} onActivate={() => activate(r.placement_id)} />
            ))}
          </div>
        )}
      </Card>
    </Shell>
  )
}

function PlacementRowView({
  r,
  busy,
  onActivate,
}: {
  r: PlacementRow
  busy: string | null
  onActivate: () => void
}) {
  const supabase = browserSupabase()
  const [planVisible, setPlanVisible] = useState(false)
  const [planLoading, setPlanLoading] = useState(false)
  const [plan, setPlan] = useState<KickstartPlan | null>(null)
  const [planErr, setPlanErr] = useState<string | null>(null)

  const loadPlan = useCallback(async () => {
    setPlanLoading(true)
    setPlanErr(null)
    const { data, error } = await supabase
      .from('kickstart_plans')
      .select('id, plan_json, validity_status, generated_at')
      .eq('person_id', r.person_id)
      .eq('org_id', FJORDTECH_ID)
      .order('generated_at', { ascending: false })
      .limit(1)
      .maybeSingle()
    setPlanLoading(false)
    if (error) {
      setPlanErr(error.message)
      return
    }
    setPlan((data as unknown as KickstartPlan) ?? null)
  }, [supabase, r.person_id])

  const generatePlan = useCallback(async () => {
    setPlanLoading(true)
    setPlanErr(null)
    const { error } = await supabase.rpc('kickstart_generate', {
      p_person_id: r.person_id,
      p_org_id: FJORDTECH_ID,
    } as never)
    setPlanLoading(false)
    if (error) {
      setPlanErr(error.message)
      return
    }
    await loadPlan()
    setPlanVisible(true)
  }, [supabase, r.person_id, loadPlan])

  useEffect(() => {
    if (r.activated && planVisible && !plan) void loadPlan()
  }, [r.activated, planVisible, plan, loadPlan])

  return (
    <div className="px-6 py-5 hover:bg-canvas transition-colors">
      <div className="flex items-start gap-4 flex-wrap">
        <div className="flex-1 min-w-[220px]">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="font-semibold text-ink text-[15px]">{r.person_name}</p>
            {!r.activated && (
              <Pill tone="interview">
                <ArrowRight size={11} strokeWidth={2.5} /> New arrival
              </Pill>
            )}
          </div>
          <p className="text-xs text-muted mt-0.5">{r.person_email}</p>
          <p className="mt-2 text-xs text-muted flex items-center gap-2 flex-wrap">
            <Building2 className="w-3.5 h-3.5 text-faint" />
            <span>from <strong className="text-ink">{r.from_org_name}</strong></span>
            <span className="text-faint">•</span>
            <span>placed {new Date(r.transferred_at).toLocaleDateString()}</span>
          </p>
          <div className="mt-2.5 flex flex-wrap gap-1.5">
            <ConsentChip active={r.activated} purpose="ongoing_management" />
          </div>
        </div>

        <div className="flex items-center gap-3 ml-auto flex-wrap">
          {r.activated ? (
            <span className="flex items-center gap-1.5 text-xs text-person font-semibold">
              <Check className="w-3.5 h-3.5" strokeWidth={2.5} />
              Activated
            </span>
          ) : (
            <button
              onClick={onActivate}
              disabled={busy !== null}
              className="bg-forest hover:bg-forest-2 text-white px-4 py-2 rounded text-xs font-bold uppercase tracking-wider flex items-center justify-center gap-2 disabled:opacity-50"
            >
              {busy === `activate:${r.placement_id}` ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <Shield className="w-3.5 h-3.5" strokeWidth={2} />
              )}
              Activate
            </button>
          )}
        </div>
      </div>

      {r.activated && (
        <div className="mt-4 border border-line rounded-lg p-3.5 bg-canvas/40">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <button
              onClick={() => {
                if (!planVisible && !plan) void loadPlan()
                setPlanVisible((v) => !v)
              }}
              className="flex items-center gap-2 eyebrow hover:text-ink"
            >
              {planVisible ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
              <Sparkles size={13} className="text-amber" strokeWidth={2} />
              90-day kickstart plan
            </button>
            <button
              onClick={generatePlan}
              disabled={planLoading}
              className="text-xs text-green font-bold uppercase tracking-wider hover:underline flex items-center gap-1.5 disabled:opacity-50"
            >
              {planLoading && <Loader2 className="w-3 h-3 animate-spin" />}
              {plan ? 'Regenerate' : 'Generate'}
            </button>
          </div>

          {planErr && <p className="mt-2 text-xs text-rust">{planErr}</p>}

          {planVisible && plan && <KickstartPlanView plan={plan.plan_json} />}
          {planVisible && !plan && !planLoading && (
            <p className="mt-2 text-xs text-muted">No plan generated yet. Click <strong>Generate</strong> above.</p>
          )}
        </div>
      )}
    </div>
  )
}

type KickstartPlan = {
  id: string
  plan_json: KickstartPlanBody
  validity_status: string
  generated_at: string
}
type Milestone = {
  framework_id: string
  framework_key: string
  day_offset: string
  title: string
  narrative: string
  manager_prompts: string[]
  grounded: boolean
}
type TailoredPrompt = {
  framework_id: string
  framework_key: string
  trigger: { trait: string; when: string }
  prompt: string
  citation: string
  grounded: boolean
}
type KickstartPlanBody = {
  milestones: Milestone[]
  tailored_prompts: TailoredPrompt[]
  role_title: string
  _dev_stub: boolean
  _grounded: boolean
}

function KickstartPlanView({ plan }: { plan: KickstartPlanBody }) {
  return (
    <div className="mt-3 space-y-4">
      <div className="flex items-center gap-2 flex-wrap">
        <RoleBadge>{plan.role_title || '(role unknown)'}</RoleBadge>
        <StubBadge />
        <Pill tone="interview">Grounded</Pill>
      </div>

      <div className="space-y-3">
        {plan.milestones.map((m) => (
          <div key={m.framework_id} className="border border-line rounded p-3 bg-surface">
            <div className="flex items-start justify-between gap-3 flex-wrap">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="inline-flex items-center justify-center min-w-[44px] h-7 px-2 rounded bg-forest text-white font-display font-semibold text-sm">
                  Day {m.day_offset}
                </span>
                <p className="font-semibold text-ink text-sm">{m.title}</p>
              </div>
              <Pill tone="draft" className="text-[10px]" title={`Framework: ${m.framework_key}`}>
                <Sparkles size={10} strokeWidth={2.5} /> {m.framework_key}
              </Pill>
            </div>
            <p className="mt-2 text-xs text-muted leading-relaxed italic">{m.narrative}</p>
            {m.manager_prompts && m.manager_prompts.length > 0 && (
              <ul className="mt-2 space-y-1">
                {m.manager_prompts.map((p, i) => (
                  <li key={i} className="text-xs text-ink flex gap-2">
                    <ChevronRight size={12} className="mt-0.5 text-faint flex-shrink-0" />
                    <span>{p}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        ))}
      </div>

      {plan.tailored_prompts.length > 0 && (
        <div>
          <p className="eyebrow mb-2">Trait-tailored manager prompts (DEV-STUB)</p>
          <div className="space-y-2">
            {plan.tailored_prompts.map((p) => (
              <div key={p.framework_id} className="border border-line rounded p-2.5 bg-surface">
                <p className="text-xs font-mono text-role mb-1">
                  trigger · {p.trigger.trait} · {p.trigger.when}
                </p>
                <p className="text-sm text-ink">{p.prompt}</p>
                <p className="text-[11px] text-muted italic mt-1.5">{p.citation}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      <p className="eyebrow flex items-center gap-1.5 pt-2 border-t border-dashed border-line">
        <Shield className="w-3 h-3" strokeWidth={2.5} />
        Grounded in frameworks library · never freeform · audited
      </p>
    </div>
  )
}
