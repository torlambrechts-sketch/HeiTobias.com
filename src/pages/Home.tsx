import { Link } from 'react-router-dom'
import { AlertTriangle, Briefcase, Building2, Smartphone, Users } from 'lucide-react'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { envReady } from '../lib/browser-supabase.js'

export function HomePage() {
  const env = envReady()
  return (
    <main className="min-h-screen bg-canvas px-6 py-16">
      <div className="max-w-4xl mx-auto">
        <header className="mb-12">
          <p className="eyebrow">HeiTobias</p>
          <h1 className="font-display text-[40px] font-semibold tracking-tight mt-2">
            Recruiter OS — dev
          </h1>
          <p className="mt-4 text-base text-muted max-w-2xl leading-relaxed">
            Phase 0 + Phase 1 build. Two operating surfaces: a recruiter workspace that drives the
            placement lifecycle, and a mobile-first candidate flow under{' '}
            <code className="text-[13px] bg-canvas-2 px-1.5 py-0.5 rounded">/take/&lt;token&gt;</code>.
          </p>
        </header>

        {!env.ok && (
          <Card className="mb-6 border-rust/40 bg-reject-bg/30">
            <CardBody className="flex items-start gap-3">
              <AlertTriangle className="w-5 h-5 text-rust flex-shrink-0 mt-0.5" />
              <div>
                <CardEyebrow className="text-rust">Setup incomplete</CardEyebrow>
                <CardTitle className="mt-1 text-lg">Supabase env not configured</CardTitle>
                <p className="mt-2 text-sm text-ink">
                  Missing: <code className="text-xs">{env.missing.join(', ')}</code>. The app loaded,
                  but it can&apos;t talk to the database until you set these.
                </p>
                <ol className="mt-3 list-decimal pl-5 text-sm text-ink space-y-1">
                  <li>Copy <code className="text-xs">.env.example</code> to <code className="text-xs">.env.local</code>.</li>
                  <li>Fill <code className="text-xs">VITE_SUPABASE_URL</code> + <code className="text-xs">VITE_SUPABASE_ANON_KEY</code>.</li>
                  <li>Restart the dev server: <code className="text-xs">npm run dev</code>.</li>
                </ol>
              </div>
            </CardBody>
          </Card>
        )}

        <div className="grid sm:grid-cols-2 gap-5">
          <Link to="/requisitions/a3000000-0000-0000-0000-000000000001" className="block group">
            <Card className="h-full group-hover:shadow-soft transition-shadow">
              <CardBody>
                <div className="flex items-center gap-3 mb-2">
                  <span className="w-10 h-10 rounded-lg bg-forest text-white flex items-center justify-center">
                    <Briefcase size={18} strokeWidth={2} />
                  </span>
                  <CardEyebrow>Phase 1 · Recruiter</CardEyebrow>
                </div>
                <CardTitle className="mt-1 text-2xl">Requisition desk</CardTitle>
                <p className="mt-3 text-sm text-muted leading-relaxed">
                  Drive the full lifecycle on the seeded Senior Backend Engineer requisition:
                  invite → consent → take → score → fit → decide → place.
                </p>
              </CardBody>
            </Card>
          </Link>

          <Link to="/activations" className="block group">
            <Card className="h-full group-hover:shadow-soft transition-shadow">
              <CardBody>
                <div className="flex items-center gap-3 mb-2">
                  <span className="w-10 h-10 rounded-lg bg-interview-bg text-role flex items-center justify-center">
                    <Building2 size={18} strokeWidth={2} />
                  </span>
                  <CardEyebrow>Phase 2 · Employer</CardEyebrow>
                </div>
                <CardTitle className="mt-1 text-2xl">Activations</CardTitle>
                <p className="mt-3 text-sm text-muted leading-relaxed">
                  Receive newly-placed candidates at FjordTech. Activate from inherited data,
                  capture ongoing-management consent (legal basis: contract), unlock the
                  post-hire surfaces.
                </p>
              </CardBody>
            </Card>
          </Link>

          <Link to="/people" className="block group">
            <Card className="h-full group-hover:shadow-soft transition-shadow">
              <CardBody>
                <div className="flex items-center gap-3 mb-2">
                  <span className="w-10 h-10 rounded-lg bg-canvas-2 text-forest flex items-center justify-center">
                    <Users size={18} strokeWidth={2} />
                  </span>
                  <CardEyebrow>Phase 0 · RLS smoke</CardEyebrow>
                </div>
                <CardTitle className="mt-1 text-2xl">People</CardTitle>
                <p className="mt-3 text-sm text-muted leading-relaxed">
                  Sign in as one of eight seeded users; the table re-fetches under their RLS scope.
                </p>
              </CardBody>
            </Card>
          </Link>
        </div>

        <Card className="mt-6">
          <CardBody className="flex items-start gap-3">
            <span className="w-10 h-10 rounded-lg bg-canvas-2 text-forest flex items-center justify-center flex-shrink-0">
              <Smartphone size={18} strokeWidth={2} />
            </span>
            <div>
              <CardEyebrow>Candidate flow</CardEyebrow>
              <p className="mt-2 text-sm text-ink leading-relaxed">
                Open the recruiter desk, click <strong>Invite to assess</strong> on a candidate,
                copy the magic link from the invite row, and open{' '}
                <code className="text-[13px] bg-canvas-2 px-1.5 py-0.5 rounded">/take/&lt;token&gt;</code>{' '}
                on a phone. Anon, no login. Consent first, then 5 items, then done.
              </p>
            </div>
          </CardBody>
        </Card>
      </div>
    </main>
  )
}
