import { forwardRef, type ButtonHTMLAttributes } from 'react'
import { cn } from '../../lib/cn.js'

type Variant = 'primary' | 'secondary' | 'ghost'

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant
}

const base =
  'inline-flex items-center justify-center gap-2 px-4 py-2 font-body text-sm font-semibold ' +
  'border-2 border-ink rounded transition-transform focus-visible:outline-none ' +
  'focus-visible:ring-2 focus-visible:ring-accent ' +
  'disabled:opacity-50 disabled:cursor-not-allowed'

const variants: Record<Variant, string> = {
  primary:   'bg-ink text-paper hover:-translate-x-px hover:-translate-y-px hover:shadow-hard active:translate-x-0 active:translate-y-0',
  secondary: 'bg-surface text-ink hover:bg-paper',
  ghost:     'border-transparent bg-transparent text-ink hover:bg-surface',
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { className, variant = 'primary', ...props },
  ref,
) {
  return <button ref={ref} className={cn(base, variants[variant], className)} {...props} />
})
