import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { CheckCircle2, Loader2 } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { AuthLayout } from '../../components/public/AuthLayout.js'
import { Button } from '../../components/ui/button.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /login/reset-password/:token — the landing for a password-reset link.
// Supabase puts the recovery session in the URL hash and fires a
// PASSWORD_RECOVERY auth event; once we're in that state, the user sets a
// new password via updateUser. We then sign them out so they log in fresh.

export function ResetPasswordPage() {
  usePageTitle('Set a new password')
  const supabase = browserSupabase()
  const navigate = useNavigate()
  const [ready, setReady] = useState(false)
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [done, setDone] = useState(false)

  useEffect(() => {
    // The recovery link establishes a session. If one exists (or the
    // PASSWORD_RECOVERY event fires), we're ready to set a new password.
    void supabase.auth.getSession().then(({ data }) => { if (data.session) setReady(true) })
    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'PASSWORD_RECOVERY' || event === 'SIGNED_IN') setReady(true)
    })
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  const pwStrong = password.length >= 12 && /[a-z]/.test(password) && /[A-Z]/.test(password) && /\d/.test(password)

  const submit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault()
    if (!pwStrong) { setErr('Password must be ≥12 chars with upper, lower, and a digit.'); return }
    if (password !== confirm) { setErr('Passwords do not match.'); return }
    setBusy(true); setErr(null)
    const { error } = await supabase.auth.updateUser({ password })
    setBusy(false)
    if (error) { setErr(error.message); return }
    await supabase.auth.signOut()
    setDone(true)
    setTimeout(() => navigate('/login', { replace: true }), 2500)
  }, [supabase, password, confirm, pwStrong, navigate])

  return (
    <AuthLayout title="Set a new password" footer={<Link className="text-role underline" to="/login">Back to sign in</Link>}>
      {done ? (
        <div className="text-center flex flex-col items-center gap-3 py-4">
          <CheckCircle2 size={28} className="text-green" />
          <p className="text-sm">Your password has been reset. Redirecting you to sign in…</p>
        </div>
      ) : !ready ? (
        <div className="text-center text-sm text-muted py-6">
          <Loader2 size={18} className="animate-spin mx-auto mb-2" />
          Waiting for a valid reset link. If you arrived here without clicking a reset email,
          <Link to="/login/forgot-password" className="text-role underline ml-1">request one</Link>.
        </div>
      ) : (
        <form onSubmit={submit} className="flex flex-col gap-3">
          {err && <div className="rounded border border-rust/40 bg-reject-bg p-2 text-xs text-rust">{err}</div>}
          <label className="flex flex-col gap-1">
            <span className="text-xs text-muted">New password</span>
            <input type="password" required value={password} onChange={e => setPassword(e.target.value)} className="border border-line rounded px-3 py-2 text-sm bg-surface" />
            <span className={'text-[11px] ' + (pwStrong ? 'text-green' : 'text-faint')}>
              {pwStrong ? '✓ Strong enough' : 'At least 12 characters, with upper, lower, and a digit.'}
            </span>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs text-muted">Confirm new password</span>
            <input type="password" required value={confirm} onChange={e => setConfirm(e.target.value)} className="border border-line rounded px-3 py-2 text-sm bg-surface" />
          </label>
          <Button type="submit" disabled={busy || !pwStrong || password !== confirm}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : null} Set new password
          </Button>
        </form>
      )}
    </AuthLayout>
  )
}
