import { type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { AlertTriangle, ExternalLink } from 'lucide-react'

// PublicShareFrame — the chrome around any token-shared artefact. Carries
// the mandatory watermark + a "request access" CTA. Used by both the
// public role preview and the public placement report.

export function PublicShareFrame({
  children,
  sharedByOrg,
  sharedAt,
  kind,
}: {
  children: ReactNode
  sharedByOrg?: string | undefined
  sharedAt?: string | undefined
  kind: string
}) {
  return (
    <div className="min-h-screen bg-canvas">
      <header className="border-b border-line bg-surface">
        <div className="max-w-3xl mx-auto px-5 h-14 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2 font-display font-bold">
            <span className="w-7 h-7 rounded bg-forest text-white flex items-center justify-center text-sm">T</span>
            HeiTobias
          </Link>
          <Link to="/signup" className="text-sm text-role hover:underline inline-flex items-center gap-1">
            Request platform access <ExternalLink size={13} />
          </Link>
        </div>
      </header>

      {/* Watermark notice */}
      <div className="max-w-3xl mx-auto px-5 pt-6">
        <div className="rounded-lg border border-amber/40 bg-internal-bg/40 px-4 py-2.5 text-xs text-ink flex items-start gap-2" data-test="share-watermark">
          <AlertTriangle size={15} className="text-amber flex-shrink-0 mt-0.5" />
          <span>
            Shared by <strong>{sharedByOrg ?? 'an organisation'}</strong> via HeiTobias
            {sharedAt ? ` on ${new Date(sharedAt).toLocaleDateString()}` : ''}. This is a working
            draft {kind} for stakeholder review — not a final decision artefact.
          </span>
        </div>
      </div>

      <main className="max-w-3xl mx-auto px-5 py-8">{children}</main>

      <footer className="max-w-3xl mx-auto px-5 py-10 border-t border-line mt-8 text-center">
        <p className="text-sm text-muted">Want the full picture, with your own roles and candidates?</p>
        <Link to="/signup" className="inline-block mt-3 bg-forest text-white rounded-lg px-5 py-2 text-sm hover:bg-forest/90">
          Request access to the platform
        </Link>
      </footer>
    </div>
  )
}

export function ShareError({ reason }: { reason?: string | undefined }) {
  const message =
    reason === 'expired' ? 'This share link has expired.'
    : reason === 'revoked' ? 'This share link has been revoked by its owner.'
    : reason === 'not_found' ? 'This share link is not valid.'
    : reason === 'gone' ? 'The shared item is no longer available.'
    : 'This shared item could not be loaded.'
  return (
    <div className="min-h-screen flex items-center justify-center px-4 bg-canvas">
      <div className="max-w-md text-center">
        <div className="w-14 h-14 mx-auto rounded-full bg-reject-bg flex items-center justify-center mb-3">
          <AlertTriangle size={24} className="text-rust" />
        </div>
        <h1 className="font-display text-2xl font-bold mb-2">Link unavailable</h1>
        <p className="text-sm text-muted">{message}</p>
        <Link to="/" className="inline-block mt-5 text-sm text-role hover:underline">← Go to HeiTobias</Link>
      </div>
    </div>
  )
}
