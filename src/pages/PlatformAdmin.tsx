import { useCallback, useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Building2, Eye, Globe, Loader2, LogOut, Pause, Plus, Play, Shield, X } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { usePageTitle } from '../lib/usePageTitle.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { TabBand, Tab } from '../components/ui/tabband.js'
import { Pill } from '../components/ui/badges.js'
import { EmptyState } from '../components/ui/EmptyState.js'
import { ErrorState } from '../components/ui/ErrorState.js'
import { useToast } from '../components/ui/Toast.js'

// /platform-admin — minimal platform-admin surface for the founder.
//
// Gated by the system-level `platform_admin` rbac_role (org_id IS NULL).
// is_platform_admin() runs server-side as a SECDEF check; the page also
// calls it on mount to render the not-authorized state immediately.
//
// Three tabs:
//   * Orgs — list all customer orgs + create / suspend / reactivate
//   * Metrics — aggregate counts only (no identifying data)
//   * Investigations — the platform admin's own past actions
//
// What this page deliberately does NOT show:
//   * Any actual customer data. Orgs are listed by name + counts only.
//   * The audit_log content of a specific org. That is in /admin → Audit
//     (cross-org view, gated separately by platform.investigate +
//     logged to platform_admin_investigation_log).

type OrgRow = {
  id: string
  name: string
  type: 'agency' | 'employer'
  status: 'active' | 'suspended' | 'archived'
  country: string
  data_region: string
  created_at: string
  suspended_at: string | null
  suspended_reason: string | null
  user_count: number
  active_placement_count: number
  is_demo: boolean
}

type Metrics = {
  orgs_total: number
  orgs_active: number
  orgs_suspended: number
  orgs_archived: number
  users_total: number
  memberships_active: number
  placements_active: number
  placements_last_7d: number
  requisitions_open: number
  audit_events_last_24h: number
  computed_at: string
}

type InvestigationRow = {
  id: string
  actor_person_id: string
  action: string
  target_org_id: string | null
  payload_json: Record<string, unknown>
  at: string
}

export function PlatformAdminPage() {
  usePageTitle('Platform admin')
  const supabase = browserSupabase()
  const toast = useToast()
  const [auth, setAuth] = useState<{ status: 'loading' } | { status: 'denied' } | { status: 'allowed' }>({ status: 'loading' })
  const [tab, setTab] = useState<'orgs' | 'metrics' | 'requests' | 'settings' | 'investigations'>('orgs')

  // Permission check on mount. Server-side is the source of truth — every
  // RPC below also checks is_platform_admin() — but rendering the surface
  // for a non-admin would still leak the structure of the page.
  useEffect(() => {
    void (async () => {
      const { data: session } = await supabase.auth.getSession()
      if (!session.session) { setAuth({ status: 'denied' }); return }
      const { data, error } = await supabase.rpc('is_platform_admin' as never)
      if (error || !data) setAuth({ status: 'denied' })
      else setAuth({ status: 'allowed' })
    })()
  }, [supabase])

  if (auth.status === 'loading') {
    return (
      <Shell breadcrumb={<span>Platform admin</span>}>
        <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Checking access…</div>
      </Shell>
    )
  }
  if (auth.status === 'denied') {
    return (
      <Shell breadcrumb={<span>Platform admin</span>}>
        <Card><CardBody>
          <ErrorState
            title="Not authorised"
            message="This surface is restricted to platform administrators. If you believe this is wrong, contact your platform owner."
          />
        </CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell breadcrumb={<>Platform · <strong>admin</strong></>}>
      <div className="flex flex-col gap-4">
        <div className="flex items-start justify-between gap-4 flex-wrap pb-3 border-b border-line">
          <div>
            <div className="flex items-center gap-2">
              <Shield size={20} className="text-forest" />
              <h1 className="font-display text-3xl font-bold tracking-tight">Platform administration</h1>
            </div>
            <p className="text-muted text-sm mt-1 max-w-2xl">
              Operator surface for the founder and platform owners. Every action here is
              recorded in <code className="font-mono">platform_admin_investigation_log</code> —
              your own activity is auditable to the next platform admin.
            </p>
          </div>
        </div>

        <TabBand>
          <Tab active={tab === 'orgs'}            onClick={() => setTab('orgs')}>            Organisations </Tab>
          <Tab active={tab === 'metrics'}         onClick={() => setTab('metrics')}>         Platform metrics </Tab>
          <Tab active={tab === 'requests'}        onClick={() => setTab('requests')}>        Signup requests </Tab>
          <Tab active={tab === 'settings'}        onClick={() => setTab('settings')}>        Settings </Tab>
          <Tab active={tab === 'investigations'}  onClick={() => setTab('investigations')}>  My investigations </Tab>
        </TabBand>

        {tab === 'orgs' && <OrgsTab toast={toast} />}
        {tab === 'metrics' && <MetricsTab />}
        {tab === 'requests' && <RequestsTab toast={toast} />}
        {tab === 'settings' && <SettingsTab toast={toast} />}
        {tab === 'investigations' && <InvestigationsTab />}

        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}

// ─── Orgs tab ───────────────────────────────────────────────────────
function OrgsTab({ toast }: { toast: ReturnType<typeof useToast> }) {
  const supabase = browserSupabase()
  const [rows, setRows] = useState<OrgRow[] | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [showCreate, setShowCreate] = useState(false)
  const [acting, setActing] = useState<{ id: string; kind: 'suspend' | 'reactivate' } | null>(null)

  const reload = useCallback(async () => {
    setErr(null)
    const { data, error } = await supabase.rpc('platform_orgs_list' as never)
    if (error) { setErr(error.message); setRows([]); return }
    setRows(((data ?? []) as unknown as OrgRow[]))
  }, [supabase])

  useEffect(() => { void reload() }, [reload])

  if (err) return <Card><CardBody><ErrorState message={err} onRetry={() => void reload()} /></CardBody></Card>
  if (rows === null) return <Card><CardBody><div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading orgs…</div></CardBody></Card>

  return (
    <>
      <Card>
        <CardBody className="flex flex-col gap-3">
          <div className="flex items-center justify-between">
            <CardEyebrow><Building2 size={12} /> All organisations</CardEyebrow>
            <Button onClick={() => setShowCreate(true)}><Plus size={14} /> Create org</Button>
          </div>
          {rows.length === 0 ? (
            <EmptyState icon={Building2} title="No organisations yet" body="Create the first customer org with the button above." />
          ) : (
            <table className="w-full text-sm">
              <thead className="text-[10.5px] uppercase tracking-wider text-muted">
                <tr className="border-b border-line">
                  <th className="text-left py-2">Name</th>
                  <th className="text-left">Type</th>
                  <th className="text-left">Status</th>
                  <th className="text-right">Users</th>
                  <th className="text-right">Placements</th>
                  <th className="text-left">Created</th>
                  <th className="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(o => (
                  <tr key={o.id} className="border-b border-line">
                    <td className="py-2">
                      <div className="font-semibold">{o.name}</div>
                      <div className="text-[10.5px] text-faint font-mono">{o.id.slice(0, 8)} · {o.country} · {o.data_region}</div>
                      {o.is_demo && <Pill tone="internal">demo</Pill>}
                    </td>
                    <td><Pill>{o.type}</Pill></td>
                    <td>
                      <Pill tone={o.status === 'active' ? 'open' : o.status === 'suspended' ? 'reject' : 'draft'}>
                        {o.status}
                      </Pill>
                      {o.status === 'suspended' && o.suspended_reason && (
                        <div className="text-[10.5px] text-faint mt-1 max-w-[200px]" title={o.suspended_reason}>
                          {o.suspended_reason.slice(0, 60)}{o.suspended_reason.length > 60 ? '…' : ''}
                        </div>
                      )}
                    </td>
                    <td className="text-right font-mono">{o.user_count}</td>
                    <td className="text-right font-mono">{o.active_placement_count}</td>
                    <td className="text-xs text-muted">{new Date(o.created_at).toLocaleDateString()}</td>
                    <td className="text-right">
                      {o.status === 'active' && (
                        <Button variant="ghost" onClick={() => setActing({ id: o.id, kind: 'suspend' })} className="text-xs">
                          <Pause size={12} /> Suspend
                        </Button>
                      )}
                      {o.status === 'suspended' && (
                        <Button variant="ghost" onClick={() => setActing({ id: o.id, kind: 'reactivate' })} className="text-xs">
                          <Play size={12} /> Reactivate
                        </Button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardBody>
      </Card>

      {showCreate && (
        <CreateOrgDialog
          onClose={() => setShowCreate(false)}
          onCreated={async () => { setShowCreate(false); toast.success('Organisation created.'); await reload() }}
        />
      )}

      {acting && (
        <SuspendReactivateDialog
          orgId={acting.id}
          kind={acting.kind}
          orgName={rows.find(r => r.id === acting.id)?.name ?? '<unknown>'}
          onClose={() => setActing(null)}
          onDone={async () => { setActing(null); toast.success(acting.kind === 'suspend' ? 'Organisation suspended.' : 'Organisation reactivated.'); await reload() }}
        />
      )}
    </>
  )
}

function CreateOrgDialog({ onClose, onCreated }: { onClose: () => void; onCreated: () => void | Promise<void> }) {
  const supabase = browserSupabase()
  const [name, setName] = useState('')
  const [orgType, setOrgType] = useState<'agency' | 'employer'>('employer')
  const [country, setCountry] = useState('NO')
  const [locale, setLocale] = useState<'nb-NO' | 'sv-SE' | 'da-DK' | 'en'>('nb-NO')
  const [adminEmail, setAdminEmail] = useState('')
  const [adminName, setAdminName] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = useCallback(async () => {
    setError(null)
    if (name.trim().length < 2) { setError('Name >= 2 chars.'); return }
    setSubmitting(true)
    const { error } = await supabase.rpc('platform_org_create' as never, {
      p_name: name.trim(),
      p_type: orgType,
      p_country: country,
      p_locale: locale,
      p_admin_email: adminEmail || null,
      p_admin_name: adminName || null,
      p_is_demo: false,
    } as never)
    setSubmitting(false)
    if (error) { setError(error.message); return }
    await onCreated()
  }, [supabase, name, orgType, country, locale, adminEmail, adminName, onCreated])

  return (
    <DialogShell onClose={onClose} title="Create organisation" eyebrow="Platform admin">
      <label className="flex flex-col gap-1">
        <span className="text-xs text-muted">Name</span>
        <input className="border border-line rounded px-3 py-2 text-sm bg-surface" value={name} onChange={e => setName(e.target.value)} placeholder="e.g. Bjørnstad Engineering" />
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-xs text-muted">Type</span>
        <select className="border border-line rounded px-3 py-2 text-sm bg-surface" value={orgType} onChange={e => setOrgType(e.target.value as 'agency' | 'employer')}>
          <option value="employer">Employer</option>
          <option value="agency">Recruitment agency</option>
        </select>
      </label>
      <div className="grid grid-cols-2 gap-2">
        <label className="flex flex-col gap-1">
          <span className="text-xs text-muted">Country (ISO-2)</span>
          <input className="border border-line rounded px-3 py-2 text-sm bg-surface uppercase" value={country} onChange={e => setCountry(e.target.value.slice(0, 2).toUpperCase())} maxLength={2} />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs text-muted">Default locale</span>
          <select className="border border-line rounded px-3 py-2 text-sm bg-surface" value={locale} onChange={e => setLocale(e.target.value as typeof locale)}>
            <option value="nb-NO">Norwegian (Bokmål)</option>
            <option value="sv-SE">Swedish</option>
            <option value="da-DK">Danish</option>
            <option value="en">English</option>
          </select>
        </label>
      </div>
      <label className="flex flex-col gap-1">
        <span className="text-xs text-muted">Admin contact email (optional)</span>
        <input className="border border-line rounded px-3 py-2 text-sm bg-surface" value={adminEmail} onChange={e => setAdminEmail(e.target.value)} placeholder="admin@example.com" />
        <span className="text-[11px] text-faint">Captured in the investigation log. The standard org-admin invite flow happens separately.</span>
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-xs text-muted">Admin contact name (optional)</span>
        <input className="border border-line rounded px-3 py-2 text-sm bg-surface" value={adminName} onChange={e => setAdminName(e.target.value)} />
      </label>
      {error && <div className="rounded border border-rust/40 bg-reject-bg p-2 text-xs text-rust">{error}</div>}
      <div className="flex items-center justify-end gap-2 pt-2 border-t border-line">
        <Button variant="ghost" onClick={onClose} disabled={submitting}>Cancel</Button>
        <Button onClick={submit} disabled={submitting || name.trim().length < 2}>
          {submitting ? <Loader2 size={14} className="animate-spin" /> : <Plus size={14} />} Create
        </Button>
      </div>
    </DialogShell>
  )
}

function SuspendReactivateDialog({
  orgId, kind, orgName, onClose, onDone,
}: {
  orgId: string
  kind: 'suspend' | 'reactivate'
  orgName: string
  onClose: () => void
  onDone: () => void | Promise<void>
}) {
  const supabase = browserSupabase()
  const [reason, setReason] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = useCallback(async () => {
    setError(null)
    if (reason.trim().length < 20) { setError('Reason >= 20 chars (audit-grade).'); return }
    setSubmitting(true)
    const fn = kind === 'suspend' ? 'platform_org_suspend' : 'platform_org_reactivate'
    const { error } = await supabase.rpc(fn as never, { p_org_id: orgId, p_reason: reason.trim() } as never)
    setSubmitting(false)
    if (error) { setError(error.message); return }
    await onDone()
  }, [supabase, kind, orgId, reason, onDone])

  return (
    <DialogShell
      onClose={onClose}
      title={kind === 'suspend' ? `Suspend ${orgName}` : `Reactivate ${orgName}`}
      eyebrow={kind === 'suspend' ? 'Pause organisation' : 'Restore access'}
    >
      <div className="rounded border border-line bg-canvas p-3 text-xs text-muted">
        {kind === 'suspend' ? (
          <>
            <AlertTriangle size={14} className="inline text-amber mr-1" />
            Suspending blocks login for everyone in <strong>{orgName}</strong>. Existing data
            is preserved. Cross-org operations involving this org will fail with a clear error.
          </>
        ) : (
          <>
            <Play size={14} className="inline text-green mr-1" />
            Reactivating restores login. The org's audit log will show both the original
            suspension and this reactivation.
          </>
        )}
      </div>
      <label className="flex flex-col gap-1">
        <span className="text-xs text-muted">Rationale (≥ 20 chars)</span>
        <textarea
          className="border border-line rounded px-3 py-2 text-sm font-body"
          rows={3}
          value={reason}
          onChange={e => setReason(e.target.value)}
          placeholder={kind === 'suspend'
            ? 'e.g. Customer requested temporary pause during contract renegotiation.'
            : 'e.g. Contract renegotiation concluded; resuming service.'}
        />
      </label>
      {error && <div className="rounded border border-rust/40 bg-reject-bg p-2 text-xs text-rust">{error}</div>}
      <div className="flex items-center justify-end gap-2 pt-2 border-t border-line">
        <Button variant="ghost" onClick={onClose} disabled={submitting}>Cancel</Button>
        <Button onClick={submit} disabled={submitting || reason.trim().length < 20}>
          {submitting ? <Loader2 size={14} className="animate-spin" /> : kind === 'suspend' ? <Pause size={14} /> : <Play size={14} />}
          {kind === 'suspend' ? 'Suspend' : 'Reactivate'}
        </Button>
      </div>
    </DialogShell>
  )
}

function DialogShell({ onClose, title, eyebrow, children }: {
  onClose: () => void
  title: string
  eyebrow: string
  children: React.ReactNode
}) {
  return (
    <div className="fixed inset-0 z-50 bg-ink/40 backdrop-blur-sm flex items-center justify-center p-4" onClick={onClose}>
      <Card className="w-full max-w-lg" onClick={(e) => e.stopPropagation()}>
        <CardBody className="flex flex-col gap-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-[10.5px] uppercase tracking-wider font-bold text-muted">{eyebrow}</p>
              <h2 className="font-display text-xl font-semibold mt-0.5">{title}</h2>
            </div>
            <Button variant="ghost" onClick={onClose}><X size={14} /></Button>
          </div>
          {children}
        </CardBody>
      </Card>
    </div>
  )
}

// ─── Metrics tab ────────────────────────────────────────────────────
function MetricsTab() {
  const supabase = browserSupabase()
  const [m, setM] = useState<Metrics | null>(null)
  const [err, setErr] = useState<string | null>(null)

  const reload = useCallback(async () => {
    setErr(null)
    const { data, error } = await supabase.rpc('platform_metrics' as never)
    if (error) { setErr(error.message); return }
    setM(data as unknown as Metrics)
  }, [supabase])

  useEffect(() => { void reload() }, [reload])

  if (err) return <Card><CardBody><ErrorState message={err} onRetry={() => void reload()} /></CardBody></Card>
  if (m === null) return <Card><CardBody><div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading metrics…</div></CardBody></Card>

  return (
    <Card>
      <CardBody className="flex flex-col gap-4">
        <div>
          <CardEyebrow><Globe size={12} /> Aggregate metrics</CardEyebrow>
          <CardTitle>Platform-wide counts</CardTitle>
          <p className="text-xs text-muted mt-1">
            Aggregate only — no individual users, orgs, or identifying data. Computed{' '}
            {new Date(m.computed_at).toLocaleString()}.
          </p>
        </div>
        <dl className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <MetricCell label="Organisations" value={m.orgs_total} sub={`${m.orgs_active} active · ${m.orgs_suspended} suspended`} />
          <MetricCell label="Users" value={m.users_total} sub={`${m.memberships_active} active memberships`} />
          <MetricCell label="Active placements" value={m.placements_active} sub={`${m.placements_last_7d} new in last 7d`} />
          <MetricCell label="Open requisitions" value={m.requisitions_open} />
          <MetricCell label="Archived orgs" value={m.orgs_archived} />
          <MetricCell label="Audit events (24h)" value={m.audit_events_last_24h} sub="Platform-wide" />
        </dl>
        <div className="rounded border border-line bg-canvas p-3 text-xs text-muted">
          Metrics intentionally exclude error rate, response time, daily active users
          and similar operational telemetry — those live in the uptime monitor and
          Sentry surfaces (see <code className="font-mono">docs/MONITORING.md</code>).
        </div>
      </CardBody>
    </Card>
  )
}

function MetricCell({ label, value, sub }: { label: string; value: number; sub?: string }) {
  return (
    <div className="border border-line rounded p-3">
      <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted">{label}</div>
      <div className="font-display text-3xl font-bold mt-1">{value.toLocaleString()}</div>
      {sub && <div className="text-xs text-faint mt-1">{sub}</div>}
    </div>
  )
}

// ─── Investigations tab ─────────────────────────────────────────────
function InvestigationsTab() {
  const supabase = browserSupabase()
  const [rows, setRows] = useState<InvestigationRow[] | null>(null)
  const [err, setErr] = useState<string | null>(null)

  const reload = useCallback(async () => {
    setErr(null)
    const { data, error } = await supabase.rpc('platform_investigation_log_recent' as never, { p_limit: 100 } as never)
    if (error) { setErr(error.message); setRows([]); return }
    setRows(((data ?? []) as unknown as InvestigationRow[]))
  }, [supabase])

  useEffect(() => { void reload() }, [reload])

  const groups = useMemo(() => {
    if (!rows) return []
    const m = new Map<string, InvestigationRow[]>()
    for (const r of rows) {
      const k = new Date(r.at).toLocaleDateString()
      if (!m.has(k)) m.set(k, [])
      m.get(k)!.push(r)
    }
    return Array.from(m.entries())
  }, [rows])

  if (err) return <Card><CardBody><ErrorState message={err} onRetry={() => void reload()} /></CardBody></Card>
  if (rows === null) return <Card><CardBody><div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div></CardBody></Card>

  return (
    <Card>
      <CardBody className="flex flex-col gap-4">
        <div>
          <CardEyebrow><Eye size={12} /> My investigations</CardEyebrow>
          <CardTitle>Recent platform-admin actions</CardTitle>
          <p className="text-xs text-muted mt-1">
            Every platform-admin action you take is recorded here so the next platform
            admin can verify your past behaviour. This log is immutable.
          </p>
        </div>
        {rows.length === 0 ? (
          <EmptyState icon={Eye} title="No investigation log yet" body="Actions you take here will appear in this view." />
        ) : (
          <div className="flex flex-col gap-4">
            {groups.map(([day, items]) => (
              <div key={day}>
                <p className="text-[10.5px] uppercase tracking-wider font-bold text-muted mb-2">{day}</p>
                <ul className="flex flex-col gap-1.5">
                  {items.map(r => (
                    <li key={r.id} className="text-sm border border-line rounded px-3 py-2 flex items-center gap-3">
                      <Pill tone={r.action.startsWith('org.suspend') ? 'reject' : r.action.startsWith('org.create') ? 'open' : 'draft'}>
                        {r.action}
                      </Pill>
                      <span className="text-xs text-faint font-mono flex-1 truncate">
                        target {r.target_org_id?.slice(0, 8) ?? '—'} · {JSON.stringify(r.payload_json).slice(0, 80)}
                      </span>
                      <span className="text-[10.5px] text-faint">{new Date(r.at).toLocaleTimeString()}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        )}
      </CardBody>
    </Card>
  )
}

// ─── Signup requests tab (Phase 4 approval) ─────────────────────────
// Lists contact_requests of signup kinds; approving provisions the org
// via platform_org_create (A9) and marks the request approved.
function RequestsTab({ toast }: { toast: ReturnType<typeof useToast> }) {
  const supabase = browserSupabase()
  type Req = {
    id: string; kind: string; name: string; email: string; organization: string | null
    interest: string | null; status: string; created_at: string
    payload_json: { org_type?: string; country?: string; locale?: string; size?: string } | null
  }
  const [rows, setRows] = useState<Req[] | null>(null)
  const [busy, setBusy] = useState<string | null>(null)

  const reload = useCallback(async () => {
    const { data, error } = await supabase.rpc('contact_requests_list' as never, { p_status: null } as never)
    if (error) { setRows([]); return }
    setRows(((data ?? []) as unknown as Req[]).filter(r => r.kind.endsWith('signup')))
  }, [supabase])
  useEffect(() => { void reload() }, [reload])

  const approve = useCallback(async (r: Req) => {
    setBusy(r.id)
    // Provision the org, then mark the request approved.
    const { error: ce } = await supabase.rpc('platform_org_create' as never, {
      p_name: r.organization ?? r.name,
      p_type: r.payload_json?.org_type === 'agency' ? 'agency' : 'employer',
      p_country: r.payload_json?.country ?? 'NO',
      p_locale: r.payload_json?.locale ?? 'nb-NO',
      p_admin_email: r.email,
      p_admin_name: r.name,
      p_is_demo: false,
    } as never)
    if (ce) { setBusy(null); toast.error(`Provisioning failed: ${ce.message}`); return }
    await supabase.rpc('contact_request_set_status' as never, { p_id: r.id, p_status: 'approved' } as never)
    setBusy(null)
    toast.success(`Provisioned org for ${r.organization ?? r.name}.`)
    await reload()
  }, [supabase, toast, reload])

  const decline = useCallback(async (r: Req) => {
    setBusy(r.id)
    await supabase.rpc('contact_request_set_status' as never, { p_id: r.id, p_status: 'declined' } as never)
    setBusy(null)
    await reload()
  }, [supabase, reload])

  if (rows === null) return <Card><CardBody><div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div></CardBody></Card>

  return (
    <Card><CardBody className="flex flex-col gap-3">
      <CardEyebrow>Signup requests</CardEyebrow>
      <CardTitle>Design-partner &amp; commercial applications</CardTitle>
      {rows.length === 0 ? (
        <EmptyState icon={Building2} title="No signup requests" body="Applications from /signup land here for review." />
      ) : (
        <ul className="flex flex-col gap-2">
          {rows.map(r => (
            <li key={r.id} className="border border-line rounded p-3 text-sm flex items-center gap-3 flex-wrap">
              <div className="flex-1 min-w-[200px]">
                <div className="font-semibold">{r.organization ?? '(no org name)'} <span className="text-faint font-normal">· {r.payload_json?.org_type ?? r.interest}</span></div>
                <div className="text-xs text-muted">{r.name} · {r.email}</div>
                <div className="text-[11px] text-faint mt-0.5">{r.kind.replace('_', ' ')} · {new Date(r.created_at).toLocaleDateString()}</div>
              </div>
              <Pill tone={r.status === 'approved' ? 'open' : r.status === 'declined' ? 'reject' : 'draft'}>{r.status}</Pill>
              {r.status === 'new' && (
                <>
                  <Button onClick={() => approve(r)} disabled={busy === r.id} className="text-xs">
                    {busy === r.id ? <Loader2 size={12} className="animate-spin" /> : <Play size={12} />} Approve &amp; provision
                  </Button>
                  <Button variant="ghost" onClick={() => decline(r)} disabled={busy === r.id} className="text-xs text-rust">Decline</Button>
                </>
              )}
            </li>
          ))}
        </ul>
      )}
    </CardBody></Card>
  )
}

// ─── Settings tab (Phase 1.5) ───────────────────────────────────────
// platform_settings management: legal entity, DPO, support email, and
// the legal-review status (which controls the TEMPLATE banner on legal
// pages). Flipping to 'current' requires a reviewer name.
function SettingsTab({ toast }: { toast: ReturnType<typeof useToast> }) {
  const supabase = browserSupabase()
  type Settings = {
    platform_legal_entity_name: string | null
    platform_legal_entity_address: string | null
    dpo_contact_name: string | null
    dpo_contact_email: string | null
    support_email: string | null
    legal_review_status: 'pending' | 'current'
    legal_reviewer_name: string | null
  }
  const [s, setS] = useState<Settings | null>(null)
  const [busy, setBusy] = useState(false)

  const reload = useCallback(async () => {
    const { data, error } = await supabase.rpc('platform_settings_get' as never)
    if (error) { return }
    setS(data as unknown as Settings)
  }, [supabase])
  useEffect(() => { void reload() }, [reload])

  const save = useCallback(async () => {
    if (!s) return
    setBusy(true)
    const { error } = await supabase.rpc('platform_settings_update' as never, {
      p_legal_entity_name: s.platform_legal_entity_name,
      p_legal_entity_address: s.platform_legal_entity_address,
      p_dpo_contact_name: s.dpo_contact_name,
      p_dpo_contact_email: s.dpo_contact_email,
      p_support_email: s.support_email,
      p_legal_review_status: s.legal_review_status,
      p_legal_reviewer_name: s.legal_reviewer_name,
    } as never)
    setBusy(false)
    if (error) { toast.error(error.message); return }
    toast.success('Platform settings saved.')
    await reload()
  }, [supabase, toast, s, reload])

  if (!s) return <Card><CardBody><div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div></CardBody></Card>

  const field = (label: string, key: keyof Settings, placeholder?: string) => (
    <label className="flex flex-col gap-1">
      <span className="text-xs text-muted">{label}</span>
      <input
        className="border border-line rounded px-3 py-2 text-sm bg-surface"
        value={(s[key] as string) ?? ''}
        placeholder={placeholder}
        onChange={e => setS({ ...s, [key]: e.target.value })}
      />
    </label>
  )

  return (
    <Card><CardBody className="flex flex-col gap-4">
      <div>
        <CardEyebrow>Platform settings</CardEyebrow>
        <CardTitle>Legal contact &amp; review status</CardTitle>
        <p className="text-xs text-muted mt-1">
          These values appear on the public legal pages. The review status controls the
          "TEMPLATE PENDING LEGAL REVIEW" banner.
        </p>
      </div>
      {field('Legal entity name', 'platform_legal_entity_name')}
      {field('Legal entity address', 'platform_legal_entity_address')}
      {field('DPO contact name', 'dpo_contact_name')}
      {field('DPO contact email', 'dpo_contact_email', 'dpo@example.com')}
      {field('Support email', 'support_email', 'support@example.com')}

      <div className="border-t border-line pt-3">
        <label className="flex flex-col gap-1">
          <span className="text-xs text-muted">Legal review status</span>
          <select
            className="border border-line rounded px-3 py-2 text-sm bg-surface"
            value={s.legal_review_status}
            onChange={e => setS({ ...s, legal_review_status: e.target.value as 'pending' | 'current' })}
          >
            <option value="pending">Pending — show TEMPLATE banner</option>
            <option value="current">Current — counsel-approved (hides banner)</option>
          </select>
        </label>
        {s.legal_review_status === 'current' && (
          <label className="flex flex-col gap-1 mt-2">
            <span className="text-xs text-muted">Reviewer name (required to mark current)</span>
            <input
              className="border border-line rounded px-3 py-2 text-sm bg-surface"
              value={s.legal_reviewer_name ?? ''}
              onChange={e => setS({ ...s, legal_reviewer_name: e.target.value })}
            />
          </label>
        )}
        <p className="text-[11px] text-faint mt-2">
          Marking legal pages "current" removes the template warning. Only do this after
          counsel has actually reviewed — the reviewer name is recorded in the investigation log.
        </p>
      </div>

      <div className="flex justify-end">
        <Button onClick={save} disabled={busy}>
          {busy ? <Loader2 size={14} className="animate-spin" /> : null} Save settings
        </Button>
      </div>
    </CardBody></Card>
  )
}
