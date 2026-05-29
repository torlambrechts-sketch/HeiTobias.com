import { AlertCircle } from 'lucide-react'
import type { RoleProfileRow } from '../../types/roleProfile.js'
import { isStubbed } from '../../types/roleProfile.js'

// Per CLAUDE.md §5 + the prompt §"OVERRIDING PRINCIPLES" A: a reviewer
// must never be able to mistake a stub for a validated record. This
// banner sits above the fold whenever any field on the role is stubbed.
export function StubBanner({ row }: { row: RoleProfileRow }) {
  const s = isStubbed(row)
  if (!s.anyStubbed) return null
  const stubbed = Object.entries(s.perSection).filter(([, v]) => v).map(([k]) => k)
  return (
    <div className="rounded-lg border border-internal-fg/30 bg-internal-bg/60 p-4 flex items-start gap-3">
      <AlertCircle size={18} className="text-internal-fg flex-shrink-0 mt-0.5" />
      <div className="text-sm">
        <p className="font-semibold text-internal-fg mb-1">SAMPLE / DEV STUB role profile — not yet validated</p>
        <p className="text-ink/80">
          The fields below are placeholder content awaiting I/O-psychologist + legal-advisor sign-off. Stubbed sections:{' '}
          <span className="font-mono">{stubbed.join(', ')}</span>.
          The "Promote to validated" actions remain disabled until an expert has signed off.
        </p>
      </div>
    </div>
  )
}

export function StubPill({ on, label = 'DEV STUB' }: { on: boolean; label?: string }) {
  if (!on) return null
  return (
    <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-0.5 rounded bg-internal-bg text-internal-fg border border-internal-fg/20">
      {label}
    </span>
  )
}
