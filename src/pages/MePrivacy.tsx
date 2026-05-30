import { useCallback, useEffect, useState } from 'react'
import { Download, Loader2, LogOut, Shield, Trash2 } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { usePageTitle } from '../lib/usePageTitle.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { EmptyState } from '../components/ui/EmptyState.js'
import { useToast } from '../components/ui/Toast.js'

// /me/privacy — authenticated data-subject self-service (GDPR Art. 15/17).
//
// Extends the /me self-view with the data-rights surface:
//   * Download my data — calls dsr_export_my_data() and offers the JSON
//     as a file download.
//   * Request deletion — opens a DSR (kind=erase) via dsr_open(); the
//     operator fulfils it (soft delete + audit retention).
//   * View active consents (with revoke link to the existing flow).
//   * View orgs the user has data in.

type Consent = { purpose: string; granted_to_org_id: string | null; active: boolean }
type SelfView = {
  consents?: Consent[]
  memberships?: Array<{ org_id: string; org_name: string | null; status: string }>
}

export function MePrivacyPage() {
  usePageTitle('My data & privacy')
  const supabase = browserSupabase()
  const toast = useToast()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [consents, setConsents] = useState<Consent[] | null>(null)
  const [orgs, setOrgs] = useState<Array<{ org_id: string; org_name: string | null }>>([])
  const [busy, setBusy] = useState<string | null>(null)
  const [showDelete, setShowDelete] = useState(false)
  const [deleteReason, setDeleteReason] = useState('')

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  const load = useCallback(async () => {
    if (!signedIn) return
    const { data, error } = await supabase.rpc('rpc_me_self_view' as never)
    if (error) { setConsents([]); return }
    const sv = data as unknown as SelfView | null
    setConsents(sv?.consents ?? [])
    setOrgs((sv?.memberships ?? []).map(m => ({ org_id: m.org_id, org_name: m.org_name })))
  }, [supabase, signedIn])

  useEffect(() => { void load() }, [load])

  const downloadData = useCallback(async () => {
    setBusy('export')
    const { data, error } = await supabase.rpc('dsr_export_my_data' as never)
    setBusy(null)
    if (error) { toast.error(`Export failed: ${error.message}`); return }
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'my-heitobias-data.json'
    a.click()
    URL.revokeObjectURL(url)
    toast.success('Your data export has been downloaded.')
  }, [supabase, toast])

  const requestDeletion = useCallback(async () => {
    if (deleteReason.trim().length < 10) { toast.error('Please give a brief reason (≥10 chars).'); return }
    setBusy('delete')
    const { error } = await supabase.rpc('dsr_open' as never, { p_kind: 'erase', p_org_id: null } as never)
    setBusy(null)
    if (error) { toast.error(`Could not submit: ${error.message}`); return }
    setShowDelete(false); setDeleteReason('')
    toast.success('Deletion request submitted. The operator will process it within 30 days.')
  }, [supabase, toast, deleteReason])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>My data & privacy</span>}>
        <Card><CardBody><p className="text-sm">Sign in to manage your data and privacy.</p></CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell breadcrumb={<>My profile · <strong>Data & privacy</strong></>} signedInLabel={signedIn}>
      <div className="flex flex-col gap-4 max-w-3xl">
        <div>
          <h1 className="font-display text-3xl font-bold tracking-tight">Your data & privacy</h1>
          <p className="text-muted text-sm mt-1">
            Exercise your data rights. Everything here is logged to the audit trail you can also see.
          </p>
        </div>

        <Card>
          <CardEyebrow><Download size={12} /> Right of access</CardEyebrow>
          <CardTitle>Download my data</CardTitle>
          <CardBody className="flex flex-col gap-3">
            <p className="text-sm text-muted">
              Get a structured JSON archive of all personal data the platform holds about you
              (GDPR Art. 15).
            </p>
            <div>
              <Button onClick={downloadData} disabled={busy === 'export'}>
                {busy === 'export' ? <Loader2 size={14} className="animate-spin" /> : <Download size={14} />}
                Download my data (JSON)
              </Button>
            </div>
          </CardBody>
        </Card>

        <Card>
          <CardEyebrow><Trash2 size={12} /> Right to erasure</CardEyebrow>
          <CardTitle>Request deletion</CardTitle>
          <CardBody className="flex flex-col gap-3">
            <p className="text-sm text-muted">
              Request erasure of your data (GDPR Art. 17). Note: some records (consent ledger,
              audit log) are retained for up to 7 years to demonstrate legal compliance, and an
              active placement may delay erasure until it concludes. The operator confirms the
              scope and processes within 30 days.
            </p>
            {!showDelete ? (
              <div><Button variant="ghost" onClick={() => setShowDelete(true)}><Trash2 size={14} /> Request deletion…</Button></div>
            ) : (
              <div className="flex flex-col gap-2 border border-line rounded p-3">
                <label className="flex flex-col gap-1">
                  <span className="text-xs text-muted">Reason (helps us process correctly, ≥10 chars)</span>
                  <textarea
                    className="border border-line rounded px-3 py-2 text-sm font-body"
                    rows={2}
                    value={deleteReason}
                    onChange={e => setDeleteReason(e.target.value)}
                  />
                </label>
                <div className="flex gap-2 justify-end">
                  <Button variant="ghost" onClick={() => setShowDelete(false)}>Cancel</Button>
                  <Button onClick={requestDeletion} disabled={busy === 'delete'}>
                    {busy === 'delete' ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
                    Submit deletion request
                  </Button>
                </div>
              </div>
            )}
          </CardBody>
        </Card>

        <Card>
          <CardEyebrow><Shield size={12} /> Consents</CardEyebrow>
          <CardTitle>Who can see your data</CardTitle>
          <CardBody>
            {consents === null && <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>}
            {consents?.length === 0 && (
              <EmptyState icon={Shield} title="No active consents" body="You haven't granted anyone access to your data." />
            )}
            {consents && consents.length > 0 && (
              <ul className="flex flex-col gap-1.5 text-sm">
                {consents.map((c, i) => (
                  <li key={`${c.purpose}-${c.granted_to_org_id ?? i}`} className="flex items-center gap-3 border-b border-line pb-2">
                    <Pill tone={c.active ? 'open' : 'reject'}>{c.purpose}</Pill>
                    <span className="flex-1 text-xs text-faint font-mono">org {c.granted_to_org_id?.slice(0, 8) ?? '—'}</span>
                  </li>
                ))}
              </ul>
            )}
            <p className="text-xs text-faint mt-3">
              To revoke a specific consent, use your consent dashboard. Revocation removes the
              corresponding data's visibility immediately.
            </p>
          </CardBody>
        </Card>

        {orgs.length > 0 && (
          <Card>
            <CardEyebrow>Organisations</CardEyebrow>
            <CardTitle>Where your data lives</CardTitle>
            <CardBody>
              <ul className="text-sm flex flex-col gap-1">
                {orgs.map(o => (
                  <li key={o.org_id} className="flex justify-between border-b border-line py-1">
                    <span>{o.org_name ?? o.org_id.slice(0, 8)}</span>
                  </li>
                ))}
              </ul>
            </CardBody>
          </Card>
        )}

        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}
