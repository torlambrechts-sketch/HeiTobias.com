import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { CheckCircle2, FileText, GitMerge, Loader2, Pencil, Send } from 'lucide-react'
import type { RoleProfileRow } from '../../types/roleProfile.js'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { Pill } from '../ui/badges.js'
import { Button } from '../ui/button.js'

// Page header: title, family, version pills, action buttons.
// Actions are RBAC-AND-state-gated:
//   * Export tech doc      — anyone with role read access (handled by Validation card)
//   * Edit (new version)   — requires role.create permission in role's org
//   * Use for requisition  — requires hiring.decide + a picked requisition (deferred to a separate flow; button opens a stub)
//   * Sign off this version — requires role.signoff AND version_status='under_review'

export function PageHeader({ row, onChanged }: { row: RoleProfileRow; onChanged: () => void }) {
  const supabase = browserSupabase()
  const [canEdit, setCanEdit] = useState(false)
  const [canSignoff, setCanSignoff] = useState(false)
  const [busy, setBusy] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)

  const vstatus = row.definition_json.identity_and_governance?.version_status ?? 'draft'
  const validity = row.definition_json.identity_and_governance?.validation_status ?? 'dev_stub'
  const codes = row.definition_json.identity_and_governance?.external_codes

  useEffect(() => {
    if (row.org_id === null) {
      // Templates: editing requires signing in to the relevant org; for now read-only.
      setCanEdit(false); setCanSignoff(false); return
    }
    void (async () => {
      const [edit, signoff] = await Promise.all([
        supabase.rpc('has_permission' as never, { org_id: row.org_id, key: 'role.create' } as never),
        supabase.rpc('has_permission' as never, { org_id: row.org_id, key: 'role.signoff' } as never),
      ])
      setCanEdit(Boolean(edit.data))
      setCanSignoff(Boolean(signoff.data))
    })()
  }, [supabase, row.org_id])

  const signOff = useCallback(async () => {
    const rationale = window.prompt('Rationale for signing off this version (>=20 chars):')
    if (!rationale || rationale.length < 20) return
    setBusy('signoff'); setErr(null)
    const { error } = await supabase.rpc('rpc_role_sign_off' as never, { p_role_id: row.id, p_rationale: rationale } as never)
    setBusy(null)
    if (error) setErr(error.message)
    onChanged()
  }, [supabase, row.id, onChanged])

  return (
    <div className="flex items-end justify-between gap-4 flex-wrap pb-4 border-b border-line">
      <div>
        <h1 className="font-display text-3xl font-bold tracking-tight text-ink">{row.title}</h1>
        <div className="flex items-center gap-2 flex-wrap mt-2">
          {row.family && <Pill>{row.family}</Pill>}
          <Pill>v{row.version}</Pill>
          {row.is_template && <Pill>template</Pill>}
          <Pill>{vstatus}</Pill>
          <Pill>{validity}</Pill>
          {codes?.onet_soc && <span className="text-[10.5px] uppercase tracking-wider font-mono text-faint">O*NET {codes.onet_soc}</span>}
          {codes?.esco && <span className="text-[10.5px] uppercase tracking-wider font-mono text-faint">ESCO {codes.esco}</span>}
        </div>
      </div>
      <div className="flex items-center gap-2 flex-wrap">
        <Button variant="ghost" disabled title="Use for requisition — choose a requisition; coming in CP6 follow-up">
          <Send size={14} /> Use for requisition
        </Button>
        <Link to="/team-def/new" title={canEdit ? 'Start a Delphi-style team-based revision of this role' : 'Requires role.create in this role\'s org'}>
          <Button variant="ghost" disabled={!canEdit}>
            <GitMerge size={14} /> Start team-based revision
          </Button>
        </Link>
        <Button
          variant="ghost"
          disabled={!canEdit}
          title={canEdit ? 'Open a new version draft (stub — full editor is separate)' : 'Requires role.create in this role\'s org'}
        >
          <Pencil size={14} /> Edit (new version)
        </Button>
        <Button
          disabled={!canSignoff || vstatus !== 'under_review' || busy !== null}
          title={
            !canSignoff ? 'Requires role.signoff in this role\'s org'
            : vstatus !== 'under_review' ? `Only roles with version_status=under_review can be signed off (current: ${vstatus})`
            : 'Sign off this version'
          }
          onClick={signOff}
        >
          {busy === 'signoff' ? <Loader2 size={14} className="animate-spin" /> : <CheckCircle2 size={14} />}
          Sign off this version
        </Button>
        <Button variant="ghost" title="Export documents — see the Validation & Defensibility section below">
          <FileText size={14} /> Export ↓
        </Button>
      </div>
      {err && <div className="w-full rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-900">{err}</div>}
    </div>
  )
}
