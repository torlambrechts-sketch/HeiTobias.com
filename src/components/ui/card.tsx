import { type HTMLAttributes } from 'react'
import { cn } from '../../lib/cn.js'

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        'bg-surface border-2 border-ink rounded p-6',
        className,
      )}
      {...props}
    />
  )
}

export function CardTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return <h2 className={cn('font-display text-2xl leading-tight', className)} {...props} />
}

export function CardEyebrow({ className, ...props }: HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn('eyebrow', className)} {...props} />
}
