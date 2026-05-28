import { Link } from 'react-router-dom'
import { Card, CardEyebrow, CardTitle } from '../components/ui/card.js'

export function HomePage() {
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
