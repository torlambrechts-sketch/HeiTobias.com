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
    <div className="rounded-lg border border-dashed border-internal-fg/60 bg-internal-bg/60 p-4 flex items-start gap-3">
      <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-1 rounded bg-white text-internal-fg border border-internal-fg/30 flex-shrink-0 inline-flex items-center gap-1.5">
        <AlertCircle size={12} /> Sample template
      </span>
      <div className="text-sm text-ink/90 leading-relaxed">
        This is a research-derived SAMPLE Role Profile shipped for the demo. Trait bands, competency
        weights, BARS anchors, and cognitive complexity must be validated per-organization by the
        engaged I/O psychologist before any live decision. <code className="font-mono text-xs bg-white/60 px-1 rounded">validity_status</code> remains
        <code className="font-mono text-xs bg-white/60 px-1 rounded mx-1">dev_stub</code> on each affected row; a row cannot transition to
        <code className="font-mono text-xs bg-white/60 px-1 rounded mx-1">validated</code> until a signed-off methodology produces real values.
        Stubbed sections: <span className="font-mono text-xs">{stubbed.join(' · ')}</span>.
        Per <span className="font-mono text-xs">SCIENCE-SPEC §2, §5</span>; CLAUDE.md Pillar 5.
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
