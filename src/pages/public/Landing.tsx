import { useEffect } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { ArrowRight, CheckCircle2, Scale, ShieldCheck, Sparkles, Users } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// Landing page at `/`. Signed-in users are redirected to /home (the
// authenticated app overview). Anonymous visitors see the marketing
// surface.
//
// Copy discipline (overriding principle A): no fabricated confidence.
// Claims are exactly what SCIENCE-SPEC permits — validity as a range
// with caveats, fairness as expert-verdict-not-system-assertion, honest
// labels on pending validation. No fabricated testimonials or pricing.

export function LandingPage() {
  usePageTitle('Talent lifecycle, Nordic-first')
  const navigate = useNavigate()
  const supabase = browserSupabase()

  useEffect(() => {
    // Bounce signed-in users to the app overview.
    void supabase.auth.getSession().then(({ data }) => {
      if (data.session) navigate('/home', { replace: true })
    })
  }, [supabase, navigate])

  return (
    <PublicLayout active="product">
      {/* Hero */}
      <section className="max-w-6xl mx-auto px-5 pt-16 pb-12">
        <div className="max-w-3xl">
          <p className="inline-flex items-center gap-2 text-xs uppercase tracking-wider text-forest font-bold mb-4">
            <Sparkles size={14} /> Nordic-first · agency &amp; employer
          </p>
          <h1 className="font-display text-5xl font-bold leading-[1.05] tracking-tight">
            Hiring and growth on one continuous, defensible data spine.
          </h1>
          <p className="text-lg text-muted mt-5 leading-relaxed">
            HeiTobias connects the candidate journey to the employee journey — role profiles as
            the target, person profiles as what's measured — with methodology you can inspect and
            an honest account of what's validated and what isn't.
          </p>
          <div className="flex items-center gap-3 mt-7 flex-wrap">
            <Link to="/contact" className="inline-flex items-center gap-2 bg-forest text-white rounded-lg px-5 py-2.5 text-sm font-medium hover:bg-forest/90">
              Request a demo <ArrowRight size={16} />
            </Link>
            <Link to="/trust" className="inline-flex items-center gap-2 border border-line rounded-lg px-5 py-2.5 text-sm font-medium hover:bg-canvas-2">
              How the methodology works
            </Link>
          </div>
        </div>
      </section>

      {/* Dual audience */}
      <section className="max-w-6xl mx-auto px-5 py-8 grid md:grid-cols-2 gap-5">
        <AudienceCard
          icon={Users}
          eyebrow="For agencies"
          title="Seed profiles, place candidates, keep the relationship"
          points={[
            'Define roles with your clients using a structured, Delphi-style workflow',
            'Run one unified candidate assessment session, not five disconnected tools',
            'Place candidates across an explicit, consent-gated hand-off',
          ]}
        />
        <AudienceCard
          icon={ShieldCheck}
          eyebrow="For employers"
          title="Inherit the profile, activate the lifecycle"
          points={[
            'Receive placed employees with their profile and consent state intact',
            'Support managers with grounded, citation-backed 1:1 preparation',
            'Track re-fit over time — developmental by default, never a performance verdict',
          ]}
        />
      </section>

      {/* Differentiators — honest */}
      <section className="bg-surface border-y border-line">
        <div className="max-w-6xl mx-auto px-5 py-12">
          <h2 className="font-display text-2xl font-bold">What makes it defensible</h2>
          <p className="text-muted mt-1 text-sm max-w-2xl">
            Each claim below is exactly what the science supports — stated as a range with caveats,
            never as fabricated certainty.
          </p>
          <div className="grid md:grid-cols-2 gap-5 mt-7">
            <Differentiator
              icon={Scale}
              title="Trait targets as ranges, not maxima"
              body="Personality targets are encoded as bands with a direction and a justification. 'More is better' is disallowed unless there's an explicit, justified threshold."
            />
            <Differentiator
              icon={CheckCircle2}
              title="Structured interview, front-loaded"
              body="The strongest single predictor of job performance is a structured interview (Sackett et al. 2022) — so the platform puts structured prep at the centre, not the periphery."
            />
            <Differentiator
              icon={ShieldCheck}
              title="EU AI Act native, GDPR by design"
              body="Multi-tenant from row zero, consent-gated personal data, EU-resident processing, immutable audit. Built to the AI Act's original 2026 requirements."
            />
            <Differentiator
              icon={Sparkles}
              title="Honest about what's validated"
              body="Every psychometric value carries a provenance label. Where a number is a placeholder pending expert sign-off, the platform says so — to you and to your candidates."
            />
          </div>
          <p className="text-sm text-ink mt-7 border-l-2 border-forest pl-4">
            <strong>Fit informs, never decides.</strong> Every consequential hiring or performance
            action requires a human decision, recorded and overridable. No score auto-rejects,
            auto-ranks-to-action, or auto-grades anyone.
          </p>
        </div>
      </section>

      {/* Trust callouts */}
      <section className="max-w-6xl mx-auto px-5 py-12">
        <div className="grid md:grid-cols-3 gap-5 text-sm">
          <TrustCallout title="No proprietary black boxes" body="Open-domain, public-source instruments only. The excluded list (MBTI, DISC, learning styles, Belbin as scored measures) is published with reasons." />
          <TrustCallout title="Inspectable methodology" body="Most B2B platforms hide their methods. Ours is on the trust page — readable even if you're not a psychometrician." />
          <TrustCallout title="Citation-grounded guidance" body="Manager guidance is generated from a frameworks library with provenance, never freeform model output about a named person." />
        </div>
      </section>

      {/* Testimonials — honest placeholder per CLAUDE.md never-list */}
      <section className="bg-canvas-2 border-y border-line">
        <div className="max-w-6xl mx-auto px-5 py-12 text-center">
          <h2 className="font-display text-2xl font-bold">Customer voices</h2>
          <p className="text-muted mt-2">
            Coming soon. We're in the design-partner phase and will share real customer voices once
            we have them — we don't publish quotes we don't have.
          </p>
        </div>
      </section>

      {/* Pricing — honest placeholder */}
      <section className="max-w-6xl mx-auto px-5 py-12 text-center">
        <h2 className="font-display text-2xl font-bold">Pricing</h2>
        <p className="text-muted mt-2 max-w-xl mx-auto">
          Pricing to be announced. Design partners use the platform free during the validation
          phase. <Link to="/contact" className="text-role underline">Apply to be a design partner.</Link>
        </p>
      </section>

      {/* CTA */}
      <section className="bg-forest text-white">
        <div className="max-w-6xl mx-auto px-5 py-14 text-center">
          <h2 className="font-display text-3xl font-bold">See it on your own roles</h2>
          <p className="text-white/80 mt-2 max-w-xl mx-auto">
            Request a demo and we'll walk you through a placement, a manager workspace, and a re-fit
            trajectory with your context.
          </p>
          <Link to="/contact" className="inline-flex items-center gap-2 bg-white text-forest rounded-lg px-6 py-3 text-sm font-semibold mt-6 hover:bg-white/90">
            Request a demo <ArrowRight size={16} />
          </Link>
        </div>
      </section>
    </PublicLayout>
  )
}

function AudienceCard({ icon: Icon, eyebrow, title, points }: { icon: typeof Users; eyebrow: string; title: string; points: string[] }) {
  return (
    <div className="border border-line rounded-xl bg-surface p-6">
      <div className="flex items-center gap-2 text-forest">
        <Icon size={18} />
        <span className="text-xs uppercase tracking-wider font-bold">{eyebrow}</span>
      </div>
      <h3 className="font-display text-xl font-semibold mt-2">{title}</h3>
      <ul className="mt-4 flex flex-col gap-2">
        {points.map((p, i) => (
          <li key={i} className="flex items-start gap-2 text-sm text-ink/90">
            <CheckCircle2 size={16} className="text-forest flex-shrink-0 mt-0.5" /> {p}
          </li>
        ))}
      </ul>
    </div>
  )
}

function Differentiator({ icon: Icon, title, body }: { icon: typeof Scale; title: string; body: string }) {
  return (
    <div className="flex gap-3">
      <div className="w-9 h-9 rounded-lg bg-canvas-2 flex items-center justify-center flex-shrink-0">
        <Icon size={18} className="text-forest" />
      </div>
      <div>
        <h3 className="font-semibold">{title}</h3>
        <p className="text-sm text-muted mt-1 leading-relaxed">{body}</p>
      </div>
    </div>
  )
}

function TrustCallout({ title, body }: { title: string; body: string }) {
  return (
    <div className="border border-line rounded-lg p-4 bg-surface">
      <h3 className="font-semibold">{title}</h3>
      <p className="text-muted mt-1 leading-relaxed">{body}</p>
    </div>
  )
}
