import { type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { LOCALES, useLocale, type Locale } from '../../lib/i18n.js'

// PublicLayout — the chrome for unauthenticated public surfaces
// (marketing, legal, contact, etc). Deliberately NOT the authenticated
// Shell: no icon rail, no org context, no notification bell. Just a
// slim header with the wordmark + nav, the content, and a full footer
// with legal links + locale switcher.
//
// Accessibility: skip-link, single <main> landmark, footer nav labelled.

export function PublicLayout({
  children,
  active,
}: {
  children: ReactNode
  active?: 'product' | 'trust' | 'about' | 'docs' | 'contact' | undefined
}) {
  return (
    <div className="min-h-screen flex flex-col bg-canvas text-ink">
      <a
        href="#public-main"
        className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:bg-forest focus:text-white focus:px-3 focus:py-2 focus:rounded"
      >
        Skip to main content
      </a>
      <PublicHeader active={active} />
      <main id="public-main" tabIndex={-1} className="flex-1 w-full">
        {children}
      </main>
      <PublicFooter />
    </div>
  )
}

function PublicHeader({ active }: { active?: string }) {
  const items: Array<{ to: string; label: string; key: string }> = [
    { to: '/trust', label: 'Methodology', key: 'trust' },
    { to: '/about', label: 'About', key: 'about' },
    { to: '/docs', label: 'FAQ', key: 'docs' },
    { to: '/contact', label: 'Contact', key: 'contact' },
  ]
  return (
    <header className="border-b border-line bg-surface/80 backdrop-blur sticky top-0 z-40">
      <div className="max-w-6xl mx-auto px-5 h-16 flex items-center gap-6">
        <Link to="/" className="flex items-center gap-2 font-display font-bold text-lg">
          <span className="w-8 h-8 rounded-lg bg-forest text-white flex items-center justify-center">T</span>
          HeiTobias
        </Link>
        <nav className="hidden md:flex items-center gap-5 ml-2" aria-label="Primary">
          {items.map(i => (
            <Link
              key={i.key}
              to={i.to}
              className={'text-sm hover:text-forest transition-colors ' + (active === i.key ? 'text-forest font-medium' : 'text-muted')}
            >
              {i.label}
            </Link>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-3">
          <Link to="/login" className="text-sm text-muted hover:text-ink">Sign in</Link>
          <Link to="/signup" className="text-sm bg-forest text-white rounded-lg px-3 py-1.5 hover:bg-forest/90">
            Request access
          </Link>
        </div>
      </div>
    </header>
  )
}

function PublicFooter() {
  const { locale, setLocale } = useLocale()
  const year = new Date().getFullYear()
  return (
    <footer className="border-t border-line bg-surface mt-16">
      <div className="max-w-6xl mx-auto px-5 py-10 grid grid-cols-2 md:grid-cols-4 gap-8 text-sm">
        <div>
          <p className="font-display font-bold mb-2">HeiTobias</p>
          <p className="text-faint text-xs leading-relaxed">
            Talent lifecycle, Nordic-first. Methodology-defensible, EU-resident,
            honest about what's validated.
          </p>
        </div>
        <FooterCol title="Product" links={[
          { to: '/', label: 'Overview' },
          { to: '/trust', label: 'Methodology' },
          { to: '/docs', label: 'FAQ' },
          { to: '/status', label: 'Status' },
        ]} />
        <FooterCol title="Company" links={[
          { to: '/about', label: 'About' },
          { to: '/contact', label: 'Contact' },
          { to: '/accessibility', label: 'Accessibility' },
        ]} />
        <FooterCol title="Legal" links={[
          { to: '/legal/privacy', label: 'Privacy policy' },
          { to: '/legal/terms', label: 'Terms of service' },
          { to: '/privacy/request', label: 'Data requests' },
        ]} />
      </div>
      <div className="border-t border-line">
        <div className="max-w-6xl mx-auto px-5 py-4 flex items-center justify-between gap-4 flex-wrap text-xs text-faint">
          <span>© {year} HeiTobias. All rights reserved.</span>
          <label className="flex items-center gap-2">
            <span className="sr-only">Language</span>
            <select
              value={locale}
              onChange={e => setLocale(e.target.value as Locale)}
              className="border border-line rounded px-2 py-1 bg-surface text-xs"
              aria-label="Language"
            >
              {LOCALES.map(l => <option key={l.code} value={l.code}>{l.nativeLabel}</option>)}
            </select>
          </label>
        </div>
      </div>
    </footer>
  )
}

function FooterCol({ title, links }: { title: string; links: Array<{ to: string; label: string }> }) {
  return (
    <div>
      <p className="font-semibold mb-2 text-xs uppercase tracking-wider text-muted">{title}</p>
      <ul className="flex flex-col gap-1.5">
        {links.map(l => (
          <li key={l.to}><Link to={l.to} className="text-muted hover:text-forest transition-colors">{l.label}</Link></li>
        ))}
      </ul>
    </div>
  )
}
