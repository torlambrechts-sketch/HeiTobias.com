import { type ReactNode } from 'react'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { TemplateBanner } from '../../components/public/TemplateBanner.js'
import { usePlatformSettings } from '../../lib/usePlatformSettings.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /legal/terms — structured terms of service (TEMPLATE pending counsel).
// The "fit informs, never decides" architectural commitment appears here
// as a contractual term, and the data-side refusal taxonomy becomes
// acceptable-use restrictions on the customer side.

export function TermsOfServicePage() {
  usePageTitle('Terms of service')
  const settings = usePlatformSettings()
  return (
    <PublicLayout>
      <article className="max-w-3xl mx-auto px-5 py-12 flex flex-col gap-6">
        <header>
          <p className="text-xs uppercase tracking-wider text-muted font-bold">Legal</p>
          <h1 className="font-display text-4xl font-bold mt-1">Terms of service</h1>
          <p className="text-muted mt-2">The agreement governing use of HeiTobias.</p>
        </header>

        <TemplateBanner
          status={settings?.legal_review_status}
          reviewerName={settings?.legal_reviewer_name}
          reviewedAt={settings?.legal_reviewed_at}
        />

        <Section title="1. The service">
          <p>
            HeiTobias is a talent-lifecycle platform supporting hiring and post-hire development.
            It provides decision <em>support</em>: every fit score, model output, and
            recommendation <strong>informs a human decision and never makes one</strong>. The
            platform must not be used as an automated decision-maker for hiring or performance
            outcomes. This is a binding term, not merely a description.
          </p>
        </Section>

        <Section title="2. Accounts and responsibilities">
          <p>
            You are responsible for the accuracy of the data you enter, the lawful basis for
            processing the personal data of your candidates and employees, and the security of
            your account credentials.
          </p>
        </Section>

        <Section title="3. Acceptable use">
          <p>You agree not to:</p>
          <ul className="list-disc pl-5 space-y-1 mt-1">
            <li>Use the platform to screen or profile individuals on protected characteristics.</li>
            <li>Process personal data outside the consent purposes granted by the data subject.</li>
            <li>Attempt to re-identify anonymised data, or extract data beyond your RLS scope.</li>
            <li>Use any output as an automated reject / rank-to-action / performance verdict.</li>
            <li>Upload excluded instruments (e.g. MBTI, DISC, learning styles) as scored measures.</li>
          </ul>
        </Section>

        <Section title="4. Your data and content">
          <p>
            You retain ownership of the data you enter (role profiles, prep responses, notes).
            You grant us a limited licence to process it solely to provide the service. We claim
            no ownership of your customer data.
          </p>
        </Section>

        <Section title="5. Our intellectual property">
          <p>
            The platform software, the methodology implementation, the component and template
            systems, and the frameworks library are our intellectual property. The open-domain
            scientific methods we implement are, of course, not ours to own — and we cite them.
          </p>
        </Section>

        <Section title="6. Pricing and payment">
          <p className="rounded border border-line bg-canvas px-3 py-2 text-sm text-muted">
            <strong>Template pending commercialisation decisions.</strong> During the validation
            phase, design partners use the platform free of charge. Commercial pricing terms will
            be added here before any charges apply.
          </p>
        </Section>

        <Section title="7. Termination">
          <p>
            Either party may terminate per the agreed notice period. On termination, you may
            export your data; we delete or return it per the retention policy and applicable law.
          </p>
        </Section>

        <Section title="8. Limitation of liability">
          <p className="text-muted">
            [Template — counsel to complete.] To the extent permitted by law, our liability is
            limited as set out in the final, counsel-reviewed agreement.
          </p>
        </Section>

        <Section title="9. Governing law">
          <p>
            These terms are governed by Norwegian law for the Nordic launch, with provisions for
            EU customers to be finalised by counsel. Mandatory consumer / data-protection rights
            in your jurisdiction are unaffected.
          </p>
        </Section>

        <Section title="10. Disputes">
          <p className="text-muted">[Template — dispute-resolution mechanism to be set by counsel.]</p>
        </Section>

        <Section title="11. Contact">
          <p>
            Questions about these terms:{' '}
            <a className="text-role underline" href={`mailto:${settings?.support_email ?? 'support@heitobias.example'}`}>
              {settings?.support_email ?? 'support@heitobias.example'}
            </a>.
          </p>
        </Section>
      </article>
    </PublicLayout>
  )
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2">
      <h2 className="font-display text-xl font-semibold border-b border-line pb-1">{title}</h2>
      <div className="text-sm leading-relaxed text-ink/90 space-y-2">{children}</div>
    </section>
  )
}
