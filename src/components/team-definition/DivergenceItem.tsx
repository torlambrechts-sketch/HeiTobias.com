import { Check, GitMerge, Target, TriangleAlert } from 'lucide-react'
import type { DivergenceCriterion } from '../../lib/teamDefinition.js'
import { cn } from '../../lib/cn.js'

// One criterion = one DivergenceItem card. The whole UI commitment is
// here: instead of an aggregate ("the team thinks 0.32"), we render
// EVERY EVALUATOR'S POSITION as a dot on a scale, color-coded by
// E-code. The mean is shown only in the stats footer, and the SD/range
// numbers are alongside it — never as a substitute for the dot plot.
//
// This is the visual realisation of SCIENCE-SPEC §7's
// "surfaces divergence, never averages it away".

const PALETTE = ['#42729e','#3f7d5a','#a8862f','#7a5fa0','#b8584a','#3aa3a3','#c87a4a']

type ConsensusCategory = 'high' | 'moderate' | 'low'
const categoryStyles: Record<ConsensusCategory, { label: string; bg: string; fg: string; border: string; icon: typeof Check }> = {
  high:     { label: 'High consensus',     bg: 'bg-open-bg',     fg: 'text-open-fg',     border: '',                icon: Check },
  moderate: { label: 'Moderate consensus', bg: 'bg-internal-bg', fg: 'text-internal-fg', border: '',                icon: TriangleAlert },
  low:      { label: 'Low consensus',      bg: 'bg-reject-bg',   fg: 'text-reject-fg',   border: 'border border-rust', icon: TriangleAlert },
}

export function DivergenceItem({
  criterion,
  evaluatorOrder,
}: {
  criterion: DivergenceCriterion
  evaluatorOrder: string[]    // ordered evaluator_id list so E1..En is stable across the page
}) {
  const c = categoryStyles[criterion.consensus_category]
  const Icon = c.icon
  // Build scale ticks — adapt to range. Use 5 ticks across [min, max], padded by 10%.
  const rawMin = criterion.min
  const rawMax = criterion.max
  const padding = (rawMax - rawMin) * 0.1 || rawMax * 0.1 || 0.5
  const lo = rawMin - padding
  const hi = rawMax + padding
  const range = hi - lo || 1
  const ticks = [0, 0.25, 0.5, 0.75, 1].map(t => ({
    pct: t * 100,
    label: (lo + t * range).toFixed(criterion.criterion_key.includes('weight') ? 2 : 1),
  }))

  return (
    <div className="border border-line rounded bg-surface overflow-hidden">
      <div className="flex items-center gap-3.5 px-5 py-3.5 border-b border-line flex-wrap">
        <Target size={18} className="text-role" />
        <div className="flex-1 min-w-[200px]">
          <div className="text-[14.5px] font-bold leading-tight">{prettyName(criterion.criterion_key)}</div>
          <div className="text-[11px] text-muted font-mono mt-0.5">{criterion.criterion_key}</div>
        </div>
        <span className={cn(
          'inline-flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider px-2.5 py-1 rounded-full',
          c.bg, c.fg, c.border,
        )}>
          <Icon size={12} /> {c.label}
        </span>
      </div>
      <div className="px-6 pt-5 pb-4">
        {/* Scale + markers (SURFACED positions, not averaged) */}
        <div className="relative py-6">
          <div className="relative h-0.5 bg-canvas-2 rounded">
            {ticks.map((t, i) => (
              <span key={i}>
                <span className="absolute -top-[3px] w-px h-2 bg-line-2" style={{ left: `${t.pct}%` }} />
                <span className="absolute top-[14px] text-[10px] text-faint font-mono -translate-x-1/2" style={{ left: `${t.pct}%` }}>
                  {t.label}
                </span>
              </span>
            ))}
            {criterion.values.map((v, i) => {
              const idx = Math.max(0, evaluatorOrder.indexOf(v.evaluator_id))
              const code = `E${idx + 1}`
              const color = PALETTE[idx % PALETTE.length]
              const left = ((v.value - lo) / range) * 100
              return (
                <span
                  key={i}
                  data-test="divergence-marker"
                  className="absolute top-1/2 w-3.5 h-3.5 rounded-full border-[2.5px] border-white shadow-sm -translate-x-1/2 -translate-y-1/2"
                  style={{ left: `${left}%`, backgroundColor: color }}
                  aria-label={`${code} at ${v.value}`}
                  title={`${code} · ${v.value.toFixed(2)}`}
                />
              )
            })}
          </div>
        </div>

        <div className="flex gap-6 text-[11.5px] text-muted pt-3.5 border-t border-line flex-wrap">
          <span>SD <b className="text-ink font-mono ml-1">{criterion.spread_value.toFixed(3)}</b></span>
          <span>Mean <b className="text-ink font-mono ml-1">{criterion.mean.toFixed(2)}</b></span>
          <span>Range <b className="text-ink font-mono ml-1">{criterion.min.toFixed(2)} – {criterion.max.toFixed(2)}</b></span>
          <span>n <b className="text-ink font-mono ml-1">{criterion.values.length}</b></span>
        </div>

        {criterion.flagged_for_reconciliation && (
          <div className="mt-4 px-4 py-3 bg-canvas border-l-[3px] border-rust rounded flex items-start gap-3">
            <GitMerge size={15} className="text-rust mt-0.5 flex-shrink-0" />
            <div className="flex-1 text-[12.5px]">
              <div className="font-bold text-[13px] mb-1">Flagged for Stage 4 reconciliation</div>
              <div className="text-muted leading-snug">
                The spread here is real — the system surfaces it instead of averaging it away.
                The reconciler will run a structured discussion on this item and record a
                decision_artefact with per-evaluator attribution.
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function prettyName(key: string): string {
  return key
    .split('.')
    .map(p => p.replace(/_/g, ' '))
    .map(p => p.replace(/\b\w/g, c => c.toUpperCase()))
    .join(' · ')
}
