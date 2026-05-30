import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Search } from 'lucide-react'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /docs — public FAQ with client-side search. Each answer links to the
// trust page where applicable. "Suggest an FAQ" → contact form.
//
// Content is honest: no fabricated numbers, citations where relevant,
// dev_stub discipline acknowledged.

type Faq = { q: string; a: React.ReactNode; category: string; keywords: string }

const FAQS: Faq[] = [
  {
    category: 'Methodology', q: 'What predicts job performance, according to HeiTobias?',
    keywords: 'predictor structured interview validity sackett gma cognitive',
    a: <>The strongest single predictor is a structured interview, with cognitive ability and
       structured assessments close behind (Sackett et al. 2022). We front-load structured prep
       rather than treating it as an afterthought. See the <Link className="text-role underline" to="/trust">methodology page</Link>.</>,
  },
  {
    category: 'Methodology', q: 'Why are trait targets ranges instead of "higher is better"?',
    keywords: 'trait target range band inverted-u conscientiousness',
    a: <>Because for many traits the relationship with performance is an inverted-U — too much is
       as much a problem as too little. Targets are bands with a direction and a justification.</>,
  },
  {
    category: 'Methodology', q: 'What does "dev_stub" mean when I see it?',
    keywords: 'dev stub placeholder validated pending sign-off honest',
    a: <>It means the engine that produces a value is built, but the underlying scientific
       calibration is still pending expert sign-off. We label it honestly rather than present a
       placeholder as validated.</>,
  },
  {
    category: 'Data handling', q: 'Where is my data stored?',
    keywords: 'data residency eu region gdpr storage',
    a: <>All personal data is processed and stored in the EU region. No transfers outside the EU/EEA.</>,
  },
  {
    category: 'Data handling', q: 'How do I get a copy of, or delete, my data?',
    keywords: 'dsr export delete erasure gdpr rights data subject',
    a: <>If you have an account, use <Link className="text-role underline" to="/me/privacy">My data &amp; privacy</Link>.
       Otherwise submit a <Link className="text-role underline" to="/privacy/request">data subject request</Link>.
       We respond within 30 days (GDPR Art. 12(3)).</>,
  },
  {
    category: 'Consent', q: 'What are the different consents I might be asked for?',
    keywords: 'consent purpose ladder hiring portability ongoing management',
    a: <>There's a layered, revocable consent ladder: <code>hiring_decision</code> during an
       active pipeline, <code>profile_portability</code> for cross-organisation transfer at
       placement, and <code>ongoing_management</code> for an employer manager's post-placement
       visibility. Each is separate and you can revoke any of them.</>,
  },
  {
    category: 'Fairness', q: 'Does the platform decide whether a result is "fair"?',
    keywords: 'fairness four-fifths adverse impact verdict expert',
    a: <>No. It computes fairness diagnostics (adverse-impact ratio, differential prediction, DIF)
       and surfaces them for a qualified human to interpret. The platform never declares a result
       "fair" — that's an expert and legal judgment.</>,
  },
  {
    category: 'Fairness', q: 'Can a score auto-reject a candidate?',
    keywords: 'auto decision human in the loop fit informs decides',
    a: <>Never. Fit informs, never decides. Every consequential action requires a named human's
       recorded, overridable decision (GDPR Art. 22 + AI Act Art. 14).</>,
  },
  {
    category: 'Pricing', q: 'How much does it cost?',
    keywords: 'pricing cost free design partner',
    a: <>Pricing is to be announced. Design partners use the platform free during the validation
       phase. <Link className="text-role underline" to="/contact">Apply to be a design partner.</Link></>,
  },
  {
    category: 'Technical', q: 'Do you use third-party tracking or analytics?',
    keywords: 'cookies tracking analytics privacy third party',
    a: <>No. Only strictly-necessary cookies (session + CSRF). No third-party tracking or
       advertising.</>,
  },
  {
    category: 'Getting started', q: 'How do I get access?',
    keywords: 'signup access design partner getting started',
    a: <>Request access via the <Link className="text-role underline" to="/signup">design-partner
       application</Link>. We review each application by hand at this stage.</>,
  },
]

export function DocsPage() {
  usePageTitle('FAQ')
  const [query, setQuery] = useState('')
  const results = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return FAQS
    return FAQS.filter(f =>
      f.q.toLowerCase().includes(q) || f.keywords.includes(q) || f.category.toLowerCase().includes(q))
  }, [query])

  const categories = useMemo(() => {
    const m = new Map<string, Faq[]>()
    for (const f of results) {
      if (!m.has(f.category)) m.set(f.category, [])
      m.get(f.category)!.push(f)
    }
    return Array.from(m.entries())
  }, [results])

  return (
    <PublicLayout active="docs">
      <div className="max-w-3xl mx-auto px-5 py-12">
        <header className="mb-6">
          <p className="text-xs uppercase tracking-wider text-forest font-bold">Help</p>
          <h1 className="font-display text-4xl font-bold mt-1">Frequently asked questions</h1>
        </header>

        <div className="flex items-center gap-2 border border-line rounded-lg px-3 py-2 bg-surface mb-6">
          <Search size={16} className="text-muted" />
          <input
            value={query}
            onChange={e => setQuery(e.target.value)}
            placeholder="Search the FAQ…"
            className="flex-1 bg-transparent text-sm outline-none"
            aria-label="Search FAQ"
          />
        </div>

        {categories.length === 0 && (
          <p className="text-sm text-muted">No FAQ matches "{query}". <Link className="text-role underline" to="/contact">Ask us directly.</Link></p>
        )}

        <div className="flex flex-col gap-8">
          {categories.map(([cat, items]) => (
            <section key={cat}>
              <h2 className="text-xs uppercase tracking-wider font-bold text-muted mb-2">{cat}</h2>
              <dl className="flex flex-col gap-4">
                {items.map((f, i) => (
                  <div key={i} className="border-b border-line pb-3">
                    <dt className="font-semibold">{f.q}</dt>
                    <dd className="text-sm text-ink/90 mt-1 leading-relaxed">{f.a}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ))}
        </div>

        <div className="mt-10 text-center text-sm text-muted">
          Didn't find your answer?{' '}
          <Link className="text-role underline" to="/contact">Suggest an FAQ or ask us directly.</Link>
        </div>
      </div>
    </PublicLayout>
  )
}
