import { type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { TemplateBanner } from '../../components/public/TemplateBanner.js'
import { usePlatformSettings } from '../../lib/usePlatformSettings.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /legal/privacy — structured privacy policy.
//
// Content is a TEMPLATE pending legal review (banner on top, driven by
// platform_settings.legal_review_status). The structure follows GDPR
// Art. 13/14 disclosure requirements + the platform's consent purpose
// ladder. Contact details read from platform_settings_public().
//
// Discipline: no fabricated certainty. Where a value depends on
// expert/operator sign-off (retention periods → H-6), the text says so.

export function PrivacyPolicyPage() {
  usePageTitle('Privacy policy')
  const settings = usePlatformSettings()
  return (
    <PublicLayout>
      <article className="max-w-3xl mx-auto px-5 py-12 flex flex-col gap-6">
        <header>
          <p className="text-xs uppercase tracking-wider text-muted font-bold">Legal</p>
          <h1 className="font-display text-4xl font-bold mt-1">Privacy policy</h1>
          <p className="text-muted mt-2">How HeiTobias collects, uses, and protects personal data.</p>
        </header>

        <TemplateBanner
          status={settings?.legal_review_status}
          reviewerName={settings?.legal_reviewer_name}
          reviewedAt={settings?.legal_reviewed_at}
        />

        <Section title="1. Who we are (data controller)">
          <p>
            {settings?.platform_legal_entity_name ?? 'The platform operator (legal entity pending)'}
            {settings?.platform_legal_entity_address ? `, ${settings.platform_legal_entity_address}` : ''} operates
            HeiTobias. For data-protection enquiries contact our Data Protection Officer
            {settings?.dpo_contact_name ? ` (${settings.dpo_contact_name})` : ''} at{' '}
            <a className="text-role underline" href={`mailto:${settings?.dpo_contact_email ?? settings?.support_email ?? 'support@heitobias.example'}`}>
              {settings?.dpo_contact_email ?? settings?.support_email ?? 'support@heitobias.example'}
            </a>.
          </p>
        </Section>

        <Section title="2. What personal data we collect, and from whom">
          <ul className="list-disc pl-5 space-y-1">
            <li><strong>Organisation users</strong> (recruiters, hiring managers, admins): name, work email, role, organisation membership.</li>
            <li><strong>Candidates</strong>: name, email, assessment responses, structured-interview prep responses, consent records.</li>
            <li><strong>Employees</strong> (post-placement): the above plus re-fit and developmental data where consented.</li>
            <li><strong>External SMEs</strong> (Team Definition): name, email, organisation affiliation, their submitted role-definition ratings.</li>
          </ul>
        </Section>

        <Section title="3. Why we process it (purposes), and the consent ladder">
          <p>Personal data tied to candidates and employees is governed by an explicit, layered consent model. Each purpose is a separate, revocable grant:</p>
          <ul className="list-disc pl-5 space-y-1 mt-2">
            <li><strong>hiring_decision</strong> — processing during an active hiring pipeline.</li>
            <li><strong>profile_portability</strong> — explicit consent for cross-organisation transfer at placement.</li>
            <li><strong>ongoing_management</strong> — separate consent for an employer manager's ongoing visibility post-placement.</li>
            <li><strong>modeling_research</strong> — optional, separate consent for aggregate research; never required for service.</li>
          </ul>
          <p className="mt-2">
            The legal basis is your consent (GDPR Art. 6(1)(a)) for candidate/employee data, and
            legitimate interest (Art. 6(1)(f)) for the operation of an organisation's own user
            accounts.
          </p>
        </Section>

        <Section title="4. How long we keep it (retention)">
          <p>
            Retention periods are defined per data category in our retention policy. The exact
            windows are subject to operator and expert sign-off (internal reference: H-6
            compliance sign-off) and will be finalised before commercial launch. Audit and
            consent ledgers are retained for 7 years to demonstrate compliance (Art. 5(2)).
          </p>
          <p className="text-sm text-muted mt-2">
            See <Link className="text-role underline" to="/docs">our FAQ</Link> for the current
            retention summary.
          </p>
        </Section>

        <Section title="5. Who receives personal data">
          <p>
            Within your organisation, scoped by role and consent. Between organisations only via
            the explicit, consent-gated placement hand-off (agency → employer), and only when an
            active partnership exists. We do <strong>not</strong> sell personal data and do
            <strong> not</strong> share it with third parties for advertising.
          </p>
        </Section>

        <Section title="6. International transfers">
          <p>None. All personal data is processed and stored in the EU region. We do not transfer personal data outside the EU/EEA.</p>
        </Section>

        <Section title="7. Your rights">
          <p>You have the right to access, rectify, erase, restrict, port, and object to processing of your data.</p>
          <ul className="list-disc pl-5 space-y-1 mt-2">
            <li>If you have an account: <Link className="text-role underline" to="/me/privacy">manage your data and consents</Link>.</li>
            <li>If you do not have an account: <Link className="text-role underline" to="/privacy/request">submit a data-subject request</Link>.</li>
          </ul>
          <p className="mt-2">We respond within 30 days as required by GDPR Art. 12(3).</p>
        </Section>

        <Section title="8. Automated decisions">
          <p>
            HeiTobias does <strong>not</strong> make automated decisions with legal or similarly
            significant effects. Every consequential hiring or performance action requires a human
            decision (our "fit informs, never decides" commitment, GDPR Art. 22 + EU AI Act Art. 14).
          </p>
        </Section>

        <Section title="9. Cookies">
          <p>
            We use only strictly-necessary cookies: a session cookie and a CSRF-protection token.
            We do not use third-party tracking or advertising cookies.
          </p>
        </Section>

        <Section title="10. Children's data">
          <p>
            HeiTobias is not intended for, and we do not knowingly process data of, individuals
            under 16. If you believe a minor's data has been provided, contact us for removal.
          </p>
        </Section>

        <Section title="11. Changes to this policy">
          <p>
            Material changes are versioned and users are notified. Prior versions are available on
            request.
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
