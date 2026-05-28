import { type HTMLAttributes, type ReactNode } from 'react'
import { cn } from '../../lib/cn.js'

/**
 * Soft tinted status pill — DESIGN.md §6.
 * One consistent system for hiring states AND re-fit quadrants.
 */
export type PillTone =
  | 'open'        // open / active / stable
  | 'draft'       // draft / growth gap / assessed
  | 'internal'   // internal / consent:hiring
  | 'reject'     // rejected / emerging misfit
  | 'interview'  // interview / flight risk
  | 'offer'      // offer

const tones: Record<PillTone, string> = {
  open:      'bg-open-bg text-open-fg',
  draft:     'bg-draft-bg text-draft-fg',
  internal:  'bg-internal-bg text-internal-fg',
  reject:    'bg-reject-bg text-reject-fg',
  interview: 'bg-interview-bg text-interview-fg',
  offer:     'bg-offer-bg text-offer-fg',
}

export function Pill({
  tone = 'open',
  className,
  children,
  ...props
}: { tone?: PillTone; children?: ReactNode } & HTMLAttributes<HTMLSpanElement>) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 px-3 py-1 rounded-full',
        'text-[11px] font-bold uppercase tracking-wider',
        tones[tone],
        className,
      )}
      {...props}
    >
      {children}
    </span>
  )
}

/** Role data = blue (DESIGN.md §7 entity color system). */
export function RoleBadge({ children, className, ...props }: HTMLAttributes<HTMLSpanElement> & { children?: ReactNode }) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-bold uppercase tracking-wider',
        'bg-interview-bg text-role',
        className,
      )}
      {...props}
    >
      {children ?? 'Role'}
    </span>
  )
}

/** Person data = green. */
export function PersonBadge({ children, className, ...props }: HTMLAttributes<HTMLSpanElement> & { children?: ReactNode }) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-bold uppercase tracking-wider',
        'bg-open-bg text-person',
        className,
      )}
      {...props}
    >
      {children ?? 'Person'}
    </span>
  )
}

/** DEV STUB marker — kept loud per CLAUDE.md "Validated science & DEV STUBs". */
export function StubBadge({ className, ...props }: HTMLAttributes<HTMLSpanElement>) {
  return (
    <Pill tone="reject" className={className} {...props}>
      Dev stub
    </Pill>
  )
}

/** Instrument validity status — pluggable I/O seam (Phase 1 §4). */
export function ValidityChip({
  status,
  className,
  ...props
}: { status: 'dev_stub' | 'licensed' | 'validated' } & HTMLAttributes<HTMLSpanElement>) {
  const tone: PillTone = status === 'validated' ? 'open' : status === 'licensed' ? 'interview' : 'reject'
  return (
    <Pill tone={tone} className={className} {...props}>
      {status.replace('_', ' ')}
    </Pill>
  )
}

/** Consent state shown as first-class wherever personal data appears (DESIGN.md §7). */
export function ConsentChip({
  active,
  purpose,
  className,
  ...props
}: { active: boolean; purpose: string } & HTMLAttributes<HTMLSpanElement>) {
  const tone: PillTone = active ? 'internal' : 'reject'
  return (
    <Pill tone={tone} className={className} {...props}>
      <Shield />
      Consent · {purpose} · {active ? 'active' : 'inactive'}
    </Pill>
  )
}

function Shield() {
  return (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
    </svg>
  )
}
