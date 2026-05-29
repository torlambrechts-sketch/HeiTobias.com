import { useEffect, useState, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { Briefcase, ChevronRight, Loader2, LogOut, Plus, Copy, X } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { useCurrentOrgId } from '../lib/currentOrg.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'

// /req — requisitions list (operator-side). Filters: stage. Add-candidate
// flow calls rpc_req_add_candidate which mints a take-token (operator
// copies the magic link until SMTP lands).
type Req = { id: string; status: string; role_id: string; org_id: string; created_at: string }
type Cand = { id: string; person_id: string; full_name: string | null; primary_email: string | null; stage: string }
type SessionSummary = {
  requisition_candidate_id: string
  session_present: boolean
  demo_mode?: boolean
  status?: string
  sections?: Record<string, { complete: boolean; total_items?: number; answered_items?: number }>
  structured_prep_responses?: number
  dev_stub_label?: string
}

export function RequisitionsListPage() {
  const supabase = browserSupabase()
  const orgState = useCurrentOrgId()
  const orgId = orgState.state === 'ready' ? orgState.orgId : null
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [reqs, setReqs]   = useState<Req[]>([])
  const [pick, setPick]   = useState<string | null>(null)
  const [cands, setCands] = useState<Cand[]>([])
  const [summaries, setSummaries] = useState<Record<string, SessionSummary>>({})
  const [newCand, setNewCand] = useState({ email: '', name: '', rationale: '' })
  const [recentToken, setRecentToken] = useState<{ token: string; email: string } | null>(null)
  const [err, setErr]     = useState<string | null>(null)
  const [busy, setBusy]   = useState(false)
  const [showCreate, setShowCreate] = useState(false)

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
    setPick(id); setCands([]); setSummaries({})
    const { data, error } = await supabase.rpc('rpc_req_candidates' as never, { p_requisition_id: id } as never)
    if (error) { setErr(error.message); return }
    const rows = (data ?? []) as unknown as Cand[]
    setCands(rows)
    // Fan-out session summaries (cheap RPC; small N)
    const map: Record<string, SessionSummary> = {}
    await Promise.all(rows.map(async c => {
      const { data: s } = await supabase.rpc('rpc_candidate_session_summary' as never, { p_rc_id: c.id } as never)
      if (s) map[c.id] = s as unknown as SessionSummary
    }))
    setSummaries(map)
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

  const reloadReqs = useCallback(async () => {
    const { data } = await supabase.from('requisitions').select('*').order('created_at', { ascending: false }).limit(100)
    setReqs((data ?? []) as Req[])
  }, [supabase])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>Requisitions</span>}>
        <Card><CardBody><p>You must sign in to view requisitions.</p>
          <Button onClick={async () => import.meta.env.DEV && (await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' }))}>Sign in (demo)</Button>
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
          <Button onClick={() => setShowCreate(true)} disabled={!orgId}>
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
                    {cands.map(c => {
                      const sum = summaries[c.id]
                      return (
                        <li key={c.id} className="flex flex-col gap-1.5 border-b border-line pb-2">
                          <div className="flex items-center gap-3">
                            <div className="flex-1 min-w-0">
                              <strong>{c.full_name}</strong> <span className="text-xs text-faint">{c.primary_email}</span>
                            </div>
                            <Pill tone={c.stage === 'placed' ? 'open' : c.stage === 'rejected' ? 'reject' : 'draft'}>{c.stage}</Pill>
                          </div>
                          {sum?.session_present && (
                            <div data-test="session-summary" className="flex items-center gap-2 flex-wrap pl-1">
                              {sum.demo_mode && <Pill tone="reject" data-test="demo-flag">⚠ DEMO MODE</Pill>}
                              <Pill tone={sum.status === 'completed' ? 'open' : 'internal'}>{sum.status}</Pill>
                              {sum.sections && Object.entries(sum.sections).map(([k, s]) => (
                                <span key={k} className="text-[11px] font-mono text-muted">
                                  {k.replace('structured_prep','prep').replace('personality','pers')}{' '}
                                  <span className={s.complete ? 'text-green' : 'text-faint'}>{s.answered_items ?? 0}/{s.total_items ?? '?'}</span>
                                </span>
                              ))}
                              <Pill tone="reject">dev_stub</Pill>
                            </div>
                          )}
                        </li>
                      )
                    })}
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

        {showCreate && orgId && (
          <CreateRequisitionDialog
            orgId={orgId}
            onClose={() => setShowCreate(false)}
            onCreated={async () => { setShowCreate(false); await reloadReqs() }}
          />
        )}
      </div>
    </Shell>
  )
}

// CreateRequisitionDialog — the minimal wizard.
//
// What it actually does: lists the caller's roles_catalog rows (visible
// under RLS — `roles_catalog` SELECT policy uses `role.read`), lets
// them pick one, optionally pick a collaborating org (for agency hands-
// off), captures a rationale, and INSERTs the requisition. The RLS
// INSERT policy enforces `requisition.write`; if the caller lacks the
// permission, the dialog surfaces the supabase-returned error verbatim.
//
// Out of scope here: title, headcount, comp range, target_start, etc.
// The current `requisitions` schema doesn't carry those fields — those
// land alongside a richer schema in a future migration. For now the
// requisition rides on top of the role profile (where the role title
// + competencies + targets already live), which matches how the rest
// of the system reads it (the recruiter page joins requisitions →
// roles_catalog for everything role-shaped).
function CreateRequisitionDialog({
  orgId,
  onClose,
  onCreated,
}: {
  orgId: string
  onClose: () => void
  onCreated: () => void | Promise<void>
}) {
  const supabase = browserSupabase()
  const [roles, setRoles] = useState<Array<{ id: string; title: string; version: number; family: string | null }>>([])
  const [collabOrgs, setCollabOrgs] = useState<Array<{ id: string; name: string; type: string }>>([])
  const [roleId, setRoleId] = useState<string>('')
  const [collabOrgId, setCollabOrgId] = useState<string>('')
  const [rationale, setRationale] = useState<string>('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    void (async () => {
      // Non-template roles in the caller's org. RLS scopes naturally.
      const { data: r } = await supabase
        .from('roles_catalog')
        .select('id, title, version, family')
        .eq('org_id', orgId)
        .eq('is_template', false)
        .order('updated_at', { ascending: false })
        .limit(100)
      setRoles((r ?? []) as Array<{ id: string; title: string; version: number; family: string | null }>)
      // Possible collaborating orgs: any org the caller can see other than their own.
      const { data: o } = await supabase
        .from('organizations')
        .select('id, name, type')
        .neq('id', orgId)
        .order('name', { ascending: true })
        .limit(50)
      setCollabOrgs((o ?? []) as Array<{ id: string; name: string; type: string }>)
    })()
  }, [supabase, orgId])

  const submit = useCallback(async () => {
    setError(null)
    if (!roleId) { setError('Pick a role.'); return }
    if (rationale.trim().length < 20) { setError('Rationale ≥ 20 chars (audit-grade).'); return }
    setSubmitting(true)
    const { data, error } = await supabase
      .from('requisitions')
      .insert({
        org_id: orgId,
        role_id: roleId,
        collaborating_org_id: collabOrgId || null,
        status: 'open',
      })
      .select('id')
      .single()
    if (error) {
      setSubmitting(false)
      setError(error.message)
      return
    }
    // Mirror the rationale into admin_decisions so the create is
    // queryable from the audit explorer. The audit_log trigger on
    // requisitions already captures the row insert itself.
    await supabase.from('admin_decisions' as never).insert({
      org_id: orgId,
      kind: 'requisition.create',
      target_entity_type: 'requisitions',
      target_entity_id: (data as { id: string }).id,
      rationale,
    } as never).then(() => undefined, () => undefined)
    setSubmitting(false)
    await onCreated()
  }, [supabase, orgId, roleId, collabOrgId, rationale, onCreated])

  return (
    <div className="fixed inset-0 z-50 bg-ink/40 backdrop-blur-sm flex items-center justify-center p-4" onClick={onClose}>
      <Card className="w-full max-w-lg" onClick={(e) => e.stopPropagation()}>
        <CardBody className="flex flex-col gap-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Create requisition</p>
              <h2 className="font-display text-xl font-semibold mt-0.5">New hiring intent</h2>
              <p className="text-xs text-muted mt-1 max-w-prose">
                Anchored on a signed-off role version. Optional collaborating org for
                agency / employer hand-off. Writes <code className="font-mono">requisitions</code>{' '}
                + audit_log + admin_decisions.
              </p>
            </div>
            <Button variant="ghost" onClick={onClose}><X size={14} /></Button>
          </div>

          {roles.length === 0 ? (
            <div className="rounded border border-line bg-canvas p-3 text-sm text-muted">
              No non-template roles visible at your RLS scope. Create a role first via the Role
              Library (or the Team-based Role Definition workflow) before opening a requisition.
            </div>
          ) : (
            <>
              <label className="flex flex-col gap-1">
                <span className="text-xs text-muted">Role profile</span>
                <select
                  className="border border-line rounded px-3 py-2 text-sm bg-surface"
                  value={roleId}
                  onChange={(e) => setRoleId(e.target.value)}
                >
                  <option value="">— pick a role —</option>
                  {roles.map(r => (
                    <option key={r.id} value={r.id}>{r.title} (v{r.version}{r.family ? `, ${r.family}` : ''})</option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-xs text-muted">Collaborating org (optional)</span>
                <select
                  className="border border-line rounded px-3 py-2 text-sm bg-surface"
                  value={collabOrgId}
                  onChange={(e) => setCollabOrgId(e.target.value)}
                >
                  <option value="">— none —</option>
                  {collabOrgs.map(o => (
                    <option key={o.id} value={o.id}>{o.name} ({o.type})</option>
                  ))}
                </select>
                <span className="text-[11px] text-faint">
                  Pair an agency with the employer-side role owner, or vice versa. Both
                  sides see the requisition under their respective <code>requisition.read</code>.
                </span>
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-xs text-muted">Rationale (≥ 20 chars)</span>
                <textarea
                  className="border border-line rounded px-3 py-2 text-sm font-body"
                  rows={3}
                  value={rationale}
                  onChange={(e) => setRationale(e.target.value)}
                  placeholder="e.g. Replacing the engineering-lead seat after Anna's transfer; expected start Q3."
                />
              </label>
              {error && <div className="rounded border border-rust/40 bg-reject-bg p-2 text-xs text-rust">{error}</div>}
              <div className="flex items-center justify-end gap-2 pt-2 border-t border-line">
                <Button variant="ghost" onClick={onClose} disabled={submitting}>Cancel</Button>
                <Button
                  onClick={submit}
                  disabled={submitting || !roleId || rationale.trim().length < 20}
                >
                  {submitting ? <Loader2 size={14} className="animate-spin" /> : <Plus size={14} />}
                  Create requisition
                </Button>
              </div>
            </>
          )}
        </CardBody>
      </Card>
    </div>
  )
}
