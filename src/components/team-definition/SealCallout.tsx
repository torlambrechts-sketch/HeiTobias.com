import { Lock } from 'lucide-react'
import { useT } from '../../lib/i18n.js'

// Post-seal banner. Body comes from i18n (en.json seal.body_clean_html /
// seal.body_unclean_html); we just interpolate {count} and {attempts}.
export function SealCallout({
  sealedAt,
  evaluatorCount,
  attemptedReadCount,
}: {
  sealedAt: string | null
  evaluatorCount: number
  attemptedReadCount: number
}) {
  const t = useT()
  const sealedDate = sealedAt
    ? new Date(sealedAt).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
    : '—'
  const template = attemptedReadCount === 0 ? t('seal.body_clean_html') : t('seal.body_unclean_html')
  const html = template
    .replace('{count}',    String(evaluatorCount))
    .replace('{attempts}', String(attemptedReadCount))
  return (
    <div className="rounded border border-role border-l-4 border-l-role bg-interview-bg p-4 mb-6 flex items-start gap-3 text-sm leading-relaxed">
      <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-1 rounded bg-white text-role border border-role/30 inline-flex items-center gap-1.5 flex-shrink-0 whitespace-nowrap">
        <Lock size={13} /> {t('seal.label_prefix')} {sealedDate}
      </span>
      <div className="text-ink/90" dangerouslySetInnerHTML={{ __html: html }} />
    </div>
  )
}
