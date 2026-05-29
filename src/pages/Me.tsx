import { useEffect, useState, useCallback } from 'react'
import { Loader2, LogOut, ShieldAlert } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'

// /me — employee self-view (Phase 3 transparency requirement).
// Shows the same data the user's manager sees about them: profile,
// consent grants (revoke per purpose), recent audit activity.
// Developmental framing throughout — no evaluative gloss anywhere.

type SelfView = {
  person: { id: string; full_name: string; primary_email: string }
  memberships: { org_id: string; org_name: string; status: string }[]
  consents: { purpose: string; granted_to_org_id: string; active: boolean }[]
  recent_activity: { action: string; at: string; actor_person_id: string | null }[]
}

export function MePage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [data, setData]   = useState<SelfView | null>(null)
  const [err, setErr]     = useState<string | null>(null)

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc('rpc_me_self_view' as never)
    if (error) setErr(error.message); else setData(data as unknown as SelfView)
  }, [supabase])

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])
  useEffect(() => { if (signedIn) void load() }, [signedIn, load])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>My profile</span>}>
        <Card><CardBody><p>You must sign in to view your own profile.</p>
          <Button onClick={async () => await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' })}>Sign in (demo)</Button>
        </CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell breadcrumb={<>People · <strong>My profile (self-view)</strong></>} signedInLabel={signedIn}>
      <div className="flex flex-col gap-4">
        <div className="pb-3 border-b border-line">
          <h1 className="font-display text-3xl font-bold tracking-tight">{data?.person?.full_name ?? 'Loading…'}</h1>
          <p className="text-muted text-sm mt-1 max-w-2xl">
            Same data your manager sees about you. Per Phase 3 transparency requirement
            <span className="text-xs font-mono ml-1">(SCIENCE-SPEC §6, §9)</span>.
          </p>
        </div>

        {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust">{err}</div>}
        {!data && !err && <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>}

        {data && (
          <>
            <div className="rounded border border-role border-l-4 border-l-role bg-interview-bg p-4 flex items-start gap-3 text-sm leading-relaxed">
              <ShieldAlert size={15} className="text-role mt-0.5 flex-shrink-0" />
              <div className="text-ink/90">
                <strong>Developmental framing.</strong> Any re-fit or pulse signal you see here is a
                <em> growth conversation input</em>, not a performance verdict. Engagement signals are
                flight-risk / well-being indicators, never performance proxies (SCIENCE-SPEC §6).
              </div>
            </div>

            <Card>
              <CardEyebrow>Account</CardEyebrow>
              <CardTitle>{data.person.full_name}</CardTitle>
              <CardBody>
                <div className="text-sm text-muted">{data.person.primary_email}</div>
                <div className="text-xs font-mono text-faint mt-1">person_id {data.person.id}</div>
              </CardBody>
            </Card>

            <Card data-test="my-memberships">
              <CardEyebrow>My orgs</CardEyebrow>
              <CardTitle>Where I'm active</CardTitle>
              <CardBody>
                <ul className="flex flex-col gap-1.5 text-sm">
                  {data.memberships.map(m => (
                    <li key={m.org_id} className="flex items-center gap-3 border-b border-line pb-2">
                      <strong className="flex-1">{m.org_name}</strong>
                      <Pill tone={m.status === 'active' ? 'open' : 'draft'}>{m.status}</Pill>
                    </li>
                  ))}
                </ul>
              </CardBody>
            </Card>

            <Card data-test="my-consents">
              <CardEyebrow>Active consents</CardEyebrow>
              <CardTitle>What I've granted, per purpose</CardTitle>
              <CardBody>
                {data.consents.length === 0 && <p className="text-faint text-sm">No active consent grants.</p>}
                <ul className="flex flex-col gap-1.5 text-sm">
                  {data.consents.map((c, i) => (
                    <li key={i} className="flex items-center gap-3 border-b border-line pb-2">
                      <Pill tone={c.active ? 'open' : 'reject'}>{c.purpose}</Pill>
                      <span className="flex-1 text-xs text-muted font-mono">org {c.granted_to_org_id?.slice(0,8) ?? '—'}</span>
                      {c.active && (
                        <a href={`/me`} className="text-xs text-rust hover:underline" title="Revoke flow lives in CandidateConsentsPage (/me/<consent_token>) until a lookup-by-purpose helper lands">Revoke…</a>
                      )}
                    </li>
                  ))}
                </ul>
                <p className="text-xs text-faint mt-3">
                  Revoking a consent removes the corresponding data's visibility to the granted org
                  immediately. Previously generated artefacts remain in the audit log per AI Act Art. 12
                  but become non-displayable.
                </p>
              </CardBody>
            </Card>

            <Card data-test="my-activity">
              <CardEyebrow>Recent activity about me</CardEyebrow>
              <CardTitle>Who's looked at / changed my data</CardTitle>
              <CardBody>
                {data.recent_activity.length === 0 && <p className="text-faint text-sm">No recent activity.</p>}
                <table className="w-full text-xs">
                  <thead className="text-faint uppercase tracking-wider"><tr><th className="text-left py-1">At</th><th className="text-left">Action</th><th className="text-left">Actor</th></tr></thead>
                  <tbody>
                    {data.recent_activity.map((a, i) => (
                      <tr key={i} className="border-t border-line">
                        <td className="py-1">{new Date(a.at).toLocaleString()}</td>
                        <td className="py-1 font-mono">{a.action}</td>
                        <td className="py-1 text-faint">{a.actor_person_id?.slice(0,8) ?? 'system'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </CardBody>
            </Card>
          </>
        )}

        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}
