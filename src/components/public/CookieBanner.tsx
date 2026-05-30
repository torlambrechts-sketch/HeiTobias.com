import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Cookie } from 'lucide-react'

// Minimal cookie consent banner. The platform uses only strictly-
// necessary cookies (session + CSRF), so this is a notice, not a
// consent gate — there are no non-essential cookies to gate. We record
// acknowledgement in a first-party cookie (not localStorage, per the
// CLAUDE.md no-browser-storage-for-sensitive-data rule; this value is
// not sensitive, but a cookie is the natural home for "saw the notice").
//
// If/when analytics are added, this banner must grow a real consent
// choice. Today it's an acknowledgement only.

const COOKIE_NAME = 'ht_cookie_notice_ack'

function hasAck(): boolean {
  if (typeof document === 'undefined') return true
  return document.cookie.split('; ').some(c => c.startsWith(`${COOKIE_NAME}=`))
}

function setAck(): void {
  // 1 year, SameSite=Lax, path=/. Not HttpOnly (the client needs to read it).
  const oneYear = 60 * 60 * 24 * 365
  document.cookie = `${COOKIE_NAME}=1; Max-Age=${oneYear}; Path=/; SameSite=Lax`
}

export function CookieBanner() {
  const [visible, setVisible] = useState(false)
  useEffect(() => { setVisible(!hasAck()) }, [])
  if (!visible) return null
  return (
    <div
      role="region"
      aria-label="Cookie notice"
      className="fixed bottom-0 inset-x-0 z-50 border-t border-line bg-surface shadow-hard"
    >
      <div className="max-w-4xl mx-auto px-5 py-3 flex items-center gap-4 flex-wrap">
        <Cookie size={18} className="text-muted flex-shrink-0" aria-hidden />
        <p className="text-sm text-ink flex-1 min-w-[240px]">
          We use only strictly-necessary cookies (a session cookie and a CSRF token). No tracking,
          no advertising.{' '}
          <Link to="/legal/privacy" className="text-role underline">Learn more</Link>.
        </p>
        <button
          type="button"
          onClick={() => { setAck(); setVisible(false) }}
          className="bg-forest text-white rounded-lg px-4 py-1.5 text-sm hover:bg-forest/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-forest/40"
        >
          Got it
        </button>
      </div>
    </div>
  )
}
