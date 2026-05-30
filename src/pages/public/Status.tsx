import { useEffect, useState } from 'react'
import { CheckCircle2, AlertTriangle, Loader2 } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /status — customer-facing status page. Reads platform_status_public()
// (aggregate, no identifying data). If an official hosting-platform
// status page is later adopted, this can redirect there; for now it
// surfaces incident state from our own monitoring tables.

type Status = {
  status: 'operational' | 'degraded' | 'maintenance' | 'outage'
  message: string | null
  status_updated_at: string | null
  as_of: string
}

export function StatusPage() {
  usePageTitle('System status')
  const supabase = browserSupabase()
  const [s, setS] = useState<Status | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    void (async () => {
      const { data, error } = await supabase.rpc('platform_status_public' as never)
      if (error) { setErr(error.message); return }
      setS(data as unknown as Status)
    })()
  }, [supabase])

  const operational = s && s.status === 'operational'

  return (
    <PublicLayout>
      <div className="max-w-2xl mx-auto px-5 py-12">
        <header className="mb-6">
          <p className="text-xs uppercase tracking-wider text-forest font-bold">Status</p>
          <h1 className="font-display text-4xl font-bold mt-1">System status</h1>
        </header>

        {err && <p className="text-sm text-muted">Status is temporarily unavailable.</p>}
        {!s && !err && <div className="text-sm text-muted flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Checking…</div>}

        {s && (
          <>
            <div className={'rounded-xl border p-5 flex items-center gap-3 ' + (operational ? 'border-green/40 bg-green/5' : 'border-amber/50 bg-internal-bg/40')}>
              {operational ? <CheckCircle2 size={28} className="text-green" /> : <AlertTriangle size={28} className="text-amber" />}
              <div>
                <p className="font-display text-xl font-semibold">
                  {operational ? 'All systems operational'
                    : s.status === 'maintenance' ? 'Scheduled maintenance'
                    : s.status === 'degraded' ? 'Degraded performance'
                    : 'Service disruption'}
                </p>
                <p className="text-xs text-muted mt-0.5">As of {new Date(s.as_of).toLocaleString()}</p>
              </div>
            </div>

            {s.message && (
              <section className="mt-6 border border-line rounded p-3 text-sm">
                <p>{s.message}</p>
                {s.status_updated_at && <p className="text-xs text-faint mt-1">Updated {new Date(s.status_updated_at).toLocaleString()}</p>}
              </section>
            )}

            <section className="mt-8 border-t border-line pt-4 text-sm text-muted">
              <p>
                This page reflects platform-operator status. Detailed uptime and response-time
                telemetry lives in our monitoring stack; status notifications (email + RSS) are
                coming. Reach us via the <a href="/contact" className="text-role underline">contact form</a>.
              </p>
            </section>
          </>
        )}
      </div>
    </PublicLayout>
  )
}
