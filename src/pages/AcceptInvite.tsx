import { useCallback, useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { CheckCircle2, Loader2, Mail, ShieldCheck } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'
import { LOCALES, useLocale, type Locale } from '../lib/i18n.js'

type InviteState = {
  invited_email: string
  org_id: string
  org_name: string
  org_settings: { logo_url?: string; accent_color?: string } | null
  membership_id: string
  expires_at: string
}

export function AcceptInvitePage() {
  const { token } = useParams<{ token: string }>()
  const navigate = useNavigate()
  const supabase = browserSupabase()
  const [signedInEmail, setSignedInEmail] = useState<string | null>(null)
  const [state, setState] = useState<InviteState | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [accepted, setAccepted] = useState(false)
  const [displayName, setDisplayName] = useState('')
  const { locale, setLocale } = useLocale()

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedInEmail(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedInEmail(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  useEffect(() => {
    if (!token) return
    void (async () => {
      const { data, error } = await supabase.rpc('org_invite_state' as never, { p_token: token } as never)
      if (error) { setErr(error.message); return }
      setState(data as unknown as InviteState)
    })()
  }, [supabase, token])

  const accept = useCallback(async () => {
    if (!token) return
    setBusy(true); setErr(null)
    const { error } = await supabase.rpc('org_invite_accept_v2' as never, {
      p_token: token,
      p_display_name: displayName.trim() || null,
      p_locale: locale,
    } as never)
    setBusy(false)
    if (error) { setErr(error.message); return }
    setAccepted(true)
    setTimeout(() => navigate('/admin'), 1500)
  }, [supabase, token, displayName, locale, navigate])

  const matchesSignIn = state && signedInEmail && state.invited_email.toLowerCase() === signedInEmail.toLowerCase()

  return (
    <div className="min-h-screen bg-canvas flex items-center justify-center p-8">
      <div className="max-w-lg w-full">
        <Card>
          <CardEyebrow><Mail size={12} /> Workspace invitation</CardEyebrow>
          <CardTitle>{state ? `Join ${state.org_name}` : 'Invitation'}</CardTitle>
          <CardBody>
            {err && <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-900 mb-4">{err}</div>}
            {accepted && (
              <div className="rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-900 mb-4 flex items-center gap-2">
                <CheckCircle2 size={14} /> Joined — redirecting to the workspace…
              </div>
            )}
            {!state && !err && (
              <div className="flex items-center gap-2 text-faint"><Loader2 size={14} className="animate-spin" /> Loading invitation…</div>
            )}
            {state && !accepted && (
              <div className="flex flex-col gap-4">
                <div className="text-sm text-ink">
                  You've been invited to join <strong>{state.org_name}</strong> as the user
                  <span className="font-mono text-role"> {state.invited_email}</span>.
                </div>
                <div className="text-xs text-faint">
                  This invitation expires {new Date(state.expires_at).toLocaleString()}.
                </div>
                {!signedInEmail && (
                  <div className="rounded-lg border border-line bg-canvas-2/50 p-3 text-sm">
                    <p className="font-semibold mb-1">Sign in first</p>
                    <p className="text-faint text-xs mb-2">Use the email <strong>{state.invited_email}</strong> when you sign in (or sign up). Then return to this page and click <em>Accept invitation</em>.</p>
                    <Button onClick={() => navigate(`/?next=${encodeURIComponent(window.location.pathname)}`)}>Go to sign-in</Button>
                  </div>
                )}
                {signedInEmail && !matchesSignIn && (
                  <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
                    You're signed in as <code>{signedInEmail}</code>, but the invitation is for <code>{state.invited_email}</code>. Sign out and back in with the matching email.
                  </div>
                )}
                {signedInEmail && matchesSignIn && (
                  <div className="flex flex-col gap-3">
                    <label className="flex flex-col gap-1">
                      <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Display name</span>
                      <input
                        value={displayName}
                        onChange={e => setDisplayName(e.target.value)}
                        placeholder="How others should see your name"
                        className="border border-line rounded px-3 py-2 text-sm bg-surface"
                      />
                    </label>
                    <label className="flex flex-col gap-1">
                      <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Language</span>
                      <select
                        value={locale}
                        onChange={e => setLocale(e.target.value as Locale)}
                        className="border border-line rounded px-3 py-2 text-sm bg-surface"
                      >
                        {LOCALES.map(l => <option key={l.code} value={l.code}>{l.nativeLabel}</option>)}
                      </select>
                    </label>
                    <div>
                      <Button onClick={accept} disabled={busy}>
                        {busy ? <Loader2 size={14} className="animate-spin" /> : <ShieldCheck size={14} />} Accept invitation
                      </Button>
                    </div>
                  </div>
                )}
                <div className="flex items-center gap-2 pt-2 border-t border-line">
                  <Pill>EU-region hosting</Pill>
                  <Pill>Consent-gated</Pill>
                </div>
              </div>
            )}
          </CardBody>
        </Card>
      </div>
    </div>
  )
}
