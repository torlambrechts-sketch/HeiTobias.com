import { AlertTriangle } from 'lucide-react'

/**
 * Human-in-the-loop disclaimer — must accompany any surface where a fit score,
 * recommendation, or model output about a named person is rendered (CLAUDE.md
 * hard rule + EU AI Act compliance per PHASE1-SPEC §10).
 */
export function HitlNotice({ compact = false }: { compact?: boolean }) {
  if (compact) {
    return (
      <p className="font-mono text-[0.7rem] uppercase tracking-wider text-accent flex items-center gap-1.5">
        <AlertTriangle className="w-3.5 h-3.5" />
        Informs a human decision — never auto-decides
      </p>
    )
  }
  return (
    <div className="border-l-4 border-accent bg-paper p-4 rounded">
      <div className="flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 text-accent flex-shrink-0 mt-0.5" />
        <div className="space-y-1">
          <p className="font-body font-semibold text-ink text-sm">
            This output informs a human decision; it never auto-decides.
          </p>
          <p className="font-body text-xs text-muted leading-relaxed">
            Per EU AI Act and HeiTobias policy: any fit score or model output on this page is an
            advisory input only. A qualified human assessor remains the decision-maker. Stub
            content is clearly marked.
          </p>
        </div>
      </div>
    </div>
  )
}
