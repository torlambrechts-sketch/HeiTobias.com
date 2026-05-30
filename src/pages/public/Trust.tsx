import { type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /trust (and /methodology) — the SCIENCE-SPEC, made public and readable.
// This page is the platform's differentiator: most B2B SaaS hide their
// methods; this one's value depends on being inspectable. Written for a
// prospect who isn't a psychometrician, with the dev_stub discipline
// explained honestly.

export function TrustPage() {
  usePageTitle('Methodology & trust')
  return (
    <PublicLayout active="trust">
      <article className="max-w-3xl mx-auto px-5 py-12 flex flex-col gap-8">
        <header>
          <p className="text-xs uppercase tracking-wider text-forest font-bold">Methodology</p>
          <h1 className="font-display text-4xl font-bold mt-1">How HeiTobias works, and what it claims</h1>
          <p className="text-muted mt-3 text-lg leading-relaxed">
            We believe a hiring platform should be inspectable. Here's the evidence base, the
            instrument choices, the fairness methods, and — importantly — an honest account of
            what's validated today and what's still pending expert sign-off.
          </p>
        </header>

        <Block title="The evidence base">
          <p>
            The strongest single predictor of job performance is a <strong>structured
            interview</strong>, with cognitive ability and structured assessments close behind
            (Sackett, Zhang, Berry &amp; Lievens, 2022 — a re-analysis that corrected long-standing
            overestimates of general-mental-ability validity). We treat that re-analysis as the
            current best evidence, and we present the contested points honestly rather than
            cherry-picking the most flattering coefficient.
          </p>
        </Block>

        <Block title="Instrument selection — open, public, inspectable">
          <p>
            We use open-domain, public-source instruments only. We do not integrate proprietary
            black-box assessments. Some popular tools are <strong>excluded as scored
            measures</strong> because the evidence doesn't support them for selection:
          </p>
          <ul className="list-disc pl-5 space-y-1 mt-2">
            <li>MBTI, DISC, Insights / "colours" — low predictive validity, poor test-retest</li>
            <li>Learning styles — not supported by evidence</li>
            <li>Belbin team roles, 9-box auto-rating — discussion aids at best, not measures</li>
          </ul>
          <p className="mt-2 text-sm text-muted">
            They may appear as clearly-labelled discussion aids, never as scored selection
            instruments.
          </p>
        </Block>

        <Block title="Trait targets are ranges, not maxima">
          <p>
            Personality targets are encoded as <strong>bands</strong> — a centre, a range, and a
            direction — with a written justification. "More is always better" is disallowed
            unless there's an explicitly justified threshold. This matters because, for traits
            like conscientiousness and emotional stability, the relationship with performance is
            often an inverted-U: too much is as much a problem as too little (Le et al. 2011;
            Pierce &amp; Aguinis 2013).
          </p>
        </Block>

        <Block title="Fairness — computation, not verdict">
          <p>
            We compute fairness diagnostics: adverse-impact ratio (the four-fifths inspection),
            Cleary's model of differential prediction, and differential item functioning (DIF).
            But the platform does <strong>not</strong> declare a result "fair" or "acceptable" —
            that is an expert and legal judgment. We surface the numbers, with confidence
            intervals, for a qualified human to interpret.
          </p>
        </Block>

        <Block title="Nordic norms — honest status">
          <p>
            Valid scoring needs population-appropriate norms. Collecting robust Nordic norm
            samples (with measurement-invariance checks across languages) is long-pole work, and
            it's not done yet. Until it is, norm-dependent values are labelled as placeholders.
            We'd rather show you a clearly-labelled placeholder than an invented number.
          </p>
        </Block>

        <Block title="EU AI Act &amp; GDPR posture">
          <p>
            We build to the EU AI Act's original (August 2026) requirements and treat the later
            deferral as schedule margin, not permission to relax. Policy logic lives in
            configurable rules, not hard-coded branches, so we can adapt as guidance evolves.
            Personal data is EU-resident, consent-gated, and every consequential action is
            audited.
          </p>
        </Block>

        <Block title="Fit informs, never decides">
          <p>
            No score auto-rejects a candidate, auto-ranks to an action, or auto-grades an
            employee. Every consequential decision is made by a named human, recorded with
            rationale, and overridable. This is a GDPR Art. 22 + AI Act Art. 14 commitment, and
            it's enforced in the data model, not just the UI.
          </p>
        </Block>

        <Block title="The dev_stub discipline — why some numbers say 'placeholder'">
          <p>
            Throughout the platform you'll see values labelled <code>dev_stub</code>. This is
            deliberate honesty. It means: the engine that produces this value is built, but the
            underlying scientific calibration (validity coefficients, norms, fairness thresholds)
            is still pending expert sign-off. We refuse to present a placeholder as a validated
            result — to you or to your candidates. As the I/O psychologist and legal advisor close
            each item, the labels lift.
          </p>
        </Block>

        <Block title="Who stands behind this">
          <p className="text-muted">
            The methodology is implemented by the platform team and reviewed by an I/O
            psychologist and a legal advisor as those engagements formalise. Names and
            attributions will be listed here as each is confirmed — we won't list an advisor we
            don't have.
          </p>
        </Block>

        <div className="rounded-xl border border-line bg-surface p-6 text-center">
          <p className="font-display text-xl font-semibold">Questions about the methodology?</p>
          <p className="text-muted mt-1 text-sm">We're happy to go deep — that's the point.</p>
          <Link to="/contact" className="inline-block mt-4 bg-forest text-white rounded-lg px-5 py-2 text-sm hover:bg-forest/90">Get in touch</Link>
        </div>
      </article>
    </PublicLayout>
  )
}

function Block({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2">
      <h2 className="font-display text-2xl font-semibold">{title}</h2>
      <div className="text-ink/90 leading-relaxed space-y-2">{children}</div>
    </section>
  )
}
