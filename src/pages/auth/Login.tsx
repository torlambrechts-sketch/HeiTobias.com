import { useCallback, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Loader2, LogIn, Mail } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { AuthLayout } from '../../components/public/AuthLayout.js'
import { Button } from '../../components/ui/button.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /login — email+password, magic-link alternative, links to signup +
// forgot-password. Rate limiting is enforced at the Supabase auth layer
// (configured in production hardening / AUTH-HARDENING.md). After login,
// redirect to /home.

export function LoginPage() {
  usePageTitle('Sign in')
  const supabase = browserSupabase()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [magicSent, setMagicSent] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  const signIn = useCallback(async (e: React.FormEvent) => {
    e.preventDefault()
    setBusy(true); setErr(null)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setBusy(false)
    if (error) { setErr(error.message); return }
    navigate('/home', { replace: true })
  }, [supabase, email, password, navigate])

  const magicLink = useCallback(async () => {
    if (!email) { setErr('Enter your email first.'); return }
    setBusy(true); setErr(null)
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/home` },
    })
    setBusy(false)
    if (error) { setErr(error.message); return }
    setMagicSent(true)
  }, [supabase, email])

  return (
    <AuthLayout
      title="Sign in"
      subtitle="Welcome back to HeiTobias."
      footer={<>New here? <Link className="text-role underline" to="/signup">Apply for a design-partner account</Link></>}
    >
      {magicSent ? (
        <div className="text-center flex flex-col items-center gap-3 py-4">
          <Mail size={28} className="text-forest" />
          <p className="text-sm">If <strong>{email}</strong> has an account, a one-time sign-in link is on its way.</p>
        </div>
      ) : (
        <form onSubmit={signIn} className="flex flex-col gap-3">
          {err && <div className="rounded border border-rust/40 bg-reject-bg p-2 text-xs text-rust">{err}</div>}
          <label className="flex flex-col gap-1">
            <span className="text-xs text-muted">Email</span>
            <input type="email" required value={email} onChange={e => setEmail(e.target.value)}
                   className="border border-line rounded px-3 py-2 text-sm bg-surface" />
          </label>
          <label className="flex flex-col gap-1">
            <div className="flex items-center justify-between">
              <span className="text-xs text-muted">Password</span>
              <Link to="/login/forgot-password" className="text-xs text-role hover:underline">Forgot password?</Link>
            </div>
            <input type="password" required value={password} onChange={e => setPassword(e.target.value)}
                   className="border border-line rounded px-3 py-2 text-sm bg-surface" />
          </label>
          <Button type="submit" disabled={busy || !email || !password}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <LogIn size={14} />} Sign in
          </Button>
          <div className="relative my-1 text-center">
            <span className="text-xs text-faint bg-surface px-2 relative z-10">or</span>
            <div className="absolute inset-x-0 top-1/2 border-t border-line" />
          </div>
          <Button type="button" variant="secondary" onClick={magicLink} disabled={busy || !email}>
            <Mail size={14} /> Email me a sign-in link
          </Button>
        </form>
      )}
    </AuthLayout>
  )
}
