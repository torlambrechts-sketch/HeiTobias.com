import { Link } from 'react-router-dom'
import { AlertTriangle } from 'lucide-react'
import { Card, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { envReady } from '../lib/browser-supabase.js'

export function HomePage() {
  const env = envReady()
  return (
    <main className="min-h-screen bg-paper px-4 py-12">
      <div className="max-w-3xl mx-auto">
        <header className="mb-10">
          <p className="font-mono text-[0.65rem] uppercase tracking-wider text-muted">HeiTobias</p>
          <h1 className="font-display text-4xl text-ink mt-1">Recruiter OS · demo</h1>
          <p className="mt-3 font-body text-base text-muted max-w-xl leading-relaxed">
            Phase 0 + Phase 1 dev build. Two surfaces: a recruiter desk to drive the lifecycle, and
            a mobile-first candidate flow under <code className="font-mono text-sm">/take/&lt;token&gt;</code>.
          </p>
        </header>

        {!env.ok && (
          <Card className="mb-6 border-accent">
            <div className="flex items-start gap-3">
              <AlertTriangle className="w-5 h-5 text-accent flex-shrink-0 mt-0.5" />
              <div>
                <CardEyebrow className="text-accent">Setup incomplete</CardEyebrow>
                <CardTitle className="mt-1 text-lg">Supabase env not configured</CardTitle>
                <p className="mt-2 font-body text-sm text-ink">
                  Missing: <code className="font-mono text-xs">{env.missing.join(', ')}</code>. The
                  app loaded, but it can&apos;t talk to the database until you set these.
                </p>
                <ol className="mt-3 list-decimal pl-5 font-body text-sm text-ink space-y-1">
                  <li>Copy <code className="font-mono text-xs">.env.example</code> to <code className="font-mono text-xs">.env.local</code>.</li>
                  <li>Fill <code className="font-mono text-xs">VITE_SUPABASE_URL</code> and <code className="font-mono text-xs">VITE_SUPABASE_ANON_KEY</code> from the Supabase dashboard.</li>
                  <li>Restart the dev server: <code className="font-mono text-xs">npm run dev</code>.</li>
                </ol>
              </div>
            </div>
          </Card>
        )}

        <div className="grid sm:grid-cols-2 gap-4">
          <Link to="/people" className="block">
            <Card className="h-full hover:shadow-hard transition-shadow">
              <CardEyebrow>Phase 0</CardEyebrow>
              <CardTitle className="mt-1">People (RLS smoke)</CardTitle>
              <p className="mt-3 font-body text-sm text-muted">
                Sign in as one of the eight seeded users; the table re-fetches under their RLS scope.
              </p>
            </Card>
          </Link>

          <Link to="/requisitions/a3000000-0000-0000-0000-000000000001" className="block">
            <Card className="h-full hover:shadow-hard-role transition-shadow border-role">
              <CardEyebrow>Phase 1 · Recruiter</CardEyebrow>
              <CardTitle className="mt-1">Requisition desk</CardTitle>
              <p className="mt-3 font-body text-sm text-muted">
                Drive the full lifecycle on the seeded Senior Backend Engineer requisition:
                invite → consent → take → score → fit → decide → place.
              </p>
            </Card>
          </Link>
        </div>

        <section className="mt-10">
          <p className="section-rule">
            <span className="eyebrow">Try the candidate flow</span>
          </p>
          <Card className="mt-4">
            <p className="font-body text-sm text-ink leading-relaxed">
              Open the recruiter desk above, invite a candidate to assess, copy the magic token from
              the invite row, and open <code className="font-mono text-sm">/take/&lt;token&gt;</code>{' '}
              on a phone. Anon, no login.
            </p>
          </Card>
        </section>
      </div>
    </main>
  )
}
