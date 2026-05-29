import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { AlertCircle, CheckCircle2, Info, X } from 'lucide-react'

// Tiny toast system. No new dependency; minimum-viable contract.
//
// What it covers:
//   * `success` / `error` / `info` toasts with an icon + message
//   * auto-dismiss after 5s; user can close earlier
//   * sticks to bottom-right; max 4 concurrent (older ones auto-shift)
//   * role="status" / role="alert" attributes for screen readers
//
// What it does NOT cover (deliberately):
//   * action buttons inside the toast (use a Dialog if you need that)
//   * positioning variants
//   * close-on-click-anywhere
//
// Usage:
//   const toast = useToast()
//   toast.error('Couldn\'t save. Try again.')
//   toast.success('Requisition created.')

type ToastKind = 'success' | 'error' | 'info'
type ToastRow = { id: number; kind: ToastKind; message: string }

interface ToastCtx {
  success: (msg: string) => void
  error:   (msg: string) => void
  info:    (msg: string) => void
}

const Ctx = createContext<ToastCtx | null>(null)

export function ToastProvider({ children }: { children: ReactNode }) {
  const [rows, setRows] = useState<ToastRow[]>([])

  const push = useCallback((kind: ToastKind, message: string) => {
    const id = Date.now() + Math.random()
    setRows(prev => [...prev.slice(-3), { id, kind, message }])
    window.setTimeout(() => {
      setRows(prev => prev.filter(r => r.id !== id))
    }, 5000)
  }, [])

  const api = useMemo<ToastCtx>(() => ({
    success: (m) => push('success', m),
    error:   (m) => push('error', m),
    info:    (m) => push('info', m),
  }), [push])

  return (
    <Ctx.Provider value={api}>
      {children}
      <div
        aria-live="polite"
        aria-relevant="additions"
        className="fixed bottom-4 right-4 z-50 flex flex-col gap-2 max-w-sm"
      >
        {rows.map(r => (
          <ToastRowView key={r.id} row={r} onClose={() => setRows(prev => prev.filter(p => p.id !== r.id))} />
        ))}
      </div>
    </Ctx.Provider>
  )
}

export function useToast(): ToastCtx {
  const ctx = useContext(Ctx)
  if (!ctx) {
    // Fail soft. A page that uses useToast outside the provider gets a
    // no-op rather than a crash. ToastProvider should wrap the app
    // (App.tsx); this guard exists for tests + isolated component
    // rendering.
    return {
      success: () => undefined,
      error:   () => undefined,
      info:    () => undefined,
    }
  }
  return ctx
}

function ToastRowView({ row, onClose }: { row: ToastRow; onClose: () => void }) {
  // The role on each row reflects severity. Screen readers treat
  // role="alert" as assertive; "status" as polite. We use alert for
  // errors (the user should hear them now) and status for the others.
  const role: 'alert' | 'status' = row.kind === 'error' ? 'alert' : 'status'
  const Icon = row.kind === 'success' ? CheckCircle2 : row.kind === 'error' ? AlertCircle : Info
  const tone = row.kind === 'success' ? 'border-green/40 bg-green/10 text-green'
             : row.kind === 'error'   ? 'border-rust/40 bg-reject-bg text-rust'
             :                          'border-line bg-canvas-2 text-ink'

  // Fade-in motion: rely on a class flip rather than a CSS keyframe so
  // we keep the toast system free of stylesheet additions.
  const [shown, setShown] = useState(false)
  useEffect(() => { const id = window.setTimeout(() => setShown(true), 10); return () => window.clearTimeout(id) }, [])

  return (
    <div
      role={role}
      data-test={`toast-${row.kind}`}
      className={
        'rounded-lg border shadow-soft px-3 py-2.5 flex items-start gap-2 transition-all ' +
        tone + ' ' +
        (shown ? 'translate-y-0 opacity-100' : 'translate-y-2 opacity-0')
      }
    >
      <Icon size={16} className="flex-shrink-0 mt-0.5" aria-hidden />
      <p className="flex-1 text-sm leading-snug">{row.message}</p>
      <button type="button" onClick={onClose} aria-label="Dismiss" className="text-current/70 hover:text-current p-0.5 flex-shrink-0">
        <X size={14} />
      </button>
    </div>
  )
}
