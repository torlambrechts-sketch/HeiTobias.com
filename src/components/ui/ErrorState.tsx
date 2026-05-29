import { AlertCircle, RefreshCw } from 'lucide-react'
import { type ReactNode } from 'react'
import { Button } from './button.js'

// ErrorState — the counterpart of EmptyState for async failures.
//
// One contract for every "the load failed" panel in the app:
//   * a clear headline ("Couldn't load requisitions")
//   * the underlying message from Supabase / RLS / network as the
//     small print — never invent friendlier text that hides what
//     actually broke
//   * a retry button when the operation is idempotent
//
// This is deliberately not an ErrorBoundary — those catch render
// crashes. ErrorState is for the more common case where the data
// fetch returned an error and we need to show something other than
// the previous (stale) data or a blank.

export function ErrorState({
  title = 'Something went wrong',
  message,
  onRetry,
  detail,
  className,
}: {
  title?: string
  message?: string | null
  onRetry?: () => void
  detail?: ReactNode
  className?: string
}) {
  return (
    <div
      data-test="error-state"
      role="alert"
      className={'flex flex-col items-center text-center px-6 py-8 gap-2 ' + (className ?? '')}
    >
      <div className="w-12 h-12 rounded-full bg-reject-bg flex items-center justify-center mb-1">
        <AlertCircle size={20} className="text-rust" aria-hidden />
      </div>
      <h3 className="font-display text-base font-semibold text-ink">{title}</h3>
      {message && <p className="text-sm text-muted max-w-md">{message}</p>}
      {detail && <div className="text-xs text-faint max-w-md mt-1">{detail}</div>}
      {onRetry && (
        <Button onClick={onRetry} className="mt-2">
          <RefreshCw size={14} /> Try again
        </Button>
      )}
    </div>
  )
}
