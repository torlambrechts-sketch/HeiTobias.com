import { useCallback, useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Building2, Copy, FileDown, FileText, Filter, Link as LinkIcon, Loader2, LogOut, Settings as SettingsIcon, Shield, UserPlus, Users } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'
import { TabBand, Tab } from '../components/ui/tabband.js'
import { Shell } from '../components/Shell.js'
import { HitlNotice } from '../components/HitlNotice.js'

type OrgRow = { org_id: string; name: string; type: string; is_admin: boolean }
type OrgInfo = { id: string; name: string; type: string; country: string; locale_default: string; data_region: string; status: string; settings_json: Record<string, unknown> }
type Member = { membership_id: string; person_id: string; name: string; email: string; status: string; roles: string[] | null }
type AuditEvent = { id?: string; action: string; entity_type: string; at: string; actor_person_id: string | null; actor_name?: string | null }
type ModuleToggle = { key: string; enabled: boolean; config: Record<string, unknown> }
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
  const [tab, setTab] = useState<'org' | 'users' | 'me' | 'compliance' | 'modules'>('org')
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

  // Invite form
  const [inviteEmail, setInviteEmail] = useState('')
  const [inviteName, setInviteName] = useState('')
  const [inviteRole, setInviteRole] = useState('hiring_manager')
  const [recentToken, setRecentToken] = useState<InviteTokenRow | null>(null)

  // Audit query
  const [auditFilter, setAuditFilter] = useState({ actionLike: '', entityType: '' })
  const [auditPage, setAuditPage] = useState(0)
  const [audit, setAudit] = useState<AuditQuery | null>(null)

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
  }, [signedIn, supabase, orgId, memberOffset])

  const loadAudit = useCallback(async () => {
    if (!orgId) return
    const { data, error } = await supabase.rpc('admin_audit_log_query' as never, {
      p_org_id: orgId,
      p_action_like: auditFilter.actionLike ? `${auditFilter.actionLike}%` : null,
      p_entity_type: auditFilter.entityType || null,
      p_limit: PAGE_SIZE, p_offset: auditPage * PAGE_SIZE,
    } as never)
    if (error) { setTopErr(error.message); return }
    setAudit(data as unknown as AuditQuery)
  }, [supabase, orgId, auditFilter, auditPage])

  useEffect(() => { void loadOrgs() }, [loadOrgs])
  useEffect(() => { void load() }, [load])
  useEffect(() => { if (tab === 'compliance') void loadAudit() }, [tab, loadAudit])

  const signIn = useCallback(async () => {
    setAuthBusy(true); setTopErr(null)
    const { error } = await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' })
    setAuthBusy(false)
    if (error) setTopErr(`Sign-in failed: ${error.message}`)
  }, [supabase])
  const signOut = useCallback(async () => { await supabase.auth.signOut() }, [supabase])

  const saveOrg = useCallback(async () => {
    if (!orgId) return
    setBusy('org'); setTopErr(null)
    const { error } = await supabase.rpc('org_settings_update' as never, {
      p_org_id: orgId, p_display_name: displayName || null, p_legal_name: legalName || null,
      p_accent_color: accentColor || null, p_logo_url: logoUrl || null, p_dpa_url: dpaUrl || null,
    } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, orgId, displayName, legalName, accentColor, logoUrl, dpaUrl, load])

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
    setBusy(membershipId); setTopErr(null)
    const { error } = await supabase.rpc('org_deactivate_user' as never, { p_membership_id: membershipId } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, load])

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
                <label className="flex flex-col gap-1 lg:col-span-2">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">DPA / privacy posture URL (https://)</span>
                  <input className="border border-line rounded px-3 py-2 text-sm" value={dpaUrl} onChange={e => setDpaUrl(e.target.value)} placeholder="https://…" />
                </label>
              </div>
              <div className="mt-4 flex items-center gap-2">
                <Button onClick={saveOrg} disabled={busy === 'org'}>{busy === 'org' ? <Loader2 size={14} className="animate-spin" /> : null} Save</Button>
                <Pill>data_region: {overview.organization.data_region}</Pill>
                <Pill>country: {overview.organization.country}</Pill>
              </div>
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
                        <td className="py-2"><Button variant="ghost" disabled={busy === m.membership_id || m.status === 'suspended'} onClick={() => deactivate(m.membership_id)}>Deactivate</Button></td>
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
          </div>
        )}

        {tab === 'me' && (
          <Card>
            <CardEyebrow><SettingsIcon size={12} /> My profile</CardEyebrow>
            <CardTitle>Display name, email, language</CardTitle>
            <CardBody>
              <p className="text-sm text-faint">Self-profile editing scaffolded; backend wiring is outside this hardening pass.</p>
            </CardBody>
          </Card>
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
                <div className="grid lg:grid-cols-3 gap-2 items-end mb-3">
                  <label className="flex flex-col gap-1">
                    <span className="text-xs font-semibold uppercase tracking-wider text-muted"><Filter size={11} className="inline mr-1" />Action prefix</span>
                    <input className="border border-line rounded px-3 py-2 text-sm" placeholder="org. / consent. / placement. / …" value={auditFilter.actionLike} onChange={e => { setAuditFilter({ ...auditFilter, actionLike: e.target.value }); setAuditPage(0) }} />
                  </label>
                  <label className="flex flex-col gap-1">
                    <span className="text-xs font-semibold uppercase tracking-wider text-muted">Entity type</span>
                    <input className="border border-line rounded px-3 py-2 text-sm" placeholder="memberships / consent_grants / …" value={auditFilter.entityType} onChange={e => { setAuditFilter({ ...auditFilter, entityType: e.target.value }); setAuditPage(0) }} />
                  </label>
                  <Button variant="ghost" onClick={() => loadAudit()}>Refresh</Button>
                </div>
                <table className="w-full text-xs">
                  <thead className="text-faint uppercase tracking-wider">
                    <tr><th className="text-left py-1">At</th><th className="text-left">Action</th><th className="text-left">Entity</th><th className="text-left">Actor</th></tr>
                  </thead>
                  <tbody>
                    {(audit?.rows ?? []).map((e, i) => (
                      <tr key={e.id ?? i} className="border-t border-line">
                        <td className="py-1">{new Date(e.at).toLocaleString()}</td>
                        <td className="py-1 font-mono">{e.action}</td>
                        <td className="py-1 text-faint">{e.entity_type}</td>
                        <td className="py-1">{e.actor_name ?? <em className="text-faint">system</em>}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
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

        {tab === 'modules' && overview && (
          <Card>
            <CardEyebrow><FileText size={12} /> Modules</CardEyebrow>
            <CardTitle>Capabilities enabled for this org</CardTitle>
            <CardBody>
              <p className="text-faint text-xs mb-2">Read-only — toggles only activate modules already implemented.</p>
              <table className="w-full text-sm">
                <thead className="text-faint text-xs uppercase tracking-wider">
                  <tr><th className="text-left py-1">Module</th><th className="text-left">State</th></tr>
                </thead>
                <tbody>
                  {overview.module_toggles.map(m => (
                    <tr key={m.key} className="border-t border-line">
                      <td className="py-1">{m.key}</td>
                      <td className="py-1"><Pill>{m.enabled ? 'enabled' : 'disabled'}</Pill></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </CardBody>
          </Card>
        )}
      </div>
    </Shell>
  )
}
