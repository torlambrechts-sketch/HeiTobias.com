import { Briefcase, Clock } from 'lucide-react'
import type { RunRow } from '../../lib/teamDefinition.js'
import { formatStage } from '../../lib/teamDefinition.js'
import { Pill } from '../ui/badges.js'

// Run-page H1 + sub-line. Mirrors team-based-definition.html lines 310-327
// minus the action buttons (those are stage-dependent and live on
// individual stage components).
export function RunHeader({ run }: { run: RunRow }) {
  const stage = formatStage(run.stage)
  const allDevStubs = Object.values(run.thresholds_json).every(v => v._dev_stub)
  return (
    <div className="flex items-start gap-6 flex-wrap mb-5">
      <div className="flex-1 min-w-0">
        <h1 className="font-display text-3xl font-semibold tracking-tight">
          {(run.draft_definition_json['title'] as string | undefined) ?? run.role_family}
        </h1>
        <div className="flex items-center gap-2 text-sm text-muted mt-1.5 flex-wrap">
          <Briefcase size={14} />
          <span className="font-mono text-xs">run #{run.id.slice(0, 8)}</span>
          <span className="text-faint">·</span>
          <span>Family: {run.role_family}</span>
          <span className="text-faint">·</span>
          <Clock size={13} />
          <span>Deadline {new Date(run.deadline_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
        </div>
        <div className="flex items-center gap-2 mt-3 flex-wrap">
          <Pill tone={stage.num === 4 ? 'open' : stage.num === 3 ? 'internal' : 'interview'}>
            Stage {stage.num} — {stage.label}
          </Pill>
          <Pill tone="interview">Purpose: {run.purpose.replace('_', ' ')}</Pill>
          {allDevStubs && <Pill tone="reject">Thresholds: dev_stub</Pill>}
        </div>
      </div>
    </div>
  )
}
