import { useCallback, useEffect, useState } from 'react'
import { Copy, Link2, Loader2, Plus, X } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from './ui/button.js'
import { Pill } from './ui/badges.js'
import { useToast } from './ui/Toast.js'

// ShareManager — create / list / revoke public share tokens for a role
// profile or placement report. Drops into a detail page. Mirrors the
// share_token_create / share_tokens_for_entity / share_token_revoke RPCs.

type Row = {
  id: string
  token: string
  created_at: string
  expires_at: string
  revoked_at: string | null
  access_count: number
}

export function ShareManager({
  entityKind,
  entityId,
  publicPathPrefix,
}: {
  entityKind: 'role_profile' | 'placement_report'
  entityId: string
  publicPathPrefix: string   // e.g. '/public/role' or '/public/placement-report'
}) {
  const supabase = browserSupabase()
  const toast = useToast()
  const [rows, setRows] = useState<Row[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [expiryDays, setExpiryDays] = useState(30)

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc('share_tokens_for_entity' as never, {
      p_entity_kind: entityKind, p_entity_id: entityId,
    } as never)
    if (error) { setRows([]); return }
    setRows(((data ?? []) as unknown as Row[]))
  }, [supabase, entityKind, entityId])

  useEffect(() => { void load() }, [load])

  const create = useCallback(async () => {
    setBusy(true)
    const { data, error } = await supabase.rpc('share_token_create' as never, {
      p_entity_kind: entityKind, p_entity_id: entityId, p_expiry_days: expiryDays,
    } as never)
    setBusy(false)
    if (error) { toast.error(`Could not create link: ${error.message}`); return }
    const res = data as { ok?: boolean; token?: string }
    if (res.ok && res.token) {
      const url = `${window.location.origin}${publicPathPrefix}/${res.token}`
      void navigator.clipboard.writeText(url).then(() => undefined, () => undefined)
      toast.success('Share link created and copied to clipboard.')
    }
    await load()
  }, [supabase, toast, entityKind, entityId, expiryDays, publicPathPrefix, load])

  const revoke = useCallback(async (id: string) => {
    const { error } = await supabase.rpc('share_token_revoke' as never, { p_id: id } as never)
    if (error) { toast.error(`Could not revoke: ${error.message}`); return }
    toast.success('Share link revoked.')
    await load()
  }, [supabase, toast, load])

  const copy = useCallback((token: string) => {
    const url = `${window.location.origin}${publicPathPrefix}/${token}`
    void navigator.clipboard.writeText(url)
    toast.success('Link copied.')
  }, [publicPathPrefix, toast])

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-3 flex-wrap">
        <label className="flex items-center gap-2 text-sm">
          <span className="text-muted text-xs">Expires in</span>
          <select value={expiryDays} onChange={e => setExpiryDays(Number(e.target.value))} className="border border-line rounded px-2 py-1 text-sm bg-surface">
            <option value={7}>7 days</option>
            <option value={30}>30 days</option>
            <option value={60}>60 days</option>
            <option value={90}>90 days</option>
          </select>
        </label>
        <Button onClick={create} disabled={busy}>
          {busy ? <Loader2 size={14} className="animate-spin" /> : <Plus size={14} />} Create share link
        </Button>
      </div>

      {rows === null && <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>}
      {rows?.length === 0 && <p className="text-sm text-faint">No share links yet. Create one above to share this {entityKind.replace('_', ' ')} with someone outside the platform.</p>}

      {rows && rows.length > 0 && (
        <ul className="flex flex-col gap-2">
          {rows.map(r => {
            const expired = new Date(r.expires_at) < new Date()
            const revoked = r.revoked_at != null
            const active = !expired && !revoked
            return (
              <li key={r.id} className="flex items-center gap-3 border border-line rounded p-2.5 text-sm">
                <Link2 size={14} className="text-muted flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <div className="font-mono text-xs truncate">…{r.token.slice(-12)}</div>
                  <div className="text-[11px] text-faint">
                    {active ? `expires ${new Date(r.expires_at).toLocaleDateString()}` : revoked ? 'revoked' : 'expired'}
                    {' · '}{r.access_count} view{r.access_count === 1 ? '' : 's'}
                  </div>
                </div>
                <Pill tone={active ? 'open' : 'reject'}>{active ? 'active' : revoked ? 'revoked' : 'expired'}</Pill>
                {active && (
                  <>
                    <Button variant="ghost" onClick={() => copy(r.token)} className="text-xs"><Copy size={13} /> Copy</Button>
                    <Button variant="ghost" onClick={() => revoke(r.id)} className="text-xs text-rust"><X size={13} /> Revoke</Button>
                  </>
                )}
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
