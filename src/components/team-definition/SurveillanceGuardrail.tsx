import { ShieldAlert } from 'lucide-react'
import { useT } from '../../lib/i18n.js'

// THE LOAD-BEARING UI GUARDRAIL. Body copy comes from the i18n
// dictionary so the CLAUDE.md i18n mandate is honoured for the most
// load-bearing scientific framing on the page. See en.json key
// `guardrail.body_html`. Nordic translations are HANDOFF.
//
// Schema-side belt: chk_team_def_evaluations_no_peer_personality in
// 20260529095459_team_definition_cp31_schema.sql. UI-side belt: this.
export function SurveillanceGuardrail() {
  const t = useT()
  return (
    <div
      data-test="surveillance-guardrail"
      className="rounded border border-rust border-l-4 border-l-rust bg-reject-bg p-4 mb-6 flex items-start gap-3 text-sm leading-relaxed"
    >
      <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-1 rounded bg-white text-rust border border-rust/30 inline-flex items-center gap-1.5 flex-shrink-0 whitespace-nowrap">
        <ShieldAlert size={13} /> {t('guardrail.label')}
      </span>
      <div className="text-ink/90" dangerouslySetInnerHTML={{ __html: t('guardrail.body_html') }} />
    </div>
  )
}
