import { useCallback, useEffect, useRef, useState } from 'react'
import { Bell, Check, Loader2, X } from 'lucide-react'
import { Link } from 'react-router-dom'
import { browserSupabase } from '../lib/browser-supabase.js'

// In-app notification bell.
//
// Reads via two RPCs:
//   * notifications_unread_count_for_me() — light, called on mount +
//     when the panel opens; this is the only background poll.
//   * notifications_recent_for_me(limit, offset) — heavier, called
//     when the panel opens.
//
// We deliberately do not subscribe to realtime updates here — the
// product does not have a websocket-driven UX yet, and polling every
// 60s + on panel-open is enough for the current product shape.
//
// payload_json convention: if a notification has a `link` field, the
// list item is a real anchor that navigates there. Without `link`, the
// item is a passive notice (read-only).

type Row = {
  id: string
  org_id: string
  subject: string
  body: string
  payload_json: { link?: string; kind?: string } | null
  created_at: string
  read_at: string | null
  seen_at: string | null
}

const POLL_MS = 60_000

export function NotificationBell() {
  const supabase = browserSupabase()
  const [unread, setUnread] = useState<number>(0)
  const [open, setOpen] = useState(false)
  const [rows, setRows] = useState<Row[] | null>(null)
  const [busyMarkAll, setBusyMarkAll] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)

  const refreshCount = useCallback(async () => {
    const { data, error } = await supabase.rpc('notifications_unread_count_for_me' as never)
    if (error) return
    setUnread(typeof data === 'number' ? data : 0)
  }, [supabase])

  const loadRows = useCallback(async () => {
    setRows(null)
    const { data, error } = await supabase.rpc(
      'notifications_recent_for_me' as never,
      { p_limit: 30, p_offset: 0 } as never,
    )
    if (error) { setRows([]); return }
    setRows((data ?? []) as unknown as Row[])
  }, [supabase])

  useEffect(() => {
    void refreshCount()
    const t = setInterval(() => { void refreshCount() }, POLL_MS)
    return () => clearInterval(t)
  }, [refreshCount])

  // Close the panel when the user clicks outside it. We keep the
  // markup mounted (rather than unmounting) so the open/close motion
  // does not flash; the panel is just `hidden` when !open.
  useEffect(() => {
    if (!open) return
    const onDoc = (e: MouseEvent) => {
      if (!containerRef.current) return
      if (!containerRef.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [open])

  const onOpen = useCallback(() => {
    setOpen(true)
    void loadRows()
  }, [loadRows])

  const onMark = useCallback(async (id: string) => {
    const { error } = await supabase.rpc('notifications_mark_read' as never, { p_id: id } as never)
    if (error) return
    setRows(prev => prev?.map(r => r.id === id ? { ...r, read_at: new Date().toISOString() } : r) ?? null)
    void refreshCount()
  }, [supabase, refreshCount])

  const onMarkAll = useCallback(async () => {
    setBusyMarkAll(true)
    const { error } = await supabase.rpc('notifications_mark_all_read_for_me' as never)
    setBusyMarkAll(false)
    if (error) return
    setRows(prev => prev?.map(r => ({ ...r, read_at: r.read_at ?? new Date().toISOString() })) ?? null)
    setUnread(0)
  }, [supabase])

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        aria-label={`Notifications${unread > 0 ? ` (${unread} unread)` : ''}`}
        onClick={() => (open ? setOpen(false) : onOpen())}
        className="relative flex items-center justify-center w-8 h-8 rounded hover:bg-canvas-2 transition-colors"
      >
        <Bell size={18} className={unread > 0 ? 'text-forest' : 'text-muted'} />
        {unread > 0 && (
          <span
            data-test="notification-bell-badge"
            className="absolute -top-0.5 -right-0.5 min-w-[16px] h-4 px-1 rounded-full bg-rust text-white text-[10px] font-bold flex items-center justify-center"
          >
            {unread > 9 ? '9+' : unread}
          </span>
        )}
      </button>

      {open && (
        <div
          className="absolute right-0 mt-2 w-[360px] max-h-[480px] overflow-hidden bg-surface border border-line rounded-lg shadow-hard z-50 flex flex-col"
          data-test="notification-panel"
        >
          <div className="px-4 py-3 border-b border-line flex items-center justify-between gap-3">
            <div>
              <p className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Notifications</p>
              <p className="text-sm font-semibold mt-0.5">
                {unread > 0 ? `${unread} unread` : 'All caught up'}
              </p>
            </div>
            <div className="flex items-center gap-1">
              {unread > 0 && (
                <button
                  type="button"
                  onClick={onMarkAll}
                  disabled={busyMarkAll}
                  className="text-xs text-role hover:underline disabled:opacity-50 flex items-center gap-1"
                >
                  {busyMarkAll ? <Loader2 size={12} className="animate-spin" /> : <Check size={12} />}
                  Mark all read
                </button>
              )}
              <button
                type="button"
                onClick={() => setOpen(false)}
                aria-label="Close notifications"
                className="text-muted hover:text-ink p-1"
              >
                <X size={14} />
              </button>
            </div>
          </div>

          <div className="overflow-y-auto flex-1">
            {rows === null && (
              <div className="px-4 py-8 text-center text-faint text-sm flex items-center justify-center gap-2">
                <Loader2 size={14} className="animate-spin" /> Loading…
              </div>
            )}
            {rows?.length === 0 && (
              <div className="px-4 py-10 text-center">
                <Bell size={20} className="mx-auto text-faint mb-2" />
                <p className="text-sm text-muted">No notifications yet.</p>
                <p className="text-xs text-faint mt-1 max-w-[260px] mx-auto">
                  Updates about your hires, your team, and your consent grants will appear
                  here when they happen.
                </p>
              </div>
            )}
            {rows && rows.map(r => (
              <NotificationItem key={r.id} row={r} onMark={() => onMark(r.id)} />
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function NotificationItem({ row, onMark }: { row: Row; onMark: () => void }) {
  const link = row.payload_json?.link ?? null
  const unread = !row.read_at
  const inner = (
    <div className={'px-4 py-3 border-b border-line text-sm flex gap-3 ' + (unread ? 'bg-canvas-2' : 'bg-surface')}>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className={'font-semibold ' + (unread ? 'text-ink' : 'text-muted')}>{row.subject}</span>
          {unread && <span className="inline-block w-1.5 h-1.5 rounded-full bg-rust" aria-hidden />}
        </div>
        <p className="text-xs text-muted mt-0.5 line-clamp-2">{row.body}</p>
        <p className="text-[10.5px] text-faint mt-1">{new Date(row.created_at).toLocaleString()}</p>
      </div>
      {unread && (
        <button
          type="button"
          onClick={(e) => { e.preventDefault(); onMark() }}
          className="text-[10.5px] text-faint hover:text-ink"
          aria-label="Mark as read"
        >
          <Check size={14} />
        </button>
      )}
    </div>
  )
  if (link) {
    return (
      <Link to={link} onClick={() => { if (unread) onMark() }}>
        {inner}
      </Link>
    )
  }
  return inner
}
