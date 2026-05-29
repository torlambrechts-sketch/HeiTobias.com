import { useCallback, useEffect, useState } from 'react'
import { AlertTriangle, FileCheck2, FileText, Gauge, Loader2, LogOut, ShieldAlert, Sparkles } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Pill, StubBadge } from '../components/ui/badges.js'
import { TabBand, Tab } from '../components/ui/tabband.js'
import { Shell } from '../components/Shell.js'
import { HitlNotice } from '../components/HitlNotice.js'

const DEMO_USERS = [
  { email: 'linnea.strand@fjordtech.test', label: 'Linnea Strand — FjordTech people_ops_admin' },
] as const

const FJORDTECH_ID = 'a1000000-0000-0000-0000-000000000002'

type ModelRow = { id: string; key: string; family: string; version: string; validity_status: string; _dev_stub: boolean; created_at: string; card_signed_off_at: string | null }
type CardRow  = { id: string; model_id: string; intended_use: string | null; validity_status: string; _dev_stub: boolean; signed_off_by: string | null }
type CurveRow = { id: string; key: string; default_weight_validity: number; regularization_lambda: number; computed_at: string; _dev_stub: boolean }
type PointRow = { weight_validity: number; predicted_validity: number | null; predicted_air: number | null; is_default_point: boolean }
type MetricRow = { id: string; characteristic: string; reference_group: string; protected_group: string; adverse_impact_ratio: number | null; ci_lower: number | null; ci_upper: number | null; four_fifths_inspection_triggered: boolean; interpretation_by_expert: string | null }
type AlertRow = { id: string; severity: string; status: string; message: string; opened_at: string; resolved_at: string | null }
type ArtifactRow = { id: string; kind: string; key: string; sign_off_status: string; generated_at: string; signed_off_at: string | null }

export function ModelingAdminPage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [authBusy, setAuthBusy] = useState(false)
  const [tab, setTab] = useState<'models' | 'pareto' | 'fairness' | 'monitoring' | 'compliance'>('models')
  const [topErr, setTopErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const [models, setModels] = useState<ModelRow[]>([])
  const [cards, setCards] = useState<CardRow[]>([])
  const [curves, setCurves] = useState<CurveRow[]>([])
  const [points, setPoints] = useState<Record<string, PointRow[]>>({})
  const [metrics, setMetrics] = useState<MetricRow[]>([])
  const [alerts, setAlerts] = useState<AlertRow[]>([])
  const [artifacts, setArtifacts] = useState<ArtifactRow[]>([])

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  const load = useCallback(async () => {
    if (!signedIn) return
    setLoading(true)
    setTopErr(null)
    try {
      const m = await supabase.from('model_registry' as never).select('id,key,family,version,validity_status,_dev_stub,created_at').eq('org_id', FJORDTECH_ID).order('created_at', { ascending: false }).limit(20)
      const c = await supabase.from('model_cards' as never).select('id,model_id,intended_use,validity_status,_dev_stub,signed_off_by')
      const cu = await supabase.from('pareto_curves' as never).select('id,key,default_weight_validity,regularization_lambda,computed_at,_dev_stub').eq('org_id', FJORDTECH_ID).order('computed_at', { ascending: false }).limit(5)
      const fm = await supabase.from('fairness_metrics' as never).select('id,characteristic,reference_group,protected_group,adverse_impact_ratio,ci_lower,ci_upper,four_fifths_inspection_triggered,interpretation_by_expert').limit(50)
      const al = await supabase.from('monitoring_alerts' as never).select('id,severity,status,message,opened_at,resolved_at').eq('org_id', FJORDTECH_ID).order('opened_at', { ascending: false }).limit(20)
      const ar = await supabase.from('compliance_artifacts' as never).select('id,kind,key,sign_off_status,generated_at,signed_off_at').eq('org_id', FJORDTECH_ID).order('generated_at', { ascending: false }).limit(20)
      setModels(((m.data as unknown) as ModelRow[]) ?? [])
      setCards(((c.data as unknown) as CardRow[]) ?? [])
      setCurves(((cu.data as unknown) as CurveRow[]) ?? [])
      setMetrics(((fm.data as unknown) as MetricRow[]) ?? [])
      setAlerts(((al.data as unknown) as AlertRow[]) ?? [])
      setArtifacts(((ar.data as unknown) as ArtifactRow[]) ?? [])
      const curveIds = ((cu.data as unknown) as CurveRow[] | null)?.map((c) => c.id) ?? []
      if (curveIds.length > 0) {
        const pts = await supabase.from('pareto_curve_points' as never).select('curve_id,weight_validity,predicted_validity,predicted_air,is_default_point').in('curve_id', curveIds).order('ordered_index', { ascending: true })
        const grouped: Record<string, PointRow[]> = {}
        ;((pts.data as unknown) as Array<PointRow & { curve_id: string }> | null)?.forEach((p) => {
          if (!grouped[p.curve_id]) grouped[p.curve_id] = []
          grouped[p.curve_id]!.push(p)
        })
        setPoints(grouped)
      }
    } catch (e) {
      setTopErr(e instanceof Error ? e.message : 'Failed to load')
    } finally {
      setLoading(false)
    }
  }, [signedIn, supabase])

  useEffect(() => { void load() }, [load])

  const signIn = useCallback(async () => {
    setAuthBusy(true); setTopErr(null)
    const { error } = await supabase.auth.signInWithPassword({ email: DEMO_USERS[0].email, password: 'demo' })
    setAuthBusy(false)
    if (error) setTopErr(`Sign-in failed: ${error.message}`)
  }, [supabase])

  const signOut = useCallback(async () => { await supabase.auth.signOut() }, [supabase])

  return (
    <Shell breadcrumb={<span>Modeling admin · <strong>Phase 4 (DEV)</strong></span>} signedInLabel={signedIn ?? undefined}>
      <div className="flex flex-col gap-6">
        <header className="flex items-end justify-between gap-4 flex-wrap">
          <div>
            <h1 className="font-display text-3xl font-bold tracking-tight text-ink">Modeling, fairness & compliance</h1>
            <p className="text-faint mt-1">Phase 4 read-only inspector. <strong>Synthetic, dev-stub only</strong> — no validated science until the I/O psychologist signs off.</p>
          </div>
          <div className="flex items-center gap-2">
            {signedIn ? (
              <>
                <Pill>{signedIn}</Pill>
                <Button variant="ghost" onClick={signOut}><LogOut size={14} /> Sign out</Button>
              </>
            ) : (
              <Button onClick={signIn} disabled={authBusy}>{authBusy ? <Loader2 size={14} className="animate-spin" /> : null} Sign in as Linnea</Button>
            )}
          </div>
        </header>

        <HitlNotice />
        <div className="border border-line bg-canvas px-5 py-3 rounded-lg text-sm text-ink">
          <strong>Phase 4 is infrastructure, not validated science.</strong> Every row in this view is <code>_dev_stub=true</code>. Validity coefficients, fairness thresholds, invariance verdicts, and compliance attestations are expert seams (<code>modeling.signoff</code>) — not granted to any seeded role.
        </div>

        {topErr && <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-900">{topErr}</div>}

        <TabBand>
          <Tab active={tab === 'models'} onClick={() => setTab('models')}>Models</Tab>
          <Tab active={tab === 'pareto'} onClick={() => setTab('pareto')}>Pareto curve</Tab>
          <Tab active={tab === 'fairness'} onClick={() => setTab('fairness')}>Fairness</Tab>
          <Tab active={tab === 'monitoring'} onClick={() => setTab('monitoring')}>Monitoring</Tab>
          <Tab active={tab === 'compliance'} onClick={() => setTab('compliance')}>Compliance</Tab>
        </TabBand>

        {loading && <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>}

        {tab === 'models' && (
          <div className="grid gap-4 lg:grid-cols-2">
            {models.length === 0 && <Card><CardBody><p className="text-faint">No models registered yet.</p></CardBody></Card>}
            {models.map((m) => {
              const card = cards.find((c) => c.model_id === m.id)
              return (
                <Card key={m.id}>
                  <CardEyebrow><Sparkles size={12} /> Model</CardEyebrow>
                  <CardTitle>{m.key} <span className="text-faint font-normal">· {m.version}</span></CardTitle>
                  <CardBody>
                    <div className="flex items-center gap-2 mb-3">
                      <Pill>{m.family}</Pill>
                      {m._dev_stub && <StubBadge />}
                      <Pill>{m.validity_status}</Pill>
                    </div>
                    <div className="text-sm text-faint">
                      <div><strong>Intended use:</strong> {card?.intended_use ?? <em>not set</em>}</div>
                      <div><strong>Card status:</strong> {card?.validity_status ?? 'no card'}</div>
                      <div><strong>Sign-off:</strong> {card?.signed_off_by ?? 'pending — expert seam (modeling.signoff)'}</div>
                    </div>
                  </CardBody>
                </Card>
              )
            })}
          </div>
        )}

        {tab === 'pareto' && (
          <div className="flex flex-col gap-4">
            {curves.length === 0 && <Card><CardBody><p className="text-faint">No Pareto curves computed yet.</p></CardBody></Card>}
            {curves.map((c) => (
              <Card key={c.id}>
                <CardEyebrow><Gauge size={12} /> Pareto curve</CardEyebrow>
                <CardTitle>{c.key}</CardTitle>
                <CardBody>
                  <div className="flex items-center gap-2 mb-3">
                    <Pill>default w<sub>validity</sub> = {c.default_weight_validity.toFixed(2)}</Pill>
                    <Pill>λ = {c.regularization_lambda.toFixed(2)}</Pill>
                    <StubBadge />
                  </div>
                  <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                      <thead className="text-faint">
                        <tr><th className="text-left py-1">w<sub>validity</sub></th><th className="text-left py-1">predicted validity</th><th className="text-left py-1">predicted AIR</th><th className="text-left py-1"></th></tr>
                      </thead>
                      <tbody>
                        {(points[c.id] ?? []).map((p, i) => (
                          <tr key={i} className={p.is_default_point ? 'bg-canvas font-semibold' : ''}>
                            <td className="py-1">{p.weight_validity.toFixed(2)}</td>
                            <td className="py-1">{p.predicted_validity?.toFixed(3) ?? '—'}</td>
                            <td className="py-1">{p.predicted_air?.toFixed(3) ?? '—'}</td>
                            <td className="py-1 text-faint">{p.is_default_point ? '← default' : ''}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  <p className="text-faint text-xs mt-3">DEV STUB synthetic linear trade-off. Real estimators (De Corte 2007; Song 2017/2023) land when the I/O psychologist plugs in.</p>
                </CardBody>
              </Card>
            ))}
          </div>
        )}

        {tab === 'fairness' && (
          <Card>
            <CardEyebrow><ShieldAlert size={12} /> Fairness metrics</CardEyebrow>
            <CardTitle>Per characteristic × group</CardTitle>
            <CardBody>
              {metrics.length === 0 && <p className="text-faint">No fairness metrics recorded yet.</p>}
              {metrics.length > 0 && (
                <table className="w-full text-xs">
                  <thead className="text-faint">
                    <tr><th className="text-left py-1">characteristic</th><th>ref</th><th>protected</th><th>AIR (CI)</th><th>trigger</th><th>expert</th></tr>
                  </thead>
                  <tbody>
                    {metrics.map((m) => (
                      <tr key={m.id} className="border-t border-line">
                        <td className="py-1">{m.characteristic}</td>
                        <td>{m.reference_group}</td>
                        <td>{m.protected_group}</td>
                        <td>
                          {m.adverse_impact_ratio?.toFixed(2) ?? '—'} ({m.ci_lower?.toFixed(2) ?? '—'} – {m.ci_upper?.toFixed(2) ?? '—'})
                        </td>
                        <td>{m.four_fifths_inspection_triggered ? <span className="text-red-700">trigger</span> : '—'}</td>
                        <td>{m.interpretation_by_expert ? <Pill>interpreted</Pill> : <span className="text-faint italic">pending</span>}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
              <p className="text-faint text-xs mt-3">Four-fifths is an <strong>inspection trigger</strong>, not a verdict. Interpretation is the expert's seam.</p>
            </CardBody>
          </Card>
        )}

        {tab === 'monitoring' && (
          <Card>
            <CardEyebrow><AlertTriangle size={12} /> Monitoring alerts</CardEyebrow>
            <CardTitle>Drift / fairness-over-time / retrain triggers</CardTitle>
            <CardBody>
              {alerts.length === 0 && <p className="text-faint">No alerts.</p>}
              {alerts.length > 0 && (
                <table className="w-full text-xs">
                  <thead className="text-faint">
                    <tr><th className="text-left py-1">opened</th><th>severity</th><th>message</th><th>status</th></tr>
                  </thead>
                  <tbody>
                    {alerts.map((a) => (
                      <tr key={a.id} className="border-t border-line">
                        <td className="py-1">{new Date(a.opened_at).toLocaleString()}</td>
                        <td>{a.severity}</td>
                        <td>{a.message}</td>
                        <td>{a.status}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
              <p className="text-faint text-xs mt-3">No alert auto-remediates a people decision. Humans acknowledge + resolve.</p>
            </CardBody>
          </Card>
        )}

        {tab === 'compliance' && (
          <div className="grid gap-4 lg:grid-cols-2">
            {artifacts.length === 0 && <Card><CardBody><p className="text-faint">No compliance artifacts assembled yet.</p></CardBody></Card>}
            {artifacts.map((a) => (
              <Card key={a.id}>
                <CardEyebrow>{a.kind === 'annex_iv_technical_doc' ? <FileText size={12} /> : <FileCheck2 size={12} />} {a.kind}</CardEyebrow>
                <CardTitle>{a.key}</CardTitle>
                <CardBody>
                  <div className="flex items-center gap-2 mb-3">
                    <Pill>{a.sign_off_status}</Pill>
                    <StubBadge />
                  </div>
                  <div className="text-sm text-faint">
                    <div><strong>Generated:</strong> {new Date(a.generated_at).toLocaleString()}</div>
                    <div><strong>Signed off:</strong> {a.signed_off_at ? new Date(a.signed_off_at).toLocaleString() : <em>pending — legal/AI-Act seam</em>}</div>
                  </div>
                </CardBody>
              </Card>
            ))}
          </div>
        )}
      </div>
    </Shell>
  )
}
