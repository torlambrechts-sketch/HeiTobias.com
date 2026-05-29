import { useCallback, useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Bell, Building2, ChevronDown, ChevronRight, Copy, FileDown, FileText, Filter, Link as LinkIcon, Loader2, LogOut, Plug, Settings as SettingsIcon, Shield, UserPlus, Users } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'
import { TabBand, Tab } from '../components/ui/tabband.js'
import { Shell } from '../components/Shell.js'
import { HitlNotice } from '../components/HitlNotice.js'
import { LOCALES, useLocale, type Locale } from '../lib/i18n.js'

// WCAG 2.x relative-luminance contrast — soft warning, never blocking.
function relLuminance(hex: string): number {
  const m = hex.replace('#','').match(/^([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i)
  if (!m) return 0
  const toLin = (s: string) => {
    const c = parseInt(s, 16) / 255
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
  }
  const [r, g, b] = [toLin(m[1]!), toLin(m[2]!), toLin(m[3]!)]
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
function contrastRatio(a: string, b: string): number {
  const la = relLuminance(a), lb = relLuminance(b)
  const [hi, lo] = la > lb ? [la, lb] : [lb, la]
  return (hi + 0.05) / (lo + 0.05)
}

function ContrastPreview({ hex }: { hex: string }) {
  const cCanvas  = contrastRatio(hex, '#f3f1e8')
  const cSurface = contrastRatio(hex, '#ffffff')
  const okCanvas = cCanvas >= 4.5
  const okSurface = cSurface >= 4.5
  return (
    <div data-test="contrast-preview" className="mt-3 border border-line rounded p-3 bg-canvas-2 text-xs flex items-center gap-4 flex-wrap">
      <span className="font-semibold uppercase tracking-wider text-muted">WCAG AA contrast</span>
      <span className="flex items-center gap-1.5">
        <span className="inline-block w-4 h-4 rounded" style={{ backgroundColor: hex, border: '1px solid var(--line-2)' }} />
        vs canvas <code className={'font-mono ' + (okCanvas ? 'text-green' : 'text-amber')}>{cCanvas.toFixed(2)}:1</code> {okCanvas ? '✓' : '⚠ below 4.5'}
      </span>
      <span className="flex items-center gap-1.5">
        vs surface <code className={'font-mono ' + (okSurface ? 'text-green' : 'text-amber')}>{cSurface.toFixed(2)}:1</code> {okSurface ? '✓' : '⚠ below 4.5'}
      </span>
      <span className="text-faint">Soft warning only — choice is yours.</span>
    </div>
  )
}

function NotificationsTab({ orgId }: { orgId: string | null }) {
  const supabase = browserSupabase()
  type Row = { id: string; recipient_name: string | null; channel: string; subject: string; status: string; attempts: number; last_error: string | null; created_at: string; delivered_at: string | null }
  const [rows, setRows] = useState<Row[]>([])
  const [err, setErr] = useState<string | null>(null)
  useEffect(() => {
    if (!orgId) return
    void supabase.rpc('notifications_list_for_org' as never, { p_org_id: orgId, p_limit: 100, p_offset: 0 } as never)
      .then(({ data, error }) => { if (error) setErr(error.message); else setRows(((data ?? []) as unknown as Row[])) })
  }, [supabase, orgId])
  return (
    <Card data-test="notifications-tab">
      <CardEyebrow><Bell size={12} /> Notification outbox</CardEyebrow>
      <CardTitle>Pending + delivered</CardTitle>
      <CardBody>
        <div className="rounded border border-amber/40 bg-internal-bg/40 px-3 py-2 text-xs text-internal-fg mb-3 flex items-start gap-2">
          <AlertTriangle size={13} className="mt-0.5 flex-shrink-0" />
          <span><strong>Operator wiring pending.</strong> The outbox table works; real SMTP / Slack / Teams / calendar dispatch
          requires per-org credentials + a transport worker — not engineering scope. <code className="font-mono">in_app</code>
          channel is the only one rendered to recipients today; others sit at <code className="font-mono">status='pending'</code> until an operator worker picks them up.</span>
        </div>
        {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust mb-3">{err}</div>}
        {rows.length === 0 && <p className="text-faint text-sm">No notifications yet.</p>}
        {rows.length > 0 && (
          <table className="w-full text-xs">
            <thead className="text-faint uppercase tracking-wider"><tr><th className="text-left py-1">At</th><th className="text-left">Recipient</th><th className="text-left">Channel</th><th className="text-left">Subject</th><th className="text-left">Status</th></tr></thead>
            <tbody>{rows.map(r => (
              <tr key={r.id} className="border-t border-line">
                <td className="py-1">{new Date(r.created_at).toLocaleString()}</td>
                <td className="py-1">{r.recipient_name}</td>
                <td className="py-1 font-mono">{r.channel}</td>
                <td className="py-1">{r.subject}</td>
                <td className="py-1"><Pill tone={r.status === 'delivered' ? 'open' : r.status === 'failed' ? 'reject' : 'draft'}>{r.status}</Pill></td>
              </tr>
            ))}</tbody>
          </table>
        )}
      </CardBody>
    </Card>
  )
}

function IntegrationsTab({ orgId }: { orgId: string | null }) {
  const supabase = browserSupabase()
  type Connector = { id: string; kind: string; status: string; display_name: string; last_sync_at: string | null; last_error: string | null }
  const [rows, setRows] = useState<Connector[]>([])
  const [err, setErr] = useState<string | null>(null)
  const load = useCallback(async () => {
    if (!orgId) return
    const { data, error } = await supabase.rpc('integration_connectors_for_org' as never, { p_org_id: orgId } as never)
    if (error) setErr(error.message); else setRows(((data ?? []) as unknown as Connector[]))
  }, [supabase, orgId])
  useEffect(() => { void load() }, [load])
  const register = useCallback(async (kind: string, displayName: string) => {
    if (!orgId) return
    const rationale = window.prompt(`Rationale for registering the ${kind} connector (≥20 chars):`)
    if (!rationale || rationale.length < 20) return
    const { error } = await supabase.rpc('integration_connector_upsert' as never,
      { p_org_id: orgId, p_kind: kind, p_display_name: displayName, p_status: 'not_configured', p_config: {}, p_rationale: rationale } as never)
    if (error) setErr(error.message); else await load()
  }, [supabase, orgId, load])
  const KINDS = [
    { k: 'hibob',            n: 'HiBob (HRIS)' },
    { k: 'personio',         n: 'Personio (HRIS)' },
    { k: 'workday',          n: 'Workday (HRIS)' },
    { k: 'slack',            n: 'Slack' },
    { k: 'teams',            n: 'Microsoft Teams' },
    { k: 'google_calendar',  n: 'Google Calendar' },
    { k: 'outlook_calendar', n: 'Outlook Calendar' },
    { k: 'generic_webhook',  n: 'Generic webhook' },
  ]
  return (
    <Card data-test="integrations-tab">
      <CardEyebrow><Plug size={12} /> Integrations</CardEyebrow>
      <CardTitle>HRIS, calendar, chat — connector registry</CardTitle>
      <CardBody>
        <div className="rounded border border-amber/40 bg-internal-bg/40 px-3 py-2 text-xs text-internal-fg mb-3 flex items-start gap-2">
          <AlertTriangle size={13} className="mt-0.5 flex-shrink-0" />
          <span><strong>Registry-only today.</strong> Registering a connector creates a row + audit + admin_decision so the org's
          intention is recorded. Actual API calls (HiBob, Personio, Workday) require operator-side credentials +
          per-vendor SDKs — out-of-scope here.</span>
        </div>
        {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust mb-3">{err}</div>}
        <table className="w-full text-sm">
          <thead className="text-faint text-xs uppercase tracking-wider"><tr><th className="text-left py-1">Connector</th><th className="text-left">Status</th><th className="text-left">Last sync</th><th></th></tr></thead>
          <tbody>{KINDS.map(({ k, n }) => {
            const existing = rows.find(r => r.kind === k)
            return (
              <tr key={k} className="border-t border-line">
                <td className="py-2"><div className="font-semibold">{n}</div><div className="text-xs font-mono text-faint">{k}</div></td>
                <td className="py-2"><Pill tone={existing?.status === 'active' ? 'open' : existing ? 'draft' : 'reject'}>{existing?.status ?? 'unregistered'}</Pill></td>
                <td className="py-2 text-xs text-faint">{existing?.last_sync_at ? new Date(existing.last_sync_at).toLocaleDateString() : '—'}</td>
                <td className="py-2"><Button variant="ghost" onClick={() => register(k, n)} className="text-xs">{existing ? 'Re-register' : 'Register'}…</Button></td>
              </tr>
            )
          })}</tbody>
        </table>
      </CardBody>
    </Card>
  )
}

function toCsv(rows: AuditEvent[]): string {
  if (rows.length === 0) return 'at,action,entity_type,entity_id,actor_name,before_json,after_json\n'
  const esc = (v: unknown) => {
    if (v === null || v === undefined) return ''
    const s = typeof v === 'string' ? v : JSON.stringify(v)
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  const header = 'at,action,entity_type,entity_id,actor_name,before_json,after_json'
  const body = rows.map(r => [
    r.at, r.action, r.entity_type, r.entity_id ?? '',
    r.actor_name ?? '', esc(r.before_json), esc(r.after_json)
  ].map(esc).join(','))
  return [header, ...body].join('\n')
}

function RetentionPreferencesView({ settings }: { settings: Record<string, unknown> | null }) {
  const rp = (settings?.retention_preferences ?? null) as Record<string, { validity_status: string; note: string }> | null
  return (
    <div data-test="retention-preferences" className="mt-4 border border-dashed border-amber/40 bg-internal-bg/40 rounded p-4">
      <div className="flex items-center gap-2 mb-2">
        <span className="text-[10.5px] uppercase tracking-wider font-bold text-internal-fg">Retention preferences</span>
        <Pill>read-only · operator decision</Pill>
      </div>
      <p className="text-xs text-muted mb-3">
        Retention policy is an <strong>operator item</strong> — set out-of-band per CLAUDE-CODE-CLOSURE-PROMPT.
        Surfaced here for admin visibility, not editable client-side.
      </p>
      <ul className="text-sm flex flex-col gap-1.5">
        {(rp ? Object.entries(rp) : [
          ['hiring_records',  { validity_status: 'dev_stub', note: 'Requires policy decision' }],
          ['pulse_data',      { validity_status: 'dev_stub', note: 'Requires policy decision' }],
          ['audit_log',       { validity_status: 'dev_stub', note: 'Requires policy decision' }],
          ['consent_records', { validity_status: 'dev_stub', note: 'Requires policy decision' }],
        ] as [string, { validity_status: string; note: string }][]).map(([k, v]) => (
          <li key={k} className="flex items-center gap-2">
            <code className="font-mono text-xs flex-shrink-0">{k}</code>
            <Pill tone="reject">{v.validity_status}</Pill>
            <span className="text-xs text-faint">{v.note}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

type OrgRow = { org_id: string; name: string; type: string; is_admin: boolean }
type OrgInfo = { id: string; name: string; type: string; country: string; locale_default: string; data_region: string; status: string; settings_json: Record<string, unknown> }
type Member = { membership_id: string; person_id: string; name: string; email: string; status: string; roles: string[] | null }
type AuditEvent = {
  id?: string
  action: string
  entity_type: string
  entity_id?: string | null
  at: string
  actor_person_id: string | null
  actor_name?: string | null
  before_json?: Record<string, unknown> | null
  after_json?:  Record<string, unknown> | null
}
type ModuleToggle = { key: string; enabled: boolean; config: Record<string, unknown> }
type ModuleState = {
  module_key: string
  module_name: string
  availability: 'available' | 'requires_part2' | 'requires_expert_signoff'
  availability_note: string | null
  enabled: boolean
  last_toggled_at: string | null
}
type DataExport = { id: string; requested_at: string; status: string }
type Overview = {
  organization: OrgInfo
  members: Member[]
  members_total: number
  members_limit: number
  members_offset: number
  consent_counts: Record<string, number>
  module_toggles: ModuleToggle[]
  audit_recent: AuditEvent[]
  data_exports: DataExport[]
}
type AuditQuery = { rows: AuditEvent[]; total: number; limit: number; offset: number }
type InviteTokenRow = { id: string; token: string; invited_email: string; expires_at: string; accepted_at: string | null; revoked_at: string | null }

const ALL_ROLES = ['hiring_manager','people_ops_admin','manager','employee','org_admin','recruiter'] as const
const PAGE_SIZE = 25

export function WorkspaceAdminPage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [authBusy, setAuthBusy] = useState(false)
  const [tab, setTab] = useState<'org' | 'users' | 'me' | 'compliance' | 'modules' | 'notifications' | 'integrations'>('org')
  const [overview, setOverview] = useState<Overview | null>(null)
  const [orgs, setOrgs] = useState<OrgRow[]>([])
  const [orgId, setOrgId] = useState<string | null>(null)
  const [memberOffset, setMemberOffset] = useState(0)
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState<string | null>(null)
  const [topErr, setTopErr] = useState<string | null>(null)

  // Org form
  const [displayName, setDisplayName] = useState('')
  const [legalName, setLegalName] = useState('')
  const [accentColor, setAccentColor] = useState('#3a4d3f')
  const [logoUrl, setLogoUrl] = useState('')
  const [dpaUrl, setDpaUrl] = useState('')
  const [localeDefault, setLocaleDefault] = useState<string>('en')

  // Invite form
  const [inviteEmail, setInviteEmail] = useState('')
  const [inviteName, setInviteName] = useState('')
  const [inviteRole, setInviteRole] = useState('hiring_manager')
  const [recentToken, setRecentToken] = useState<InviteTokenRow | null>(null)

  // Audit query
  const [auditFilter, setAuditFilter] = useState({ actionLike: '', entityType: '', actorId: '', since: '', until: '', complianceOnly: false })
  const [auditPage, setAuditPage] = useState(0)
  const [audit, setAudit] = useState<AuditQuery | null>(null)
  const [auditLoading, setAuditLoading] = useState(false)
  const [auditActors, setAuditActors] = useState<{ person_id: string; full_name: string; primary_email: string }[]>([])

  // Pending invites
  const [pendingInvites, setPendingInvites] = useState<InviteTokenRow[]>([])

  // Module states
  const [moduleStates, setModuleStates] = useState<ModuleState[]>([])

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  const loadOrgs = useCallback(async () => {
    if (!signedIn) { setOrgs([]); setOrgId(null); return }
    const { data, error } = await supabase.rpc('org_for_current_user' as never)
    if (error) { setTopErr(error.message); return }
    const rows = ((data as unknown as { rows: OrgRow[] })?.rows ?? []).filter(r => r.is_admin)
    setOrgs(rows)
    if (rows.length > 0 && !orgId) setOrgId(rows[0]!.org_id)
  }, [supabase, signedIn, orgId])

  const load = useCallback(async () => {
    if (!signedIn || !orgId) return
    setLoading(true); setTopErr(null)
    const { data, error } = await supabase.rpc('admin_overview' as never, { p_org_id: orgId, p_members_limit: PAGE_SIZE, p_members_offset: memberOffset } as never)
    setLoading(false)
    if (error) { setTopErr(error.message); return }
    const ov = data as unknown as Overview
    setOverview(ov)
    setDisplayName(ov.organization.name ?? '')
    const s = (ov.organization.settings_json ?? {}) as Record<string, string>
    setLegalName(s.legal_name ?? '')
    setAccentColor(s.accent_color ?? '#3a4d3f')
    setLogoUrl(s.logo_url ?? '')
    setDpaUrl(s.dpa_url ?? '')
    setLocaleDefault(ov.organization.locale_default ?? 'en')
  }, [signedIn, supabase, orgId, memberOffset])

  const loadAudit = useCallback(async () => {
    if (!orgId) return
    setAuditLoading(true)
    if (auditFilter.complianceOnly) {
      const { data, error } = await supabase.rpc('admin_audit_compliance_view' as never, {
        p_org_id: orgId,
        p_since: auditFilter.since ? new Date(auditFilter.since).toISOString() : null,
        p_until: auditFilter.until ? new Date(auditFilter.until).toISOString() : null,
        p_limit: PAGE_SIZE, p_offset: auditPage * PAGE_SIZE,
      } as never)
      setAuditLoading(false)
      if (error) { setTopErr(error.message); return }
      const rows = (data ?? []) as unknown as AuditEvent[]
      setAudit({ rows, total: rows.length, limit: PAGE_SIZE, offset: auditPage * PAGE_SIZE })
    } else {
      const { data, error } = await supabase.rpc('admin_audit_log_query' as never, {
        p_org_id: orgId,
        p_action_like: auditFilter.actionLike ? `${auditFilter.actionLike}%` : null,
        p_actor_id: auditFilter.actorId || null,
        p_entity_type: auditFilter.entityType || null,
        p_since: auditFilter.since ? new Date(auditFilter.since).toISOString() : null,
        p_until: auditFilter.until ? new Date(auditFilter.until).toISOString() : null,
        p_limit: PAGE_SIZE, p_offset: auditPage * PAGE_SIZE,
      } as never)
      setAuditLoading(false)
      if (error) { setTopErr(error.message); return }
      setAudit(data as unknown as AuditQuery)
    }
  }, [supabase, orgId, auditFilter, auditPage])

  const loadAuditActors = useCallback(async () => {
    if (!orgId) return
    const { data, error } = await supabase.rpc('admin_audit_actors' as never, { p_org_id: orgId } as never)
    if (!error) setAuditActors((data ?? []) as unknown as { person_id: string; full_name: string; primary_email: string }[])
  }, [supabase, orgId])

  const exportAudit = useCallback(async (format: 'json' | 'csv') => {
    if (!orgId) return
    setBusy('export_audit'); setTopErr(null)
    const { data, error } = await supabase.rpc('admin_audit_log_export' as never, {
      p_org_id: orgId,
      p_action_like: auditFilter.actionLike ? `${auditFilter.actionLike}%` : null,
      p_actor_id: auditFilter.actorId || null,
      p_entity_type: auditFilter.entityType || null,
      p_since: auditFilter.since ? new Date(auditFilter.since).toISOString() : null,
      p_until: auditFilter.until ? new Date(auditFilter.until).toISOString() : null,
      p_format: format, p_limit: 5000,
    } as never)
    setBusy(null)
    if (error) { setTopErr(error.message); return }
    const result = data as unknown as { rows: AuditEvent[]; count: number }
    const blob = format === 'csv'
      ? new Blob([toCsv(result.rows)], { type: 'text/csv' })
      : new Blob([JSON.stringify(result.rows, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `audit_log_${new Date().toISOString().slice(0,10)}.${format}`
    a.click()
    URL.revokeObjectURL(url)
  }, [supabase, orgId, auditFilter])

  useEffect(() => { void loadOrgs() }, [loadOrgs])
  useEffect(() => { void load() }, [load])
  useEffect(() => { if (tab === 'compliance') { void loadAudit(); void loadAuditActors() } }, [tab, loadAudit, loadAuditActors])

  const signIn = useCallback(async () => {
    setAuthBusy(true); setTopErr(null)
    const { error } = await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' })
    setAuthBusy(false)
    if (error) setTopErr(`Sign-in failed: ${error.message}`)
  }, [supabase])
  const signOut = useCallback(async () => { await supabase.auth.signOut() }, [supabase])

  const saveOrg = useCallback(async () => {
    if (!orgId) return
    const rationale = window.prompt('Rationale for this org-settings change (≥20 chars):')
    if (!rationale || rationale.length < 20) return
    setBusy('org'); setTopErr(null)
    const { error } = await supabase.rpc('org_settings_update_v2' as never, {
      p_org_id: orgId, p_display_name: displayName || null, p_legal_name: legalName || null,
      p_accent_color: accentColor || null, p_logo_url: logoUrl || null, p_dpa_url: dpaUrl || null,
      p_locale_default: localeDefault || null, p_rationale: rationale,
    } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, orgId, displayName, legalName, accentColor, logoUrl, dpaUrl, localeDefault, load])

  const invite = useCallback(async () => {
    if (!orgId) return
    setBusy('invite'); setTopErr(null); setRecentToken(null)
    const { data: mid, error } = await supabase.rpc('org_invite_user' as never, {
      p_org_id: orgId, p_email: inviteEmail, p_rbac_role_key: inviteRole, p_full_name: inviteName || null,
    } as never)
    if (!error && mid) {
      const { data: tokRaw } = await supabase.rpc('invite_token_for' as never, { p_membership_id: mid } as never)
      if (tokRaw) setRecentToken(tokRaw as unknown as InviteTokenRow)
      setInviteEmail(''); setInviteName('')
    } else if (error) {
      setTopErr(error.message)
    }
    setBusy(null)
    await load()
  }, [supabase, orgId, inviteEmail, inviteRole, inviteName, load])

  const toggleRole = useCallback(async (membershipId: string, roleKey: string, currentlyAttached: boolean) => {
    setBusy(membershipId + roleKey); setTopErr(null)
    const fn = currentlyAttached ? 'org_role_detach' : 'org_role_attach'
    const { error } = await supabase.rpc(fn as never, { p_membership_id: membershipId, p_rbac_role_key: roleKey } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, load])

  const deactivate = useCallback(async (membershipId: string) => {
    const rationale = window.prompt('Rationale for deactivating this user (≥20 chars):')
    if (!rationale || rationale.length < 20) return
    setBusy(membershipId); setTopErr(null)
    const { error } = await supabase.rpc('org_deactivate_user' as never, { p_membership_id: membershipId, p_rationale: rationale } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, load])

  const reactivate = useCallback(async (membershipId: string) => {
    const rationale = window.prompt('Rationale for reactivating this user (≥20 chars):')
    if (!rationale || rationale.length < 20) return
    setBusy(membershipId); setTopErr(null)
    const { error } = await supabase.rpc('org_reactivate_user' as never, { p_membership_id: membershipId, p_rationale: rationale } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, load])

  const changePrimaryRole = useCallback(async (membershipId: string) => {
    const role = window.prompt('New primary RBAC role key (employee/manager/hiring_manager/recruiter/people_ops_admin/org_admin):')
    if (!role) return
    const rationale = window.prompt('Rationale for the role change (≥20 chars):')
    if (!rationale || rationale.length < 20) return
    setBusy(membershipId); setTopErr(null)
    const { error } = await supabase.rpc('org_change_role' as never, { p_membership_id: membershipId, p_new_rbac_role_key: role, p_rationale: rationale } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, load])

  const loadPending = useCallback(async () => {
    if (!orgId) return
    const { data, error } = await supabase.rpc('org_pending_invites' as never, { p_org_id: orgId } as never)
    if (error) { setTopErr(error.message); return }
    setPendingInvites((data ?? []) as unknown as InviteTokenRow[])
  }, [supabase, orgId])

  const resendInvite = useCallback(async (tokenId: string) => {
    setBusy(tokenId); setTopErr(null)
    const { error } = await supabase.rpc('org_invite_resend' as never, { p_token_id: tokenId, p_extend_days: 14 } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await loadPending()
  }, [supabase, loadPending])

  const cancelInvite = useCallback(async (tokenId: string) => {
    if (!window.confirm('Revoke this invite? The link will no longer work.')) return
    setBusy(tokenId); setTopErr(null)
    const { error } = await supabase.rpc('org_invite_revoke' as never, { p_token_id: tokenId } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await loadPending()
  }, [supabase, loadPending])

  useEffect(() => { if (tab === 'users') void loadPending() }, [tab, loadPending])

  const loadModules = useCallback(async () => {
    if (!orgId) return
    const { data, error } = await supabase.rpc('org_modules_state' as never, { p_org_id: orgId } as never)
    if (error) { setTopErr(error.message); return }
    setModuleStates((data ?? []) as unknown as ModuleState[])
  }, [supabase, orgId])
  useEffect(() => { if (tab === 'modules') void loadModules() }, [tab, loadModules])

  const toggleModule = useCallback(async (key: string, enable: boolean) => {
    const rationale = window.prompt(`Rationale for ${enable ? 'enabling' : 'disabling'} the ${key} module (≥20 chars):`)
    if (!rationale || rationale.length < 20) return
    setBusy(key); setTopErr(null)
    const { error } = await supabase.rpc('org_module_set_enabled' as never,
      { p_org_id: orgId, p_module_key: key, p_enabled: enable, p_rationale: rationale } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await loadModules()
  }, [supabase, orgId, loadModules])

  const requestExport = useCallback(async () => {
    if (!orgId) return
    setBusy('export'); setTopErr(null)
    const { error } = await supabase.rpc('data_export_request_create' as never, { p_org_id: orgId, p_scope: { all: true } } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, orgId, load])

  const copyInviteLink = useCallback(async (token: string) => {
    const url = `${window.location.origin}/admin/accept-invite/${token}`
    try { await navigator.clipboard.writeText(url) } catch { /* no-op */ }
  }, [])

  const accentSwatchStyle = useMemo(() => ({ background: accentColor }), [accentColor])

  return (
    <Shell breadcrumb={<span>Workspace admin · <strong>{overview?.organization.name ?? '…'}</strong></span>} signedInLabel={signedIn ?? undefined}>
      <div className="flex flex-col gap-6">
        <header className="flex items-end justify-between gap-4 flex-wrap">
          <div>
            <h1 className="font-display text-3xl font-bold tracking-tight text-ink">Workspace admin</h1>
            <p className="text-faint mt-1">Org profile, user management, compliance & data — minimum subset to operate.</p>
          </div>
          <div className="flex items-center gap-2">
            {orgs.length > 1 && signedIn && (
              <select className="border border-line rounded px-3 py-2 text-sm" value={orgId ?? ''} onChange={e => setOrgId(e.target.value)}>
                {orgs.map(o => <option key={o.org_id} value={o.org_id}>{o.name}</option>)}
              </select>
            )}
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

        {orgs.length === 0 && signedIn && (
          <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900 flex items-center gap-2">
            <AlertTriangle size={14} /> You are signed in but have no org with <code>org.manage_all</code>.
          </div>
        )}
        {topErr && <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-900">{topErr}</div>}

        <TabBand>
          <Tab active={tab === 'org'} onClick={() => setTab('org')}><Building2 size={14} /> Org profile</Tab>
          <Tab active={tab === 'users'} onClick={() => setTab('users')}><Users size={14} /> Users</Tab>
          <Tab active={tab === 'me'} onClick={() => setTab('me')}><SettingsIcon size={14} /> My profile</Tab>
          <Tab active={tab === 'compliance'} onClick={() => setTab('compliance')}><Shield size={14} /> Compliance & data</Tab>
          <Tab active={tab === 'modules'} onClick={() => setTab('modules')}><FileText size={14} /> Modules</Tab>
          <Tab active={tab === 'notifications'} onClick={() => setTab('notifications')}><Bell size={14} /> Notifications</Tab>
          <Tab active={tab === 'integrations'} onClick={() => setTab('integrations')}><Plug size={14} /> Integrations</Tab>
        </TabBand>

        {loading && <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>}

        {tab === 'org' && overview && (
          <Card>
            <CardEyebrow><Building2 size={12} /> Organization profile</CardEyebrow>
            <CardTitle>{overview.organization.name}</CardTitle>
            <CardBody>
              <div className="grid lg:grid-cols-2 gap-4">
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">Display name</span>
                  <input className="border border-line rounded px-3 py-2 text-sm" value={displayName} onChange={e => setDisplayName(e.target.value)} />
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">Legal name</span>
                  <input className="border border-line rounded px-3 py-2 text-sm" value={legalName} onChange={e => setLegalName(e.target.value)} />
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">Accent color</span>
                  <div className="flex items-center gap-2">
                    <input type="color" value={accentColor} onChange={e => setAccentColor(e.target.value)} />
                    <input className="border border-line rounded px-2 py-1 text-sm font-mono" value={accentColor} onChange={e => setAccentColor(e.target.value)} placeholder="#3a4d3f" />
                    <span className="inline-block w-5 h-5 rounded border border-line" style={accentSwatchStyle} />
                  </div>
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">Logo URL (https://)</span>
                  <input className="border border-line rounded px-3 py-2 text-sm" value={logoUrl} onChange={e => setLogoUrl(e.target.value)} placeholder="https://…" />
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">Default language</span>
                  <select className="border border-line rounded px-3 py-2 text-sm bg-surface" value={localeDefault} onChange={e => setLocaleDefault(e.target.value)}>
                    {LOCALES.map(l => <option key={l.code} value={l.code}>{l.nativeLabel} ({l.code})</option>)}
                  </select>
                </label>
                <label className="flex flex-col gap-1 lg:col-span-2">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">DPA / privacy posture URL (https://)</span>
                  <input className="border border-line rounded px-3 py-2 text-sm" value={dpaUrl} onChange={e => setDpaUrl(e.target.value)} placeholder="https://…" />
                </label>
              </div>
              <ContrastPreview hex={accentColor} />
              <div className="mt-4 flex items-center gap-2">
                <Button onClick={saveOrg} disabled={busy === 'org'}>{busy === 'org' ? <Loader2 size={14} className="animate-spin" /> : null} Save (rationale required)</Button>
                <Pill>data_region: {overview.organization.data_region}</Pill>
                <Pill>country: {overview.organization.country}</Pill>
                <Pill>type: {overview.organization.type}</Pill>
              </div>
              <RetentionPreferencesView settings={overview.organization.settings_json} />
            </CardBody>
          </Card>
        )}

        {tab === 'users' && overview && (
          <div className="flex flex-col gap-4">
            <Card>
              <CardEyebrow><UserPlus size={12} /> Invite user</CardEyebrow>
              <CardTitle>Add someone to {overview.organization.name}</CardTitle>
              <CardBody>
                <div className="grid lg:grid-cols-4 gap-3 items-end">
                  <input className="border border-line rounded px-3 py-2 text-sm" placeholder="email@org" value={inviteEmail} onChange={e => setInviteEmail(e.target.value)} />
                  <input className="border border-line rounded px-3 py-2 text-sm" placeholder="Full name (optional)" value={inviteName} onChange={e => setInviteName(e.target.value)} />
                  <select className="border border-line rounded px-3 py-2 text-sm" value={inviteRole} onChange={e => setInviteRole(e.target.value)}>
                    {ALL_ROLES.map(r => <option key={r} value={r}>{r}</option>)}
                  </select>
                  <Button onClick={invite} disabled={busy === 'invite' || !inviteEmail}>{busy === 'invite' ? <Loader2 size={14} className="animate-spin" /> : null} Invite</Button>
                </div>
                {recentToken && (
                  <div className="mt-3 rounded-lg border border-line bg-canvas p-3 text-sm flex items-center justify-between gap-3">
                    <span><LinkIcon size={12} className="inline mr-1" /> Invite link for <strong>{recentToken.invited_email}</strong> — expires {new Date(recentToken.expires_at).toLocaleString()}</span>
                    <Button variant="ghost" onClick={() => copyInviteLink(recentToken.token)}><Copy size={14} /> Copy link</Button>
                  </div>
                )}
              </CardBody>
            </Card>
            <Card>
              <CardEyebrow><Users size={12} /> Members ({overview.members_total})</CardEyebrow>
              <CardTitle>Org membership</CardTitle>
              <CardBody>
                <table className="w-full text-sm">
                  <thead className="text-faint text-xs uppercase tracking-wider">
                    <tr><th className="text-left py-1">Name</th><th className="text-left">Email</th><th className="text-left">Status</th><th className="text-left">Role(s) — toggle to attach/detach</th><th></th></tr>
                  </thead>
                  <tbody>
                    {overview.members.map(m => (
                      <tr key={m.membership_id} className="border-t border-line align-top">
                        <td className="py-2">{m.name}</td>
                        <td className="py-2 text-faint">{m.email}</td>
                        <td className="py-2"><Pill>{m.status}</Pill></td>
                        <td className="py-2">
                          <div className="flex flex-wrap gap-1.5">
                            {ALL_ROLES.map(r => {
                              const has = (m.roles ?? []).includes(r)
                              const k = m.membership_id + r
                              return (
                                <button key={r}
                                  onClick={() => toggleRole(m.membership_id, r, has)}
                                  disabled={busy === k}
                                  className={'text-xs uppercase tracking-wider font-bold px-2 py-1 rounded ' +
                                    (has ? 'bg-forest text-white' : 'border border-line text-faint hover:text-ink')}>
                                  {has ? '✓ ' : ''}{r}
                                </button>
                              )
                            })}
                          </div>
                        </td>
                        <td className="py-2">
                          <div className="flex gap-1.5">
                            <Button variant="ghost" disabled={busy === m.membership_id} onClick={() => changePrimaryRole(m.membership_id)} className="text-xs">Change role…</Button>
                            {m.status === 'suspended'
                              ? <Button variant="ghost" disabled={busy === m.membership_id} onClick={() => reactivate(m.membership_id)} className="text-xs text-green">Reactivate</Button>
                              : <Button variant="ghost" disabled={busy === m.membership_id} onClick={() => deactivate(m.membership_id)} className="text-xs text-rust">Deactivate</Button>}
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <div className="mt-3 flex items-center gap-2 text-xs text-faint">
                  <Button variant="ghost" disabled={memberOffset === 0} onClick={() => setMemberOffset(Math.max(0, memberOffset - PAGE_SIZE))}>← Previous</Button>
                  <span>{memberOffset + 1}–{Math.min(memberOffset + PAGE_SIZE, overview.members_total)} of {overview.members_total}</span>
                  <Button variant="ghost" disabled={memberOffset + PAGE_SIZE >= overview.members_total} onClick={() => setMemberOffset(memberOffset + PAGE_SIZE)}>Next →</Button>
                </div>
              </CardBody>
            </Card>

            {/* Pending invites */}
            <Card data-test="pending-invites">
              <CardEyebrow><LinkIcon size={12} /> Pending invites</CardEyebrow>
              <CardTitle>Outstanding magic links</CardTitle>
              <CardBody>
                <div className="rounded border border-amber/40 bg-internal-bg/40 px-3 py-2 text-xs text-internal-fg mb-3 flex items-start gap-2">
                  <AlertTriangle size={13} className="mt-0.5 flex-shrink-0" />
                  <span>Email infrastructure pending operator action. Copy the link below into your own email client until SMTP is wired (per the closure-report operator list).</span>
                </div>
                {pendingInvites.filter(i => !i.accepted_at && !i.revoked_at).length === 0 && (
                  <p className="text-faint text-sm">No outstanding invites.</p>
                )}
                <ul className="flex flex-col gap-2 text-sm">
                  {pendingInvites.filter(i => !i.accepted_at && !i.revoked_at).map(i => (
                    <li key={i.id} className="flex items-center gap-3 border-b border-line pb-2">
                      <span className="flex-1 min-w-0">
                        <strong>{i.invited_email}</strong>
                        <span className="text-xs text-faint ml-2">expires {new Date(i.expires_at).toLocaleDateString()}</span>
                      </span>
                      <Button variant="ghost" disabled={busy === i.id} onClick={() => copyInviteLink(i.token)} className="text-xs"><Copy size={12} /> Copy link</Button>
                      <Button variant="ghost" disabled={busy === i.id} onClick={() => resendInvite(i.id)} className="text-xs">Resend (+14d)</Button>
                      <Button variant="ghost" disabled={busy === i.id} onClick={() => cancelInvite(i.id)} className="text-xs text-rust">Cancel</Button>
                    </li>
                  ))}
                </ul>
              </CardBody>
            </Card>
          </div>
        )}

        {tab === 'me' && (
          <MyProfileTab signedIn={signedIn} />
        )}

        {tab === 'compliance' && overview && (
          <div className="flex flex-col gap-4">
            <Card>
              <CardEyebrow><Shield size={12} /> Consent ledger</CardEyebrow>
              <CardTitle>Active grants by purpose</CardTitle>
              <CardBody>
                {Object.keys(overview.consent_counts).length === 0 && <p className="text-faint text-sm">No active grants.</p>}
                <ul className="text-sm flex flex-wrap gap-3">
                  {Object.entries(overview.consent_counts).map(([purpose, cnt]) => (
                    <li key={purpose} className="flex items-center gap-2"><Pill>{purpose}</Pill><span className="font-semibold">{cnt}</span></li>
                  ))}
                </ul>
              </CardBody>
            </Card>
            <Card>
              <CardEyebrow><FileText size={12} /> Audit log</CardEyebrow>
              <CardTitle>Filter, paginate, inspect</CardTitle>
              <CardBody>
                <div className="grid lg:grid-cols-3 gap-2 items-end mb-3" data-test="audit-filters">
                  <label className="flex flex-col gap-1">
                    <span className="text-xs font-semibold uppercase tracking-wider text-muted"><Filter size={11} className="inline mr-1" />Action prefix</span>
                    <input className="border border-line rounded px-3 py-2 text-sm" placeholder="org. / consent. / placement. / …" value={auditFilter.actionLike} onChange={e => { setAuditFilter({ ...auditFilter, actionLike: e.target.value }); setAuditPage(0) }} />
                  </label>
                  <label className="flex flex-col gap-1">
                    <span className="text-xs font-semibold uppercase tracking-wider text-muted">Entity type</span>
                    <input className="border border-line rounded px-3 py-2 text-sm" placeholder="memberships / consent_grants / …" value={auditFilter.entityType} onChange={e => { setAuditFilter({ ...auditFilter, entityType: e.target.value }); setAuditPage(0) }} />
                  </label>
                  <label className="flex flex-col gap-1">
                    <span className="text-xs font-semibold uppercase tracking-wider text-muted">Actor</span>
                    <select data-test="audit-actor-filter" className="border border-line rounded px-3 py-2 text-sm bg-surface" value={auditFilter.actorId} onChange={e => { setAuditFilter({ ...auditFilter, actorId: e.target.value }); setAuditPage(0) }}>
                      <option value="">— any actor —</option>
                      {auditActors.map(a => <option key={a.person_id} value={a.person_id}>{a.full_name}</option>)}
                    </select>
                  </label>
                  <label className="flex flex-col gap-1">
                    <span className="text-xs font-semibold uppercase tracking-wider text-muted">Since</span>
                    <input type="date" className="border border-line rounded px-3 py-2 text-sm" value={auditFilter.since} onChange={e => { setAuditFilter({ ...auditFilter, since: e.target.value }); setAuditPage(0) }} />
                  </label>
                  <label className="flex flex-col gap-1">
                    <span className="text-xs font-semibold uppercase tracking-wider text-muted">Until</span>
                    <input type="date" className="border border-line rounded px-3 py-2 text-sm" value={auditFilter.until} onChange={e => { setAuditFilter({ ...auditFilter, until: e.target.value }); setAuditPage(0) }} />
                  </label>
                  <label className="flex items-center gap-2 text-xs font-semibold text-ink mt-5">
                    <input data-test="compliance-toggle" type="checkbox" checked={auditFilter.complianceOnly} onChange={e => { setAuditFilter({ ...auditFilter, complianceOnly: e.target.checked }); setAuditPage(0) }} />
                    Compliance view (AI Act Art. 12 + GDPR Art. 30 only)
                  </label>
                </div>
                <div className="flex items-center gap-2 mb-3">
                  <Button variant="ghost" onClick={() => loadAudit()}>Refresh</Button>
                  <Button variant="ghost" disabled={busy === 'export_audit'} onClick={() => exportAudit('json')} className="text-xs"><FileDown size={12} /> Export JSON</Button>
                  <Button variant="ghost" disabled={busy === 'export_audit'} onClick={() => exportAudit('csv')} className="text-xs"><FileDown size={12} /> Export CSV</Button>
                  <span className="text-[11px] text-faint ml-2">Export writes its own <code className="font-mono">audit_log_exported_by</code> row.</span>
                </div>
                {auditLoading && <div className="text-faint text-xs flex items-center gap-2 py-2"><Loader2 size={12} className="animate-spin" /> Searching…</div>}
                {!auditLoading && audit && audit.rows.length === 0 && (
                  <div className="text-faint text-xs py-6 text-center border border-dashed border-line rounded">
                    No events match your filter.
                  </div>
                )}
                {!auditLoading && audit && audit.rows.length > 0 && (
                  <AuditLogTable rows={audit.rows} />
                )}
                {audit && (
                  <div className="mt-3 flex items-center gap-2 text-xs text-faint">
                    <Button variant="ghost" disabled={auditPage === 0} onClick={() => setAuditPage(Math.max(0, auditPage - 1))}>← Previous</Button>
                    <span>{audit.offset + 1}–{Math.min(audit.offset + audit.rows.length, audit.total)} of {audit.total}</span>
                    <Button variant="ghost" disabled={(audit.offset + audit.limit) >= audit.total} onClick={() => setAuditPage(auditPage + 1)}>Next →</Button>
                  </div>
                )}
              </CardBody>
            </Card>
            <Card>
              <CardEyebrow><FileDown size={12} /> Data export</CardEyebrow>
              <CardTitle>Request export (delivered out-of-band)</CardTitle>
              <CardBody>
                <Button onClick={requestExport} disabled={busy === 'export'}>{busy === 'export' ? <Loader2 size={14} className="animate-spin" /> : null} File export request</Button>
                {overview.data_exports.length > 0 && (
                  <ul className="mt-3 text-sm">
                    {overview.data_exports.map(r => (
                      <li key={r.id} className="flex items-center gap-2"><span className="text-faint">{new Date(r.requested_at).toLocaleString()}</span><Pill>{r.status}</Pill></li>
                    ))}
                  </ul>
                )}
              </CardBody>
            </Card>
          </div>
        )}

        {tab === 'notifications' && <NotificationsTab orgId={orgId} />}
        {tab === 'integrations' && <IntegrationsTab orgId={orgId} />}

        {tab === 'modules' && (
          <Card data-test="modules-tab">
            <CardEyebrow><FileText size={12} /> Modules</CardEyebrow>
            <CardTitle>Capabilities enabled for this org</CardTitle>
            <CardBody>
              <p className="text-muted text-xs mb-4 max-w-2xl">
                Toggle enables / disables a module for this org. Disabled modules hide from the
                sidebar and any direct route shows a "module disabled" message.{' '}
                <strong>requires_part2</strong> + <strong>requires_expert_signoff</strong> are
                locked off at the DB layer — no admin (including yourself) can flip them on until
                the gating work lands.
              </p>
              <table className="w-full text-sm">
                <thead className="text-faint text-xs uppercase tracking-wider">
                  <tr>
                    <th className="text-left py-1">Module</th>
                    <th className="text-left">Availability</th>
                    <th className="text-left">State</th>
                    <th className="text-left">Last toggled</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {moduleStates.map(m => {
                    const locked = m.availability !== 'available'
                    return (
                      <tr key={m.module_key} className="border-t border-line align-top">
                        <td className="py-2">
                          <div className="font-semibold">{m.module_name}</div>
                          <div className="text-xs text-faint font-mono">{m.module_key}</div>
                          {m.availability_note && <div className="text-xs text-muted mt-1 max-w-md">{m.availability_note}</div>}
                        </td>
                        <td className="py-2">
                          <Pill tone={m.availability === 'available' ? 'open' : 'reject'}>{m.availability}</Pill>
                        </td>
                        <td className="py-2"><Pill tone={m.enabled ? 'open' : 'draft'}>{m.enabled ? 'enabled' : 'disabled'}</Pill></td>
                        <td className="py-2 text-xs text-faint">{m.last_toggled_at ? new Date(m.last_toggled_at).toLocaleDateString() : '—'}</td>
                        <td className="py-2">
                          {locked
                            ? <span className="text-xs text-faint italic">Locked</span>
                            : <Button variant="ghost" disabled={busy === m.module_key} onClick={() => toggleModule(m.module_key, !m.enabled)} className="text-xs">
                                {m.enabled ? 'Disable' : 'Enable'}…
                              </Button>}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </CardBody>
          </Card>
        )}
      </div>
    </Shell>
  )
}

// Audit log table with per-row expansion to show before/after JSON.
// The audit_log columns are immutable + insert-only per CLAUDE.md;
// surfacing before/after is the compliance reviewer's primary need.
function AuditLogTable({ rows }: { rows: AuditEvent[] }) {
  const [openIdx, setOpenIdx] = useState<number | null>(null)
  return (
    <table className="w-full text-xs" data-test="audit-log-table">
      <thead className="text-faint uppercase tracking-wider">
        <tr>
          <th className="text-left py-1 w-6"></th>
          <th className="text-left py-1">At</th>
          <th className="text-left">Action</th>
          <th className="text-left">Entity</th>
          <th className="text-left">Actor</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((e, i) => {
          const expandable = !!(e.before_json || e.after_json || e.entity_id)
          const isOpen = openIdx === i
          return (
            <>
              <tr
                key={(e.id ?? i) + '-row'}
                className={'border-t border-line ' + (expandable ? 'cursor-pointer hover:bg-canvas' : '')}
                onClick={() => expandable && setOpenIdx(isOpen ? null : i)}
              >
                <td className="py-1 text-faint">
                  {expandable ? (isOpen ? <ChevronDown size={12} /> : <ChevronRight size={12} />) : null}
                </td>
                <td className="py-1">{new Date(e.at).toLocaleString()}</td>
                <td className="py-1 font-mono">{e.action}</td>
                <td className="py-1 text-faint">{e.entity_type}</td>
                <td className="py-1">{e.actor_name ?? <em className="text-faint">system</em>}</td>
              </tr>
              {isOpen && expandable && (
                <tr key={(e.id ?? i) + '-detail'} data-test="audit-log-detail">
                  <td></td>
                  <td colSpan={4} className="py-2 pb-3">
                    <div className="bg-canvas border border-line rounded p-3 grid lg:grid-cols-2 gap-3 text-[11px]">
                      {e.entity_id && (
                        <div className="lg:col-span-2 flex items-center gap-2">
                          <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">entity_id</span>
                          <code className="font-mono text-ink">{e.entity_id}</code>
                        </div>
                      )}
                      <div>
                        <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted mb-1">before</div>
                        <pre className="bg-surface border border-line rounded p-2 overflow-auto max-h-48 whitespace-pre-wrap break-words">
                          {e.before_json ? JSON.stringify(e.before_json, null, 2) : <span className="text-faint italic">null (insert)</span>}
                        </pre>
                      </div>
                      <div>
                        <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted mb-1">after</div>
                        <pre className="bg-surface border border-line rounded p-2 overflow-auto max-h-48 whitespace-pre-wrap break-words">
                          {e.after_json ? JSON.stringify(e.after_json, null, 2) : <span className="text-faint italic">null (delete)</span>}
                        </pre>
                      </div>
                    </div>
                  </td>
                </tr>
              )}
            </>
          )
        })}
      </tbody>
    </table>
  )
}

// "My profile" tab — wires to the i18n locale (the only self-managed
// preference shipped to date). When more self-service fields land
// (display name correction, email aliases, etc.), they slot in here.
function MyProfileTab({ signedIn }: { signedIn: string | null }) {
  const supabase = browserSupabase()
  const { locale, setLocale } = useLocale()
  type MyMembership = { membership_id: string; org_id: string; org_name: string; status: string; roles: string[] }
  const [mems, setMems] = useState<MyMembership[]>([])
  const [myAudit, setMyAudit] = useState<AuditEvent[]>([])
  const [err, setErr] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    const [{ data: m }, { data: a }] = await Promise.all([
      supabase.rpc('me_memberships' as never),
      supabase.rpc('me_audit_log' as never, { p_limit: 25, p_offset: 0 } as never),
    ])
    setMems((m ?? []) as unknown as MyMembership[])
    setMyAudit((a ?? []) as unknown as AuditEvent[])
  }, [supabase])
  useEffect(() => { void refresh() }, [refresh])

  const leave = useCallback(async (membershipId: string) => {
    const rationale = window.prompt('Rationale for leaving this org (≥20 chars). You will enter a 7-day grace period and can cancel.')
    if (!rationale || rationale.length < 20) return
    const { error } = await supabase.rpc('me_leave_request' as never, { p_membership_id: membershipId, p_rationale: rationale } as never)
    if (error) setErr(error.message); else await refresh()
  }, [supabase, refresh])
  const cancelLeave = useCallback(async (membershipId: string) => {
    const rationale = window.prompt('Rationale for cancelling this leave (≥20 chars):')
    if (!rationale || rationale.length < 20) return
    const { error } = await supabase.rpc('me_leave_cancel' as never, { p_membership_id: membershipId, p_rationale: rationale } as never)
    if (error) setErr(error.message); else await refresh()
  }, [supabase, refresh])

  return (
    <div className="flex flex-col gap-4">
      {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust">{err}</div>}
      <Card>
        <CardEyebrow><SettingsIcon size={12} /> My profile</CardEyebrow>
        <CardTitle>Account &amp; preferences</CardTitle>
        <CardBody className="flex flex-col gap-4">
          <div className="grid lg:grid-cols-2 gap-4">
            <label className="flex flex-col gap-1">
              <span className="text-xs font-semibold uppercase tracking-wider text-muted">Signed in as</span>
              <input className="border border-line rounded px-3 py-2 text-sm bg-canvas" value={signedIn ?? ''} readOnly />
            </label>
            <label className="flex flex-col gap-1">
              <span className="text-xs font-semibold uppercase tracking-wider text-muted">Language</span>
              <select data-test="my-profile-locale" value={locale} onChange={e => setLocale(e.target.value as Locale)}
                className="border border-line rounded px-3 py-2 text-sm bg-surface">
                {LOCALES.map(l => <option key={l.code} value={l.code}>{l.nativeLabel} ({l.code})</option>)}
              </select>
              <span className="text-xs text-faint">Stored locally; server-side persistence lands with the user_preferences table.</span>
            </label>
          </div>
        </CardBody>
      </Card>

      <Card data-test="my-memberships">
        <CardEyebrow>My memberships</CardEyebrow>
        <CardTitle>Orgs &amp; roles</CardTitle>
        <CardBody>
          {mems.length === 0 && <p className="text-faint text-sm">You have no active memberships.</p>}
          <ul className="flex flex-col gap-2">
            {mems.map(m => (
              <li key={m.membership_id} className="flex items-center gap-3 border-b border-line pb-2 text-sm">
                <span className="flex-1">
                  <strong>{m.org_name}</strong>
                  <span className="text-xs text-faint ml-2">{m.roles.join(', ') || 'no roles'}</span>
                </span>
                <Pill tone={m.status === 'active' ? 'open' : m.status === 'leaving' ? 'reject' : 'draft'}>{m.status}</Pill>
                {m.status === 'active' && (
                  <Button variant="ghost" onClick={() => leave(m.membership_id)} className="text-xs text-rust">Leave org…</Button>
                )}
                {m.status === 'leaving' && (
                  <Button variant="ghost" onClick={() => cancelLeave(m.membership_id)} className="text-xs text-green">Cancel leave</Button>
                )}
              </li>
            ))}
          </ul>
          <p className="text-xs text-faint mt-3">
            Leave-org enters a 7-day grace window; admin is notified. Auto-finalisation to
            <code className="font-mono"> inactive</code> at grace expiry is an operator scheduler item.
          </p>
        </CardBody>
      </Card>

      <Card data-test="my-audit">
        <CardEyebrow>Recent activity</CardEyebrow>
        <CardTitle>Actions you took (last 25)</CardTitle>
        <CardBody>
          {myAudit.length === 0 && <p className="text-faint text-sm">No recorded actions.</p>}
          <table className="w-full text-xs">
            <thead className="text-faint uppercase tracking-wider"><tr><th className="text-left py-1">At</th><th className="text-left">Action</th><th className="text-left">Entity</th></tr></thead>
            <tbody>
              {myAudit.map(e => (
                <tr key={e.id} className="border-t border-line">
                  <td className="py-1">{new Date(e.at).toLocaleString()}</td>
                  <td className="py-1 font-mono">{e.action}</td>
                  <td className="py-1 text-faint">{e.entity_type}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardBody>
      </Card>
    </div>
  )
}
