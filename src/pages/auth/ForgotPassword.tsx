import { useCallback, useState } from 'react'
import { Link } from 'react-router-dom'
import { Loader2, Mail } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { AuthLayout } from '../../components/public/AuthLayout.js'
import { Button } from '../../components/ui/button.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /login/forgot-password — sends a Supabase password-reset email. The
// reset link lands on /login/reset-password/:token (handled by Supabase's
// recovery flow). We always show the same neutral message (no existence
// leak).

export function ForgotPasswordPage() {
  usePageTitle('Reset your password')
  const supabase = browserSupabase()
  const [email, setEmail] = useState('')
  const [busy, setBusy] = useState(false)
  const [sent, setSent] = useState(false)

  const submit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault()
    setBusy(true)
    await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/login/reset-password/recovery`,
    })
    setBusy(false)
    setSent(true)  // always — neutral response
  }, [supabase, email])

  return (
    <AuthLayout
      title="Reset your password"
      footer={<Link className="text-role underline" to="/login">Back to sign in</Link>}
    >
      {sent ? (
        <div className="text-center flex flex-col items-center gap-3 py-4">
          <Mail size={28} className="text-forest" />
          <p className="text-sm">
            If <strong>{email}</strong> has an account, a password-reset link has been sent. Check
            your inbox.
          </p>
        </div>
      ) : (
        <form onSubmit={submit} className="flex flex-col gap-3">
          <label className="flex flex-col gap-1">
            <span className="text-xs text-muted">Your email</span>
            <input type="email" required value={email} onChange={e => setEmail(e.target.value)} className="border border-line rounded px-3 py-2 text-sm bg-surface" />
          </label>
          <Button type="submit" disabled={busy || !email}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <Mail size={14} />} Send reset link
          </Button>
        </form>
      )}
    </AuthLayout>
  )
}
