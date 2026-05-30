import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Loader2 } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { AuthLayout } from '../../components/public/AuthLayout.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /preferences/notifications/:token — token-keyed email preferences for
// external users (candidates, SMEs, pre-claim employees) who have no
// account. Reads/writes via notif_prefs_by_token / notif_prefs_set_by_token.
// Mandatory (transactional) categories can't be turned off — the page
// says so and explains the alternative (revoke the relationship).

type Cat = { enabled: boolean; mandatory: boolean }
type Categories = Record<string, Cat>

const LABELS: Record<string, { title: string; desc: string }> = {
  consent_confirmations: { title: 'Consent confirmations', desc: 'Receipts when you grant or revoke consent. Transactional.' },
  status_updates: { title: 'Status updates', desc: 'When your application or placement status changes.' },
  reminders: { title: 'Reminders', desc: 'Nudges to complete an assessment or pending step.' },
}

export function NotificationPreferencesPage() {
  usePageTitle('Email preferences')
  const { token } = useParams<{ token: string }>()
  const supabase = browserSupabase()
  const [cats, setCats] = useState<Categories | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)

  const load = useCallback(async () => {
    if (!token) return
    const { data, error } = await supabase.rpc('notif_prefs_by_token' as never, { p_token: token } as never)
    if (error) { setErr(error.message); return }
    const res = data as { ok?: boolean; reason?: string; categories?: Categories }
    if (!res.ok) { setErr(res.reason === 'invalid_token' ? 'This preferences link is not valid.' : 'Could not load preferences.'); return }
    setCats(res.categories ?? {})
  }, [supabase, token])

  useEffect(() => { void load() }, [load])

  const toggle = useCallback(async (kind: string, enabled: boolean) => {
    setNote(null)
    const { data, error } = await supabase.rpc('notif_prefs_set_by_token' as never, {
      p_token: token, p_kind: kind, p_enabled: enabled,
    } as never)
    if (error) { setErr(error.message); return }
    const res = data as { ok?: boolean; reason?: string; message?: string }
    if (!res.ok) { setNote(res.message ?? 'That category cannot be changed.'); return }
    setCats(prev => prev ? { ...prev, [kind]: { ...prev[kind]!, enabled } } : prev)
  }, [supabase, token])

  return (
    <AuthLayout title="Email preferences" subtitle="Choose which emails you receive from HeiTobias.">
      {err && <div className="rounded border border-rust/40 bg-reject-bg p-2 text-xs text-rust mb-3">{err}</div>}
      {note && <div className="rounded border border-amber/40 bg-internal-bg/40 p-2 text-xs text-ink mb-3">{note}</div>}
      {!cats && !err && <div className="text-sm text-muted flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>}
      {cats && (
        <ul className="flex flex-col gap-3">
          {Object.entries(cats).map(([kind, cat]) => {
            const label = LABELS[kind] ?? { title: kind, desc: '' }
            return (
              <li key={kind} className="flex items-start justify-between gap-3 border-b border-line pb-3">
                <div>
                  <p className="font-medium text-sm">{label.title}{cat.mandatory && <span className="text-[10.5px] text-faint ml-2">(required)</span>}</p>
                  <p className="text-xs text-muted mt-0.5">{label.desc}</p>
                </div>
                <label className="flex items-center gap-2 flex-shrink-0">
                  <input
                    type="checkbox"
                    checked={cat.enabled}
                    disabled={cat.mandatory}
                    onChange={e => toggle(kind, e.target.checked)}
                  />
                  <span className="text-xs text-muted">{cat.enabled ? 'On' : 'Off'}</span>
                </label>
              </li>
            )
          })}
        </ul>
      )}
      <p className="text-[11px] text-faint mt-4">
        Transactional emails (like consent confirmations) can't be turned off here — they're part
        of the service. To stop them entirely, revoke the underlying consent or relationship.
      </p>
    </AuthLayout>
  )
}
