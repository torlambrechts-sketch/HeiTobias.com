import { Shield } from 'lucide-react'
import { useT } from '../lib/i18n.js'

// Human-in-the-loop disclaimer per CLAUDE.md + EU AI Act (DESIGN.md §7).
// Copy comes from the i18n dictionary; defaults preserve the original
// strings as English fallback for callers that pre-date i18n setup.
export function HitlNotice({ compact = false }: { compact?: boolean }) {
  const t = useT()
  if (compact) {
    return (
      <p className="text-[11px] uppercase tracking-wider text-role font-bold flex items-center gap-1.5">
        <Shield className="w-3.5 h-3.5" strokeWidth={2} />
        {t('hitl.compact_label', 'Informs a human decision — never auto-decides')}
      </p>
    )
  }
  return (
    <div className="border border-line bg-interview-bg/50 px-5 py-4 rounded-lg">
      <div className="flex items-start gap-3">
        <Shield className="w-5 h-5 text-role flex-shrink-0 mt-0.5" strokeWidth={2} />
        <div className="space-y-1">
          <p className="text-sm font-semibold text-ink">{t('hitl.headline', 'This output informs a human decision; it never auto-decides.')}</p>
          <p className="text-xs text-muted leading-relaxed">{t('hitl.body', 'Per EU AI Act and HeiTobias policy: any fit score or model output on this page is an advisory input only. A qualified human assessor remains the decision-maker. Stub content is clearly marked.')}</p>
        </div>
      </div>
    </div>
  )
}
