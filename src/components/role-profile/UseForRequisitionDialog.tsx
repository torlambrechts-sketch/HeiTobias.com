import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Briefcase, Loader2, Send, X } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import type { RoleProfileRow } from '../../types/roleProfile.js'
import { Button } from '../ui/button.js'
import { Card, CardBody } from '../ui/card.js'
import { Pill } from '../ui/badges.js'

// Use-for-requisition dialog. Triggered from the role profile page
// header. Lists requisitions visible to the caller (RLS scopes to
// org), excludes those already pointing to this exact role (the RPC
// would refuse anyway, but suppressing in the picker is cleaner).
// Confirms with a ≥20-char rationale before calling
// rpc_requisition_attach_role.
//
// CANNOT attach to a template (is_template=true) — the role profile
// header gates the trigger button on canEdit which is per-org and
// templates are global, so the picker won't appear for templates.

const MIN_RATIONALE = 20

type RequisitionRow = {
  id: string
  org_id: string
  role_id: string
  team_id: string | null
  status: string
}

export function UseForRequisitionDialog({
  row,
  onClose,
}: {
  row: RoleProfileRow
  onClose: () => void
}) {
  const supabase = browserSupabase()
  const navigate = useNavigate()
  const [reqs, setReqs]               = useState<RequisitionRow[] | undefined>(undefined)
  const [picked, setPicked]           = useState<RequisitionRow | null>(null)
  const [rationale, setRationale]     = useState('')
  const [busy, setBusy]               = useState(false)
  const [err, setErr]                 = useState<string | null>(null)

  useEffect(() => {
    if (row.org_id === null) {
      // Templates can't be attached; this dialog shouldn't even have been
      // opened, but defensive fallback.
      setReqs([])
      return
    }
    void (async () => {
      const { data, error } = await supabase
        .from('requisitions')
        .select('id, org_id, role_id, team_id, status')
        .order('created_at', { ascending: false })
        .limit(50)
      if (error) setErr(error.message)
      else setReqs((data ?? []) as RequisitionRow[])
    })()
  }, [supabase, row.org_id])

  const valid = rationale.trim().length >= MIN_RATIONALE && picked !== null

  const submit = useCallback(async () => {
    if (!valid || !picked) return
    setBusy(true); setErr(null)
    try {
      const { error } = await supabase.rpc(
        'rpc_requisition_attach_role' as never,
        {
          p_requisition_id: picked.id,
          p_role_id: row.id,
          p_rationale: rationale.trim(),
        } as never,
      )
      if (error) throw new Error(error.message)
      navigate(`/requisitions/${picked.id}`)
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e))
      setBusy(false)
    }
  }, [supabase, picked, row.id, rationale, valid, navigate])

  return (
    <div
      data-test="use-for-requisition-dialog"
      className="fixed inset-0 z-50 bg-ink/40 flex items-start justify-center p-6 overflow-auto"
      onClick={onClose}
    >
      <Card className="w-full max-w-2xl mt-12" onClick={e => e.stopPropagation()}>
        <CardBody className="flex flex-col gap-4">
          <div className="flex items-start justify-between">
            <div>
              <h3 className="font-display text-xl font-semibold">Use this role for a requisition</h3>
              <p className="text-muted text-sm mt-1 max-w-md">
                Pick a requisition to attach <strong>{row.title}</strong> v{row.version} to.
                Switches the requisition's <code className="font-mono text-xs">role_id</code> +
                writes a {' '}<code className="font-mono text-xs">requisition.role_attached</code>{' '}
                audit row carrying the previous role + your rationale.
              </p>
            </div>
            <Button variant="ghost" onClick={onClose} aria-label="Close"><X size={14} /></Button>
          </div>

          {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust">{err}</div>}

          {/* Requisition picker */}
          <div>
            <div className="text-[10.5px] uppercase tracking-wider font-bold text-muted mb-2">Requisitions you can edit</div>
            {reqs === undefined && (
              <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>
            )}
            {reqs && reqs.length === 0 && (
              <div className="text-faint text-sm italic border border-dashed border-line rounded p-4 text-center">
                No requisitions visible. You need <code className="font-mono">requisition.write</code> in this org
                to attach a role.
              </div>
            )}
            {reqs && reqs.length > 0 && (
              <div className="flex flex-col gap-1.5 max-h-64 overflow-auto pr-1">
                {reqs.map(r => {
                  const same = r.role_id === row.id
                  const isPicked = picked?.id === r.id
                  return (
                    <button
                      key={r.id}
                      type="button"
                      disabled={same}
                      onClick={() => setPicked(r)}
                      className={'text-left border rounded px-3 py-2 flex items-center gap-3 ' +
                        (same        ? 'border-line bg-canvas opacity-50 cursor-not-allowed' :
                         isPicked    ? 'border-forest bg-canvas-2' :
                                       'border-line bg-surface hover:bg-canvas')}
                    >
                      <Briefcase size={15} className="text-role flex-shrink-0" />
                      <div className="flex-1 min-w-0">
                        <div className="text-sm font-semibold font-mono truncate">req #{r.id.slice(0, 8)}</div>
                        <div className="text-xs text-muted">role_id {r.role_id.slice(0, 8)}…</div>
                      </div>
                      <Pill tone={r.status === 'open' ? 'open' : 'draft'}>{r.status}</Pill>
                      {same && <span className="text-[10.5px] uppercase tracking-wider font-bold text-faint">already attached</span>}
                    </button>
                  )
                })}
              </div>
            )}
          </div>

          {/* Rationale */}
          <label className="flex flex-col gap-1.5">
            <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">
              Rationale <span className="text-faint normal-case font-normal">(audit-grade — ≥{MIN_RATIONALE} chars; 200-char excerpt stored)</span>
            </span>
            <textarea
              value={rationale}
              onChange={e => setRationale(e.target.value)}
              rows={3}
              placeholder="Why is this role version the right fit for this requisition?"
              className="border border-line rounded px-3 py-2 bg-surface text-sm font-body"
            />
            <span className={'text-xs font-mono ' + (rationale.trim().length >= MIN_RATIONALE ? 'text-green' : 'text-faint')}>
              {rationale.trim().length} / {MIN_RATIONALE}
            </span>
          </label>

          <div className="flex items-center gap-3 border-t border-line pt-3">
            <Button onClick={submit} disabled={!valid || busy}>
              {busy ? <Loader2 size={14} className="animate-spin" /> : <Send size={14} />}
              Attach &amp; open requisition
            </Button>
            <Button variant="ghost" onClick={onClose} disabled={busy}>Cancel</Button>
          </div>
        </CardBody>
      </Card>
    </div>
  )
}
