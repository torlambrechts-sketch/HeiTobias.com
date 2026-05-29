import { useEffect, useState, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { Briefcase, ChevronRight, Loader2, LogOut, Plus, Copy } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'

// /req — requisitions list (operator-side). Filters: stage. Add-candidate
// flow calls rpc_req_add_candidate which mints a take-token (operator
// copies the magic link until SMTP lands).
type Req = { id: string; status: string; role_id: string; org_id: string; created_at: string }
type Cand = { id: string; person_id: string; full_name: string | null; primary_email: string | null; stage: string }

export function RequisitionsListPage() {
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [reqs, setReqs]   = useState<Req[]>([])
  const [pick, setPick]   = useState<string | null>(null)
  const [cands, setCands] = useState<Cand[]>([])
  const [newCand, setNewCand] = useState({ email: '', name: '', rationale: '' })
  const [recentToken, setRecentToken] = useState<{ token: string; email: string } | null>(null)
  const [err, setErr]     = useState<string | null>(null)
  const [busy, setBusy]   = useState(false)

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  useEffect(() => {
    if (!signedIn) return
    void (async () => {
      const { data } = await supabase.from('requisitions').select('*').order('created_at', { ascending: false }).limit(100)
      setReqs((data ?? []) as Req[])
    })()
  }, [supabase, signedIn])

  const loadCands = useCallback(async (id: string) => {
    setPick(id); setCands([])
    const { data, error } = await supabase.rpc('rpc_req_candidates' as never, { p_requisition_id: id } as never)
    if (error) setErr(error.message); else setCands(((data ?? []) as unknown as Cand[]))
  }, [supabase])

  const addCand = useCallback(async () => {
    if (!pick) return
    setBusy(true); setErr(null); setRecentToken(null)
    const { data, error } = await supabase.rpc('rpc_req_add_candidate' as never, {
      p_requisition_id: pick, p_email: newCand.email, p_full_name: newCand.name || null,
      p_rationale: newCand.rationale,
    } as never)
    setBusy(false)
    if (error) { setErr(error.message); return }
    const r = data as unknown as { take_token: string }
    setRecentToken({ token: r.take_token, email: newCand.email })
    setNewCand({ email: '', name: '', rationale: '' })
    await loadCands(pick)
  }, [supabase, pick, newCand, loadCands])

  const copyTake = useCallback((token: string) => {
    const url = `${window.location.origin}/take/${token}`
    void navigator.clipboard.writeText(url)
  }, [])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>Requisitions</span>}>
        <Card><CardBody><p>You must sign in to view requisitions.</p>
          <Button onClick={async () => await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' })}>Sign in (demo)</Button>
        </CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell breadcrumb={<>Hiring · <strong>Requisitions</strong></>} signedInLabel={signedIn}>
      <div className="flex flex-col gap-4">
        <div className="flex items-end justify-between gap-4 flex-wrap pb-3 border-b border-line">
          <div>
            <h1 className="font-display text-3xl font-bold tracking-tight">Requisitions</h1>
            <p className="text-muted text-sm mt-1 max-w-2xl">Agency + employer requisitions. Click a row to view candidates and add new ones. Take-tokens are operator-emailed until SMTP lands.</p>
          </div>
          <Button disabled title="Create-requisition wizard is in /requisitions infra; for now create via SQL/admin">
            <Plus size={14} /> Create requisition
          </Button>
        </div>

        {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust">{err}</div>}

        <div className="grid lg:grid-cols-[1fr_2fr] gap-4">
          <div className="flex flex-col gap-2">
            {reqs.length === 0 && <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>}
            {reqs.map(r => (
              <button key={r.id} onClick={() => loadCands(r.id)}
                className={'text-left border rounded p-3 transition-colors ' +
                  (pick === r.id ? 'border-forest bg-canvas-2' : 'border-line bg-surface hover:bg-canvas')}>
                <div className="flex items-center gap-2">
                  <Briefcase size={14} className="text-role flex-shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="text-xs font-mono truncate">req #{r.id.slice(0,8)}</div>
                    <div className="text-[11px] text-faint">role {r.role_id.slice(0,8)}…</div>
                  </div>
                  <Pill tone={r.status === 'open' ? 'open' : 'draft'}>{r.status}</Pill>
                  <ChevronRight size={14} className="text-faint" />
                </div>
              </button>
            ))}
          </div>

          <div>
            {!pick && <Card><CardBody><p className="text-faint text-sm">Select a requisition to see its candidates.</p></CardBody></Card>}
            {pick && (
              <Card>
                <CardBody className="flex flex-col gap-4">
                  <div className="flex items-center justify-between">
                    <h2 className="font-display text-xl font-semibold">Candidates</h2>
                    <Link to={`/requisitions/${pick}`} className="text-xs text-role hover:underline">Full requisition page →</Link>
                  </div>

                  {cands.length === 0 && <p className="text-faint text-sm italic">No candidates yet.</p>}
                  <ul className="flex flex-col gap-2 text-sm">
                    {cands.map(c => (
                      <li key={c.id} className="flex items-center gap-3 border-b border-line pb-2">
                        <div className="flex-1 min-w-0"><strong>{c.full_name}</strong> <span className="text-xs text-faint">{c.primary_email}</span></div>
                        <Pill tone={c.stage === 'placed' ? 'open' : c.stage === 'rejected' ? 'reject' : 'draft'}>{c.stage}</Pill>
                      </li>
                    ))}
                  </ul>

                  <div className="border-t border-line pt-3">
                    <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted mb-2">Add candidate</div>
                    <div className="grid lg:grid-cols-2 gap-2">
                      <input className="border border-line rounded px-3 py-2 text-sm" placeholder="email@candidate.test" value={newCand.email}
                        onChange={e => setNewCand({ ...newCand, email: e.target.value })} />
                      <input className="border border-line rounded px-3 py-2 text-sm" placeholder="Full name (optional)" value={newCand.name}
                        onChange={e => setNewCand({ ...newCand, name: e.target.value })} />
                    </div>
                    <textarea className="border border-line rounded px-3 py-2 text-sm w-full mt-2 font-body" rows={3}
                      placeholder="Rationale for adding this candidate (≥20 chars — audit-grade)"
                      value={newCand.rationale} onChange={e => setNewCand({ ...newCand, rationale: e.target.value })} />
                    <div className="flex items-center gap-3 mt-2">
                      <Button disabled={busy || !newCand.email || newCand.rationale.trim().length < 20} onClick={addCand}>
                        {busy ? <Loader2 size={14} className="animate-spin" /> : <Plus size={14} />}
                        Add + mint take-token
                      </Button>
                      <span className="text-xs text-faint">Writes <code className="font-mono">requisition.candidate_added</code> + admin_decision.</span>
                    </div>
                    {recentToken && (
                      <div className="mt-3 rounded border border-line bg-canvas p-3 text-sm flex items-center justify-between gap-3">
                        <span>Take-token for <strong>{recentToken.email}</strong> — copy and email it (SMTP pending operator action).</span>
                        <Button variant="ghost" onClick={() => copyTake(recentToken.token)}><Copy size={14} /> Copy /take URL</Button>
                      </div>
                    )}
                  </div>
                </CardBody>
              </Card>
            )}
          </div>
        </div>

        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}
