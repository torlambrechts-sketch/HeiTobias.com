import { Lock } from 'lucide-react'

// Post-seal banner. Mirrors team-based-definition.html lines 361-364.
// The point is to make the seal event visible — "your evaluators all
// submitted independently, no one peeked, here's the seal moment."
export function SealCallout({
  sealedAt,
  evaluatorCount,
  attemptedReadCount,
}: {
  sealedAt: string | null
  evaluatorCount: number
  attemptedReadCount: number
}) {
  const sealedDate = sealedAt
    ? new Date(sealedAt).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
    : '—'
  return (
    <div className="rounded border border-role border-l-4 border-l-role bg-interview-bg p-4 mb-6 flex items-start gap-3 text-sm leading-relaxed">
      <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-1 rounded bg-white text-role border border-role/30 inline-flex items-center gap-1.5 flex-shrink-0 whitespace-nowrap">
        <Lock size={13} /> Sealed at {sealedDate}
      </span>
      <div className="text-ink/90">
        All <strong>{evaluatorCount}</strong> evaluators submitted independently before Stage 2 closed.{' '}
        {attemptedReadCount === 0
          ? <>No pre-reveal reads were attempted — the audit log is clean.</>
          : <><strong className="text-rust">{attemptedReadCount}</strong> read-during-seal attempt{attemptedReadCount === 1 ? '' : 's'} logged
              (<code className="font-mono text-xs">audit_log.action='team_def.read_during_seal'</code>) — review before sign-off.</>
        }{' '}
        Submissions are now immutable. Per Linstone &amp; Turoff (1975) Delphi method.
      </div>
    </div>
  )
}
