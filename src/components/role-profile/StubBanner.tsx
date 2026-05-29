import { AlertCircle } from 'lucide-react'
import type { RoleProfileRow } from '../../types/roleProfile.js'
import { isStubbed } from '../../types/roleProfile.js'
import { useT } from '../../lib/i18n.js'

// Stub banner — surfaces dev_stub provenance per CLAUDE.md §5.
// Copy comes from i18n; the stubbed-section list is a runtime suffix.
export function StubBanner({ row }: { row: RoleProfileRow }) {
  const t = useT()
  const s = isStubbed(row)
  if (!s.anyStubbed) return null
  const stubbed = Object.entries(s.perSection).filter(([, v]) => v).map(([k]) => k)
  return (
    <div className="rounded-lg border border-dashed border-internal-fg/60 bg-internal-bg/60 p-4 flex items-start gap-3">
      <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-1 rounded bg-white text-internal-fg border border-internal-fg/30 flex-shrink-0 inline-flex items-center gap-1.5">
        <AlertCircle size={12} /> {t('stub_banner.label')}
      </span>
      <div className="text-sm text-ink/90 leading-relaxed">
        <span dangerouslySetInnerHTML={{ __html: t('stub_banner.body_html') }} />{' '}
        {t('stub_banner.stubbed_prefix')} <span className="font-mono text-xs">{stubbed.join(' · ')}</span>.{' '}
        {t('stub_banner.cite')}
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
