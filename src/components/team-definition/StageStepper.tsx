import { Check } from 'lucide-react'
import type { TeamDefinitionStage } from '../../lib/teamDefinition.js'
import { cn } from '../../lib/cn.js'

// Four-stage Delphi stepper. Mirrors team-based-definition.html lines
// 334-340. The labels are scientific (Independent rating, not "Rate"),
// because the UI is teaching the methodology while it runs it.
const STAGES: { num: 1 | 2 | 3 | 4; label: string; sub: string }[] = [
  { num: 1, label: 'Setup',                    sub: 'Pick role · invite evaluators' },
  { num: 2, label: 'Independent rating',       sub: 'Sealed until all submit / deadline' },
  { num: 3, label: 'Divergence',               sub: 'Surface, never average' },
  { num: 4, label: 'Reconciliation & sign-off',sub: 'Human decisions, attributed' },
]

function stageIndex(s: TeamDefinitionStage): number {
  switch (s) {
    case 'setup':          return 1
    case 'rating':         return 2
    case 'divergence':     return 3
    case 'reconciliation': return 4
    case 'signed_off':     return 4
    case 'abandoned':      return 1
  }
}

export function StageStepper({ stage }: { stage: TeamDefinitionStage }) {
  const current = stageIndex(stage)
  return (
    <div className="bg-surface border border-line rounded-lg shadow-soft overflow-hidden flex flex-col lg:flex-row mb-5">
      {STAGES.map(({ num, label, sub }) => {
        const done = num < current
        const active = num === current
        return (
          <div
            key={num}
            className={cn(
              'flex-1 px-4 py-3.5 flex items-center gap-3 border-b lg:border-b-0 lg:border-r border-line last:border-r-0',
              active && 'bg-canvas',
            )}
          >
            <span
              className={cn(
                'w-7 h-7 rounded-full flex items-center justify-center font-bold text-[13px] flex-shrink-0',
                done   && 'bg-green text-white',
                active && 'bg-forest text-white',
                !done && !active && 'bg-canvas-2 text-muted',
              )}
              aria-label={done ? `Stage ${num} done` : active ? `Stage ${num} current` : `Stage ${num} pending`}
            >
              {done ? <Check size={14} strokeWidth={2.5} /> : num}
            </span>
            <div className="min-w-0">
              <div className="text-[10.5px] font-bold uppercase tracking-wider text-muted">
                Stage {num}{active ? ' · current' : ''}
              </div>
              <div className={cn('text-sm font-semibold mt-0.5', (done || active) && 'text-ink', !done && !active && 'text-muted')}>
                {label}
              </div>
              <div className="text-[11.5px] text-faint mt-0.5">{sub}</div>
            </div>
          </div>
        )
      })}
    </div>
  )
}
