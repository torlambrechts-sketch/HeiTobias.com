import { useCallback, useEffect, useState } from 'react'
import { Building2, FileDown, FileText, Loader2, LogOut, Settings as SettingsIcon, Shield, UserPlus, Users } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'
import { TabBand, Tab } from '../components/ui/tabband.js'
import { Shell } from '../components/Shell.js'
import { HitlNotice } from '../components/HitlNotice.js'

const FJORDTECH_ID = 'a1000000-0000-0000-0000-000000000002'

type OrgInfo = { id: string; name: string; type: string; country: string; locale_default: string; data_region: string; status: string; settings_json: Record<string, unknown> }
type Member = { membership_id: string; person_id: string; name: string; email: string; status: string; roles: string[] | null }
type AuditEvent = { action: string; entity_type: string; at: string; actor_person_id: string | null }
type ModuleToggle = { key: string; enabled: boolean; config: Record<string, unknown> }
type DataExport = { id: string; requested_at: string; status: string }
type Overview = {
  organization: OrgInfo
  members: Member[]
  consent_counts: Record<string, number>
  module_toggles: ModuleToggle[]
  audit_recent: AuditEvent[]
  data_exports: DataExport[]
}

const DEMO_USERS = [
  { email: 'linnea.strand@fjordtech.test', label: 'Linnea Strand — FjordTech people_ops_admin (org.manage_all)' },
] as const

export function WorkspaceAdminPage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [authBusy, setAuthBusy] = useState(false)
  const [tab, setTab] = useState<'org' | 'users' | 'me' | 'compliance' | 'modules'>('org')
  const [overview, setOverview] = useState<Overview | null>(null)
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState<string | null>(null)
  const [topErr, setTopErr] = useState<string | null>(null)

  // Org-form local state
  const [displayName, setDisplayName] = useState('')
  const [legalName, setLegalName] = useState('')
  const [accentColor, setAccentColor] = useState('#3a4d3f')
  const [logoUrl, setLogoUrl] = useState('')
  const [dpaUrl, setDpaUrl] = useState('')

  // Invite form
  const [inviteEmail, setInviteEmail] = useState('')
  const [inviteName, setInviteName] = useState('')
  const [inviteRole, setInviteRole] = useState('hiring_manager')

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  const load = useCallback(async () => {
    if (!signedIn) return
    setLoading(true); setTopErr(null)
    const { data, error } = await supabase.rpc('admin_overview' as never, { p_org_id: FJORDTECH_ID } as never)
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
  }, [signedIn, supabase])

  useEffect(() => { void load() }, [load])

  const signIn = useCallback(async () => {
    setAuthBusy(true); setTopErr(null)
    const { error } = await supabase.auth.signInWithPassword({ email: DEMO_USERS[0].email, password: 'demo' })
    setAuthBusy(false)
    if (error) setTopErr(`Sign-in failed: ${error.message}`)
  }, [supabase])
  const signOut = useCallback(async () => { await supabase.auth.signOut() }, [supabase])

  const saveOrg = useCallback(async () => {
    setBusy('org'); setTopErr(null)
    const { error } = await supabase.rpc('org_settings_update' as never, {
      p_org_id: FJORDTECH_ID,
      p_display_name: displayName || null,
      p_legal_name: legalName || null,
      p_accent_color: accentColor || null,
      p_logo_url: logoUrl || null,
      p_dpa_url: dpaUrl || null,
    } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, displayName, legalName, accentColor, logoUrl, dpaUrl, load])

  const invite = useCallback(async () => {
    setBusy('invite'); setTopErr(null)
    const { error } = await supabase.rpc('org_invite_user' as never, {
      p_org_id: FJORDTECH_ID, p_email: inviteEmail, p_rbac_role_key: inviteRole, p_full_name: inviteName || null,
    } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    else { setInviteEmail(''); setInviteName('') }
    await load()
  }, [supabase, inviteEmail, inviteRole, inviteName, load])

  const changeRole = useCallback(async (membershipId: string, newRole: string) => {
    setBusy(membershipId); setTopErr(null)
    const { error } = await supabase.rpc('org_change_role' as never, { p_membership_id: membershipId, p_new_rbac_role_key: newRole } as never)
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
    setBusy('export'); setTopErr(null)
    const { error } = await supabase.rpc('data_export_request_create' as never, { p_org_id: FJORDTECH_ID, p_scope: { all: true } } as never)
    setBusy(null)
    if (error) setTopErr(error.message)
    await load()
  }, [supabase, load])

  return (
    <Shell breadcrumb={<span>Workspace admin · <strong>FjordTech</strong></span>} signedInLabel={signedIn ?? undefined}>
      <div className="flex flex-col gap-6">
        <header className="flex items-end justify-between gap-4 flex-wrap">
          <div>
            <h1 className="font-display text-3xl font-bold tracking-tight text-ink">Workspace admin</h1>
            <p className="text-faint mt-1">Org profile, user management, compliance & data — minimum subset to operate.</p>
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
                    <input className="border border-line rounded px-2 py-1 text-sm" value={accentColor} onChange={e => setAccentColor(e.target.value)} />
                  </div>
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">Logo URL</span>
                  <input className="border border-line rounded px-3 py-2 text-sm" value={logoUrl} onChange={e => setLogoUrl(e.target.value)} placeholder="https://…" />
                </label>
                <label className="flex flex-col gap-1 lg:col-span-2">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">DPA / privacy posture URL</span>
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
              <CardTitle>Add someone to FjordTech</CardTitle>
              <CardBody>
                <div className="grid lg:grid-cols-4 gap-3 items-end">
                  <input className="border border-line rounded px-3 py-2 text-sm" placeholder="email@org" value={inviteEmail} onChange={e => setInviteEmail(e.target.value)} />
                  <input className="border border-line rounded px-3 py-2 text-sm" placeholder="Full name (optional)" value={inviteName} onChange={e => setInviteName(e.target.value)} />
                  <select className="border border-line rounded px-3 py-2 text-sm" value={inviteRole} onChange={e => setInviteRole(e.target.value)}>
                    <option value="hiring_manager">hiring_manager</option>
                    <option value="people_ops_admin">people_ops_admin</option>
                    <option value="manager">manager</option>
                    <option value="employee">employee</option>
                    <option value="org_admin">org_admin</option>
                  </select>
                  <Button onClick={invite} disabled={busy === 'invite' || !inviteEmail}>{busy === 'invite' ? <Loader2 size={14} className="animate-spin" /> : null} Invite</Button>
                </div>
              </CardBody>
            </Card>
            <Card>
              <CardEyebrow><Users size={12} /> Members ({overview.members.length})</CardEyebrow>
              <CardTitle>Org membership</CardTitle>
              <CardBody>
                <table className="w-full text-sm">
                  <thead className="text-faint text-xs uppercase tracking-wider">
                    <tr><th className="text-left py-1">Name</th><th className="text-left">Email</th><th className="text-left">Status</th><th className="text-left">Role(s)</th><th></th></tr>
                  </thead>
                  <tbody>
                    {overview.members.map(m => (
                      <tr key={m.membership_id} className="border-t border-line">
                        <td className="py-2">{m.name}</td>
                        <td className="py-2 text-faint">{m.email}</td>
                        <td className="py-2"><Pill>{m.status}</Pill></td>
                        <td className="py-2 flex flex-wrap gap-1">{(m.roles ?? []).map(r => <Pill key={r}>{r}</Pill>)}</td>
                        <td className="py-2">
                          <div className="flex items-center gap-2">
                            <select disabled={busy === m.membership_id} className="border border-line rounded px-2 py-1 text-xs"
                              defaultValue={(m.roles ?? [])[0] ?? 'employee'}
                              onChange={e => changeRole(m.membership_id, e.target.value)}>
                              <option value="hiring_manager">hiring_manager</option>
                              <option value="people_ops_admin">people_ops_admin</option>
                              <option value="manager">manager</option>
                              <option value="employee">employee</option>
                              <option value="org_admin">org_admin</option>
                              <option value="recruiter">recruiter</option>
                            </select>
                            <Button variant="ghost" disabled={busy === m.membership_id || m.status === 'suspended'} onClick={() => deactivate(m.membership_id)}>Deactivate</Button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </CardBody>
            </Card>
          </div>
        )}

        {tab === 'me' && (
          <Card>
            <CardEyebrow><SettingsIcon size={12} /> My profile</CardEyebrow>
            <CardTitle>Display name, email, language</CardTitle>
            <CardBody>
              <p className="text-sm text-faint">Self-profile editing — name, email, language (nb-NO / sv-SE / da-DK / en), notification preferences. Form scaffolded; backend wiring is outside this hardening pass.</p>
              <div className="grid lg:grid-cols-2 gap-3 mt-4">
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">Display name</span>
                  <input className="border border-line rounded px-3 py-2 text-sm" defaultValue={signedIn ?? ''} disabled />
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">Email</span>
                  <input className="border border-line rounded px-3 py-2 text-sm" defaultValue={signedIn ?? ''} disabled />
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">Language</span>
                  <select className="border border-line rounded px-3 py-2 text-sm" defaultValue="nb-NO">
                    <option>nb-NO</option><option>sv-SE</option><option>da-DK</option><option>en</option>
                  </select>
                </label>
              </div>
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
              <CardEyebrow><FileText size={12} /> Audit log (last 50)</CardEyebrow>
              <CardTitle>Recent activity</CardTitle>
              <CardBody>
                <table className="w-full text-xs">
                  <thead className="text-faint uppercase tracking-wider">
                    <tr><th className="text-left py-1">At</th><th className="text-left">Action</th><th className="text-left">Entity</th></tr>
                  </thead>
                  <tbody>
                    {overview.audit_recent.map((e, i) => (
                      <tr key={i} className="border-t border-line">
                        <td className="py-1">{new Date(e.at).toLocaleString()}</td>
                        <td className="py-1">{e.action}</td>
                        <td className="py-1 text-faint">{e.entity_type}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
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
