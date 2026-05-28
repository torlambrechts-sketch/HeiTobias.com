import { forwardRef, type SelectHTMLAttributes } from 'react'
import { cn } from '../../lib/cn.js'

export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(
  function Select({ className, ...props }, ref) {
    return (
      <select
        ref={ref}
        className={cn(
          'block w-full px-3 py-2.5 text-sm bg-surface text-ink',
          'border border-line-2 rounded',
          'focus:outline-none focus:ring-2 focus:ring-green',
          'disabled:opacity-50',
          className,
        )}
        {...props}
      />
    )
  },
)
