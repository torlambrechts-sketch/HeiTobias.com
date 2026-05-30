import { Link } from 'react-router-dom'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { usePlatformSettings } from '../../lib/usePlatformSettings.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /accessibility — accessibility statement. The platform targets WCAG 2.1
// AA. A third-party audit is operator work, so the audit date/auditor
// line is a labelled template until that lands.
export function AccessibilityPage() {
  usePageTitle('Accessibility')
  const settings = usePlatformSettings()
  return (
    <PublicLayout>
      <article className="max-w-3xl mx-auto px-5 py-12 flex flex-col gap-6">
        <header>
          <p className="text-xs uppercase tracking-wider text-forest font-bold">Accessibility</p>
          <h1 className="font-display text-4xl font-bold mt-1">Accessibility statement</h1>
        </header>

        <section className="space-y-2 text-ink/90 leading-relaxed">
          <h2 className="font-display text-xl font-semibold">Our commitment</h2>
          <p>
            We are committed to meeting <strong>WCAG 2.1 Level AA</strong> across both the public
            site and the authenticated platform. Accessibility is treated as a defect class, not a
            nice-to-have: inaccessible animations, low-contrast text, or keyboard traps are bugs.
          </p>
        </section>

        <section className="space-y-2 text-ink/90 leading-relaxed">
          <h2 className="font-display text-xl font-semibold">Current status</h2>
          <ul className="list-disc pl-5 space-y-1">
            <li>Full keyboard navigation, with visible focus states and a skip-to-content link.</li>
            <li>Screen-reader labels on icon-only controls and form fields.</li>
            <li>Colour contrast checked against WCAG AA; org-chosen accent colours are warned at the source if they fall below 4.5:1.</li>
            <li>No keyboard traps in dialogs; status and error messages use appropriate ARIA roles.</li>
          </ul>
        </section>

        <section className="space-y-2 text-ink/90 leading-relaxed">
          <h2 className="font-display text-xl font-semibold">Known limitations</h2>
          <p className="text-muted">
            Some complex data visualisations (e.g. the re-fit trajectory) currently rely on
            colour + position; we are adding text alternatives. If you hit a barrier, please tell us
            — that report is the fastest path to a fix.
          </p>
        </section>

        <section className="space-y-2 text-ink/90 leading-relaxed">
          <h2 className="font-display text-xl font-semibold">EU directive posture</h2>
          <p>
            We track the EU 2025/2122 accessibility directive and build toward its requirements as
            part of our EU-first posture.
          </p>
        </section>

        <section className="rounded-lg border-2 border-amber/60 bg-internal-bg/40 px-4 py-3 text-sm">
          <strong>Pending third-party audit.</strong> A formal external accessibility audit is
          operator work and has not yet been completed. The audit date and auditor will be listed
          here once done.
        </section>

        <section className="space-y-2 text-ink/90 leading-relaxed">
          <h2 className="font-display text-xl font-semibold">Contact</h2>
          <p>
            Found an accessibility barrier? Email{' '}
            <a className="text-role underline" href={`mailto:${settings?.support_email ?? 'support@heitobias.example'}`}>
              {settings?.support_email ?? 'support@heitobias.example'}
            </a>{' '}or use the <Link className="text-role underline" to="/contact">contact form</Link>.
          </p>
        </section>
      </article>
    </PublicLayout>
  )
}
