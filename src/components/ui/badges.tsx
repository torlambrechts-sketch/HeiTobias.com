import { type HTMLAttributes } from 'react'
import { cn } from '../../lib/cn.js'

export function StubBadge({ className, ...props }: HTMLAttributes<HTMLSpanElement>) {
  return (
    <span
      className={cn(
        'inline-flex items-center px-2 py-0.5 font-mono text-[0.65rem] uppercase tracking-wider',
        'border-2 border-accent bg-paper text-accent rounded',
        className,
      )}
      {...props}
    >
      Dev stub
    </span>
  )
}

export function ValidityChip({
  status,
  className,
  ...props
}: { status: 'dev_stub' | 'licensed' | 'validated' } & HTMLAttributes<HTMLSpanElement>) {
  const tone =
    status === 'validated'
      ? 'border-person text-person'
      : status === 'licensed'
        ? 'border-role text-role'
        : 'border-accent text-accent'
  return (
    <span
      className={cn(
        'inline-flex items-center px-2 py-0.5 font-mono text-[0.65rem] uppercase tracking-wider rounded bg-paper border-2',
        tone,
        className,
      )}
      {...props}
    >
      {status.replace('_', ' ')}
    </span>
  )
}

export function ConsentChip({
  active,
  purpose,
  className,
  ...props
}: { active: boolean; purpose: string } & HTMLAttributes<HTMLSpanElement>) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 px-2 py-0.5 font-mono text-[0.65rem] uppercase tracking-wider rounded',
        'border-2 bg-paper',
        active ? 'border-person text-person' : 'border-line text-muted',
        className,
      )}
      {...props}
    >
      <span className={cn('inline-block w-1.5 h-1.5 rounded-full', active ? 'bg-person' : 'bg-muted')} />
      Consent · {purpose} · {active ? 'active' : 'inactive'}
    </span>
  )
}
