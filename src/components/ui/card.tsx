import { type HTMLAttributes } from 'react'
import { cn } from '../../lib/cn.js'

/**
 * Card / panel per DESIGN.md §6:
 *   white surface · 1px hairline border · radius-lg · soft glow shadow.
 * Attach under a TabBand by passing `attached` — drops the top border + radius.
 */
export function Card({
  className,
  attached = false,
  ...props
}: HTMLAttributes<HTMLDivElement> & { attached?: boolean }) {
  return (
    <div
      className={cn(
        'bg-surface border border-line shadow-soft',
        attached ? 'border-t-0 rounded-b-lg' : 'rounded-lg',
        className,
      )}
      {...props}
    />
  )
}

export function CardHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn('px-6 py-5 border-b border-line flex items-center gap-3', className)}
      {...props}
    />
  )
}

export function CardTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return <h2 className={cn('font-display text-2xl font-semibold', className)} {...props} />
}

export function CardEyebrow({ className, ...props }: HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn('eyebrow', className)} {...props} />
}

export function CardBody({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('px-6 py-5', className)} {...props} />
}
