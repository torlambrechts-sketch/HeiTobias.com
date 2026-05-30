import { type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { usePlatformSettings } from '../../lib/usePlatformSettings.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /about — company page. Placeholder structured copy (refine after
// customer conversations) but honest: lists only what exists, includes
// an "open questions" section consistent with the platform's honesty
// discipline.

export function AboutPage() {
  usePageTitle('About')
  const settings = usePlatformSettings()
  return (
    <PublicLayout active="about">
      <article className="max-w-3xl mx-auto px-5 py-12 flex flex-col gap-8">
        <header>
          <p className="text-xs uppercase tracking-wider text-forest font-bold">About</p>
          <h1 className="font-display text-4xl font-bold mt-1">Deliberately slow, deliberately correct</h1>
        </header>

        <Block title="Mission">
          <p>
            Hiring and talent decisions shape people's lives. They deserve tools that are honest
            about their evidence base, that keep a human in the loop, and that treat the data
            subject as the owner of their own data. HeiTobias is our attempt to build that for the
            Nordic market first.
          </p>
          <p className="text-sm text-muted">
            This copy is an early draft and will sharpen as we learn from design partners.
          </p>
        </Block>

        <Block title="Approach">
          <ul className="list-disc pl-5 space-y-1">
            <li><strong>Nordic-first.</strong> Built for Norwegian, Swedish, and Danish contexts, with localisation from day one.</li>
            <li><strong>Methodology-defensible.</strong> Open-domain instruments, citation-grounded, inspectable.</li>
            <li><strong>Deliberately slow.</strong> We'd rather ship a clearly-labelled placeholder than a fabricated number.</li>
          </ul>
        </Block>

        <Block title="Team">
          <p>
            Currently founder-led. As we engage an I/O psychologist and a legal advisor for the
            science and compliance sign-offs, we'll name them here — we don't list advisors we
            don't have.
          </p>
        </Block>

        <Block title="Open questions we're grappling with">
          <p className="text-sm text-muted">
            Unusual for a SaaS landing, but consistent with our honesty discipline. These are real:
          </p>
          <ul className="list-disc pl-5 space-y-1 mt-2">
            <li>How to collect robust Nordic norms ethically and at sufficient scale.</li>
            <li>How to present fairness diagnostics so they inform rather than mislead non-experts.</li>
            <li>Where the line sits between helpful manager guidance and overreach.</li>
          </ul>
        </Block>

        <Block title="Contact">
          <p>
            General enquiries:{' '}
            <a className="text-role underline" href={`mailto:${settings?.support_email ?? 'support@heitobias.example'}`}>
              {settings?.support_email ?? 'support@heitobias.example'}
            </a>. Or <Link className="text-role underline" to="/contact">request a demo</Link>.
          </p>
        </Block>
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
