import type { TraitTarget } from '../types/roleProfile.js'
import { decideTraitRangeRender, bandToPercent, directionPillLabel } from '../lib/traitRangeGeometry.js'
import { AlertTriangle } from 'lucide-react'

// The signature component. Renders one trait_targets[] entry per the
// SCIENCE-SPEC §2 + DESIGN.md §7 contract:
//   - slim track, role-blue tinted band for optimum,
//   - direction pill (top-right),
//   - centre marker as an open circle (role-blue stroke, white fill),
//   - per-trait justification + evidence_refs in a left-rule callout.
//
// HARD RULES:
//   - Never accepts a person-score prop. This is the ROLE side only.
//     A separate PersonFitOnRole component (different surface) renders
//     the person dot against this band.
//   - Refuses to render bare-maximum optimum; shows an error state and
//     logs to the console with a stack trace.

export interface TraitRangeControlProps {
  target: TraitTarget
}

export function TraitRangeControl({ target }: TraitRangeControlProps) {
  const r = decideTraitRangeRender(target)

  if (r.kind === 'error') {
    // Second line of defence per CLAUDE.md §5.
    if (typeof console !== 'undefined') {
      console.error('TraitRangeControl: schema violation', { reason: r.reason, target: r.offendingTarget, stack: new Error().stack })
    }
    return (
      <div className="border border-red-300 bg-red-50 rounded p-3 text-sm text-red-900 flex items-start gap-2">
        <AlertTriangle size={16} className="mt-0.5 flex-shrink-0" />
        <div>
          <div className="font-semibold mb-1">Schema violation — trait target rejected</div>
          <div className="text-xs">{r.reason}</div>
          <div className="text-xs text-red-700/70 mt-1">Trait: {target.trait}</div>
        </div>
      </div>
    )
  }

  const pill = directionPillLabel(r.direction)

  return (
    <div className="flex flex-col gap-3">
      {/* Header: trait name + direction pill */}
      <div className="flex items-center justify-between gap-2">
        <span className="font-display text-lg text-ink">{target.trait}</span>
        <span
          className={
            'text-[10.5px] uppercase tracking-wider font-bold px-2 py-0.5 rounded ' +
            (pill.tone === 'role' ? 'bg-role/10 text-role border border-role/30' :
             pill.tone === 'amber' ? 'bg-internal-bg text-internal-fg border border-internal-fg/20' :
             'bg-canvas-2 text-muted border border-line')
          }
        >
          {pill.label}
        </span>
      </div>

      {/* Track */}
      <Track render={r} />

      {/* Scale */}
      <div className="flex justify-between text-[10px] font-mono text-faint">
        <span>0</span><span>25</span><span>50</span><span>75</span><span>100</span>
      </div>

      {/* Justification + evidence_refs */}
      {(target.justification || (target.evidence_refs?.length ?? 0) > 0) && (
        <div className="border-l-2 border-role pl-3 text-sm">
          {target.justification && <p className="text-ink">{target.justification}</p>}
          {(target.evidence_refs?.length ?? 0) > 0 && (
            <p className="text-[11px] font-mono text-faint mt-1">
              {target.evidence_refs!.join(' · ')}
            </p>
          )}
        </div>
      )}

      {/* Per-target stub flag (auto-converted from legacy {min,max}) */}
      {target._dev_stub_shape && (
        <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-0.5 rounded bg-internal-bg text-internal-fg border border-internal-fg/20 self-start">
          DEV STUB — auto-converted from {'{min,max}'}
        </span>
      )}
    </div>
  )
}

function Track({ render }: { render: Exclude<ReturnType<typeof decideTraitRangeRender>, { kind: 'error' }> }) {
  return (
    <div className="relative h-2.5 w-full rounded-full bg-canvas-2 border border-line">
      {render.kind === 'optimum_band' && (() => {
        const { leftPct, widthPct } = bandToPercent(render)
        const centrePct = Math.max(0, Math.min(1, render.centre)) * 100
        return (
          <>
            <div className="absolute top-0 h-full rounded-full bg-role/25" style={{ left: `${leftPct}%`, width: `${widthPct}%` }} />
            <div className="absolute top-[-2px] h-[14px] w-[2px] bg-role" style={{ left: `${leftPct}%` }} />
            <div className="absolute top-[-2px] h-[14px] w-[2px] bg-role" style={{ left: `calc(${leftPct + widthPct}% - 2px)` }} />
            <div className="absolute top-1/2 -translate-y-1/2 -translate-x-1/2 w-3 h-3 rounded-full border-2 border-role bg-white" style={{ left: `${centrePct}%` }} />
            <div className="absolute -top-5 text-[10px] font-mono text-role" style={{ left: `${leftPct}%` }}>{Math.round(render.lower * 100)}</div>
            <div className="absolute -top-5 text-[10px] font-mono text-role" style={{ left: `calc(${leftPct + widthPct}% - 16px)` }}>{Math.round(render.upper * 100)}</div>
          </>
        )
      })()}

      {render.kind === 'minimum_threshold' && (() => {
        const lowerPct = Math.max(0, Math.min(1, render.lower)) * 100
        return (
          <>
            <div className="absolute top-0 h-full rounded-r-full bg-internal-bg" style={{ left: `${lowerPct}%`, width: `${100 - lowerPct}%` }} />
            <div className="absolute top-[-3px] h-[16px] w-[2px] bg-internal-fg" style={{ left: `${lowerPct}%` }} />
            <div className="absolute -top-5 text-[10px] font-mono text-internal-fg" style={{ left: `${lowerPct}%` }}>≥ {Math.round(render.lower * 100)}</div>
          </>
        )
      })()}

      {render.kind === 'maximum_threshold' && (() => {
        const upperPct = Math.max(0, Math.min(1, render.upper)) * 100
        return (
          <>
            <div className="absolute top-0 h-full rounded-l-full bg-internal-bg" style={{ left: '0%', width: `${upperPct}%` }} />
            <div className="absolute top-[-3px] h-[16px] w-[2px] bg-internal-fg" style={{ left: `${upperPct}%` }} />
            <div className="absolute -top-5 text-[10px] font-mono text-internal-fg" style={{ left: `${upperPct}%` }}>≤ {Math.round(render.upper * 100)}</div>
          </>
        )
      })()}

      {render.kind === 'linear' && (
        <div className="absolute top-0 h-full w-full rounded-full bg-canvas-2" />
      )}
    </div>
  )
}
