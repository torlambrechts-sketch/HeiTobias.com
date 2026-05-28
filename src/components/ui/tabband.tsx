import { type ReactNode } from 'react'
import { cn } from '../../lib/cn.js'

/**
 * Forest tab band — the signature DESIGN.md §2 structural move.
 * Dark forest bar with rounded top corners; the active tab is a white
 * "lifted" notch. The white panel attaches directly beneath (no top border).
 */
export function TabBand({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn('bg-forest rounded-t-lg flex items-stretch overflow-hidden', className)}>
      {children}
    </div>
  )
}

export function Tab({
  active = false,
  right = false,
  onClick,
  children,
  className,
}: {
  active?: boolean
  right?: boolean
  onClick?: () => void
  children: ReactNode
  className?: string
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'flex items-center gap-2 px-4 py-3.5 text-sm font-semibold',
        'border-r border-white/10',
        active
          ? 'bg-surface text-ink rounded-t mt-1 ml-1 first:ml-1 hover:bg-surface'
          : 'text-white/80 hover:text-white hover:bg-white/5',
        right && 'ml-auto border-r-0',
        className,
      )}
    >
      {children}
    </button>
  )
}
