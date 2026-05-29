import { type LucideIcon } from 'lucide-react'
import { type ReactNode } from 'react'

// EmptyState — what every list / table / dashboard renders when there
// is genuinely nothing to show. Phase C of production-grade discipline:
// empty states are first-class, not afterthoughts.
//
// Anatomy:
//   * one canonical icon (the entity icon — Briefcase for requisitions,
//     Users for teams, etc.) at 32px, muted
//   * a one-line headline ("No requisitions yet")
//   * a one-paragraph explanation of what would populate the list and
//     what the next action is
//   * an optional primary CTA
//
// Why a dedicated component: scattering `if (rows.length === 0) return
// <p>Empty</p>` across 19 surfaces is the symptom we are fixing. One
// component, one style contract, every surface uses it.

export function EmptyState({
  icon: Icon,
  title,
  body,
  action,
  className,
  ...props
}: {
  icon?: LucideIcon
  title: string
  body?: ReactNode
  action?: ReactNode
  className?: string
} & Omit<React.HTMLAttributes<HTMLDivElement>, 'title'>) {
  return (
    <div
      data-test="empty-state"
      role="status"
      className={'flex flex-col items-center text-center px-6 py-10 gap-2 ' + (className ?? '')}
      {...props}
    >
      {Icon && (
        <div className="w-12 h-12 rounded-full bg-canvas-2 flex items-center justify-center mb-1">
          <Icon size={20} className="text-muted" aria-hidden />
        </div>
      )}
      <h3 className="font-display text-base font-semibold text-ink">{title}</h3>
      {body && (
        <div className="text-sm text-muted max-w-md leading-relaxed">{body}</div>
      )}
      {action && <div className="mt-2">{action}</div>}
    </div>
  )
}
