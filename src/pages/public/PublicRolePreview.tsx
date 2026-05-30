import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Loader2 } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { PublicShareFrame, ShareError } from '../../components/public/PublicShareFrame.js'
import { StubBadge } from '../../components/ui/badges.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /public/role/:token — field-stripped, watermarked public preview of a
// signed-off role profile. Calls public_role_view() which strips internal
// fields server-side and logs the access. Anon-readable.

type RoleView = {
  ok: boolean
  reason?: string
  shared_by_org?: string
  shared_at?: string
  title?: string
  family?: string | null
  version?: number
  status?: string
  definition?: Record<string, unknown>
  defensibility_summary?: { has_signoff?: boolean; signed_off_at?: string | null }
}

export function PublicRolePreviewPage() {
  usePageTitle('Shared role profile')
  const { token } = useParams<{ token: string }>()
  const supabase = browserSupabase()
  const [view, setView] = useState<RoleView | null>(null)

  useEffect(() => {
    if (!token) return
    void (async () => {
      const { data, error } = await supabase.rpc('public_role_view' as never, {
        p_token: token, p_ua: navigator.userAgent,
      } as never)
      if (error) { setView({ ok: false, reason: error.message }); return }
      setView(data as unknown as RoleView)
    })()
  }, [supabase, token])

  if (!view) {
    return <div className="min-h-screen flex items-center justify-center text-muted text-sm"><Loader2 className="animate-spin mr-2" size={16} /> Loading shared profile…</div>
  }
  if (!view.ok) return <ShareError reason={view.reason} />

  const def = view.definition ?? {}
  const competencies = (def.competencies as Array<{ key: string; name?: string; weight: number; criticality?: string; _dev_stub?: boolean }>) ?? []
  const traits = (def.trait_targets as Array<{ trait: string; direction: string; centre?: number; lower?: number; upper?: number; _dev_stub?: boolean }>) ?? []
  const tasks = (def.task_layer as Array<{ task: string; criticality?: string }>) ?? []
  const success = (def.success_criteria as Array<{ horizon: string; dimension: string; behaviour: string }>) ?? []

  return (
    <PublicShareFrame sharedByOrg={view.shared_by_org} sharedAt={view.shared_at} kind="role profile">
      <div className="flex items-baseline gap-3 flex-wrap">
        <h1 className="font-display text-3xl font-bold">{view.title}</h1>
        <span className="text-sm text-muted">v{view.version}{view.family ? ` · ${view.family}` : ''}</span>
        {view.defensibility_summary?.has_signoff && (
          <span className="text-xs text-green border border-green/40 rounded px-2 py-0.5">signed off</span>
        )}
      </div>

      {tasks.length > 0 && (
        <Section title="Key tasks">
          <ul className="list-disc pl-5 space-y-1 text-sm">
            {tasks.slice(0, 12).map((t, i) => <li key={i}>{t.task}{t.criticality ? <span className="text-faint"> · {t.criticality}</span> : null}</li>)}
          </ul>
        </Section>
      )}

      {competencies.length > 0 && (
        <Section title="Competencies & weights">
          <ul className="flex flex-col gap-1.5 text-sm">
            {competencies.map((c, i) => (
              <li key={i} className="flex items-center gap-3 border-b border-line py-1">
                <span className="flex-1">{c.name ?? c.key}</span>
                {c.criticality && <span className="text-xs text-faint">{c.criticality}</span>}
                <span className="font-mono text-xs">{c.weight}</span>
                {c._dev_stub && <StubBadge />}
              </li>
            ))}
          </ul>
        </Section>
      )}

      {traits.length > 0 && (
        <Section title="Trait targets (as ranges)">
          <p className="text-xs text-muted mb-2">
            Targets are bands with a direction, not maxima — consistent with the methodology.
          </p>
          <ul className="flex flex-col gap-1.5 text-sm">
            {traits.map((t, i) => (
              <li key={i} className="flex items-center gap-3 border-b border-line py-1">
                <span className="flex-1">{t.trait}</span>
                <span className="text-xs text-faint">{t.direction}</span>
                <span className="font-mono text-xs">
                  {t.lower != null && t.upper != null ? `${t.lower}–${t.upper}` : t.centre ?? '—'}
                </span>
                {t._dev_stub && <StubBadge />}
              </li>
            ))}
          </ul>
        </Section>
      )}

      {success.length > 0 && (
        <Section title="Success criteria">
          <ul className="list-disc pl-5 space-y-1 text-sm">
            {success.map((s, i) => <li key={i}><span className="text-faint">{s.horizon} · {s.dimension}:</span> {s.behaviour}</li>)}
          </ul>
        </Section>
      )}
    </PublicShareFrame>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-6">
      <h2 className="font-display text-lg font-semibold border-b border-line pb-1 mb-2">{title}</h2>
      {children}
    </section>
  )
}
