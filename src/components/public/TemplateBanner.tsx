import { AlertTriangle } from 'lucide-react'

// TemplateBanner — the prominent header on every legal page that is still
// pending counsel review. Per the public-surfaces principle B: removing
// this banner is itself an action requiring legal sign-off (a
// platform_admin flips platform_settings.legal_review_status to 'current'
// with a reviewer name, which hides this banner).
//
// `status` comes from platform_settings_public().legal_review_status. When
// 'current', the banner is replaced with a small reviewed-by line.
export function TemplateBanner({
  status,
  reviewerName,
  reviewedAt,
}: {
  status: 'pending' | 'current' | undefined
  reviewerName?: string | null
  reviewedAt?: string | null
}) {
  if (status === 'current') {
    return (
      <div className="rounded-lg border border-green/40 bg-green/5 px-4 py-2.5 text-sm text-ink flex items-center gap-2">
        <span className="text-green">✓</span>
        <span>
          Reviewed and approved{reviewerName ? ` by ${reviewerName}` : ''}
          {reviewedAt ? ` on ${new Date(reviewedAt).toLocaleDateString()}` : ''}.
        </span>
      </div>
    )
  }
  return (
    <div
      role="note"
      className="rounded-lg border-2 border-amber/60 bg-internal-bg/40 px-4 py-3 text-sm text-ink flex items-start gap-3"
      data-test="template-banner"
    >
      <AlertTriangle size={18} className="text-amber flex-shrink-0 mt-0.5" aria-hidden />
      <div>
        <strong className="block">TEMPLATE PENDING LEGAL REVIEW</strong>
        <span className="text-muted">
          This content is a structural draft and is <strong>not legally binding</strong> until
          reviewed and approved by counsel. Do not rely on it as a final legal document.
        </span>
      </div>
    </div>
  )
}
