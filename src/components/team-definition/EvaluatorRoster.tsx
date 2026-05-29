import { Check, Eye, EyeOff } from 'lucide-react'
import type { EvaluatorRow } from '../../lib/teamDefinition.js'

// E1-E6 color palette. Per the mock (team-based-definition.html
// :root --e1 .. --e7). Cycled if more than 7 evaluators (unusual).
const PALETTE = ['#42729e','#3f7d5a','#a8862f','#7a5fa0','#b8584a','#3aa3a3','#c87a4a']

export type EvaluatorWithPerson = EvaluatorRow & {
  full_name: string | null
  primary_email: string | null
}

export function EvaluatorRoster({
  evaluators,
  showNames,
  setShowNames,
}: {
  evaluators: EvaluatorWithPerson[]
  showNames: boolean
  setShowNames: (v: boolean) => void
}) {
  const sorted = [...evaluators].sort((a, b) => (a.submitted_at ?? '').localeCompare(b.submitted_at ?? ''))
  const consenting = evaluators.filter(e => e.allow_attribution_on_reveal).length
  return (
    <>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3 mb-4">
        {sorted.map((ev, idx) => {
          const code = `E${idx + 1}`
          const color = PALETTE[idx % PALETTE.length]
          const reveal = showNames && ev.allow_attribution_on_reveal
          return (
            <div key={ev.id} className="border border-line rounded p-3.5 bg-surface">
              <div className="flex items-center gap-2.5">
                <div
                  className="w-6 h-6 rounded-full flex items-center justify-center text-white font-bold text-[11px] flex-shrink-0"
                  style={{ backgroundColor: color }}
                >
                  {code}
                </div>
                <div className="min-w-0">
                  <div className="text-[13.5px] font-semibold leading-tight truncate">
                    {reveal ? (ev.full_name ?? code) : 'Anonymous'}
                  </div>
                  <div className="text-[11px] text-muted leading-tight mt-0.5 capitalize">
                    {ev.role.replace('_', ' ')}
                  </div>
                </div>
              </div>
              <div className="text-[11px] font-semibold flex items-center gap-1.5 pt-2.5 mt-2.5 border-t border-line text-green">
                {ev.submitted_at
                  ? <><Check size={12} /> Submitted {new Date(ev.submitted_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })} · {ev.allow_attribution_on_reveal ? 'named OK' : 'anon only'}</>
                  : <span className="text-amber">Pending</span>}
              </div>
            </div>
          )
        })}
      </div>

      <div className="flex items-center gap-2.5 bg-canvas px-3.5 py-2.5 rounded text-xs text-muted mb-5">
        {showNames ? <Eye size={13} /> : <EyeOff size={13} />}
        <span>Showing {showNames ? 'names where consented' : 'E-codes only'}.</span>
        <label className="ml-auto inline-flex items-center gap-2 text-ink font-semibold cursor-pointer select-none">
          <input
            type="checkbox"
            checked={showNames}
            onChange={e => setShowNames(e.target.checked)}
            className="accent-forest"
          />
          Reveal names ({consenting} of {evaluators.length} consented)
        </label>
      </div>
    </>
  )
}
