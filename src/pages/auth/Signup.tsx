import { useCallback, useState } from 'react'
import { Link } from 'react-router-dom'
import { CheckCircle2, ChevronRight, Loader2 } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { AuthLayout } from '../../components/public/AuthLayout.js'
import { Button } from '../../components/ui/button.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /signup — multi-step design-partner application. Does NOT auto-provision
// an org. Step 1 creates the Supabase auth user (email verification
// configured in production hardening). Step 2 captures org basics + ToS
// acceptance. Step 3 records the application via signup_submit; a
// platform_admin reviews and provisions via platform_org_create.

type Step = 1 | 2 | 3 | 'done'

export function SignupPage() {
  usePageTitle('Request access')
  const supabase = browserSupabase()
  const [step, setStep] = useState<Step>(1)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  // Step 1
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  // Step 2
  const [name, setName] = useState('')
  const [orgName, setOrgName] = useState('')
  const [orgType, setOrgType] = useState<'agency' | 'employer' | 'hybrid'>('employer')
  const [country, setCountry] = useState('NO')
  const [locale, setLocale] = useState('nb-NO')
  const [size, setSize] = useState('small')
  const [acceptTos, setAcceptTos] = useState(false)
  const [acceptPrivacy, setAcceptPrivacy] = useState(false)
  // Step 3
  const [commercial, setCommercial] = useState(false)
  const [hp, setHp] = useState('')

  const pwStrong = password.length >= 12 && /[a-z]/.test(password) && /[A-Z]/.test(password) && /\d/.test(password)

  const doStep1 = useCallback(async (e: React.FormEvent) => {
    e.preventDefault()
    if (!pwStrong) { setErr('Password must be ≥12 chars with upper, lower, and a digit.'); return }
    setBusy(true); setErr(null)
    const { error } = await supabase.auth.signUp({
      email, password,
      options: { emailRedirectTo: `${window.location.origin}/login` },
    })
    setBusy(false)
    if (error) { setErr(error.message); return }
    setStep(2)
  }, [supabase, email, password, pwStrong])

  const doSubmit = useCallback(async () => {
    setBusy(true); setErr(null)
    const { data, error } = await supabase.rpc('signup_submit' as never, {
      p_email: email, p_name: name, p_org_name: orgName, p_org_type: orgType,
      p_country: country, p_locale: locale, p_size: size, p_commercial: commercial, p_hp: hp,
    } as never)
    setBusy(false)
    if (error) { setErr(error.message); return }
    if ((data as { ok?: boolean })?.ok) setStep('done')
  }, [supabase, email, name, orgName, orgType, country, locale, size, commercial, hp])

  return (
    <AuthLayout
      title="Request access"
      subtitle="Design partners use HeiTobias free during the validation phase."
      footer={step !== 'done' ? <>Already have an account? <Link className="text-role underline" to="/login">Sign in</Link></> : undefined}
    >
      {err && <div className="rounded border border-rust/40 bg-reject-bg p-2 text-xs text-rust mb-3">{err}</div>}

      {step !== 'done' && <StepBar step={step} />}

      {step === 1 && (
        <form onSubmit={doStep1} className="flex flex-col gap-3 mt-3">
          <label className="flex flex-col gap-1">
            <span className="text-xs text-muted">Work email</span>
            <input type="email" required value={email} onChange={e => setEmail(e.target.value)} className="border border-line rounded px-3 py-2 text-sm bg-surface" />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs text-muted">Password</span>
            <input type="password" required value={password} onChange={e => setPassword(e.target.value)} className="border border-line rounded px-3 py-2 text-sm bg-surface" />
            <span className={'text-[11px] ' + (pwStrong ? 'text-green' : 'text-faint')}>
              {pwStrong ? '✓ Strong enough' : 'At least 12 characters, with upper, lower, and a digit.'}
            </span>
          </label>
          <Button type="submit" disabled={busy || !email || !pwStrong}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <ChevronRight size={14} />} Continue
          </Button>
          <p className="text-[11px] text-faint">We'll send a verification email. You can complete the next steps right away.</p>
        </form>
      )}

      {step === 2 && (
        <div className="flex flex-col gap-3 mt-3">
          <label className="flex flex-col gap-1">
            <span className="text-xs text-muted">Your name</span>
            <input value={name} onChange={e => setName(e.target.value)} className="border border-line rounded px-3 py-2 text-sm bg-surface" />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs text-muted">Organisation legal name</span>
            <input value={orgName} onChange={e => setOrgName(e.target.value)} className="border border-line rounded px-3 py-2 text-sm bg-surface" />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs text-muted">Organisation type</span>
            <select value={orgType} onChange={e => setOrgType(e.target.value as typeof orgType)} className="border border-line rounded px-3 py-2 text-sm bg-surface">
              <option value="employer">Employer</option>
              <option value="agency">Recruitment agency</option>
              <option value="hybrid">Hybrid</option>
            </select>
          </label>
          <div className="grid grid-cols-3 gap-2">
            <label className="flex flex-col gap-1">
              <span className="text-xs text-muted">Country</span>
              <input value={country} onChange={e => setCountry(e.target.value.slice(0,2).toUpperCase())} maxLength={2} className="border border-line rounded px-3 py-2 text-sm bg-surface uppercase" />
            </label>
            <label className="flex flex-col gap-1">
              <span className="text-xs text-muted">Locale</span>
              <select value={locale} onChange={e => setLocale(e.target.value)} className="border border-line rounded px-3 py-2 text-sm bg-surface">
                <option value="nb-NO">nb-NO</option><option value="sv-SE">sv-SE</option><option value="da-DK">da-DK</option><option value="en">en</option>
              </select>
            </label>
            <label className="flex flex-col gap-1">
              <span className="text-xs text-muted">Size</span>
              <select value={size} onChange={e => setSize(e.target.value)} className="border border-line rounded px-3 py-2 text-sm bg-surface">
                <option value="small">Small</option><option value="medium">Medium</option><option value="large">Large</option>
              </select>
            </label>
          </div>
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" checked={acceptTos} onChange={e => setAcceptTos(e.target.checked)} className="mt-0.5" />
            <span>I accept the <Link className="text-role underline" to="/legal/terms" target="_blank">terms of service</Link>.</span>
          </label>
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" checked={acceptPrivacy} onChange={e => setAcceptPrivacy(e.target.checked)} className="mt-0.5" />
            <span>I accept the <Link className="text-role underline" to="/legal/privacy" target="_blank">privacy policy</Link>.</span>
          </label>
          <Button onClick={() => setStep(3)} disabled={!name || orgName.length < 2 || !acceptTos || !acceptPrivacy}>
            <ChevronRight size={14} /> Continue
          </Button>
        </div>
      )}

      {step === 3 && (
        <div className="flex flex-col gap-3 mt-3">
          <p className="text-sm text-muted">How would you like to engage?</p>
          <label className={'border rounded-lg p-3 cursor-pointer ' + (!commercial ? 'border-forest bg-canvas-2' : 'border-line')}>
            <input type="radio" name="engage" checked={!commercial} onChange={() => setCommercial(false)} className="mr-2" />
            <strong>Apply to be a design partner</strong>
            <p className="text-xs text-muted mt-1 ml-5">Free during the validation phase. We hand-select design partners.</p>
          </label>
          <label className={'border rounded-lg p-3 cursor-pointer ' + (commercial ? 'border-forest bg-canvas-2' : 'border-line')}>
            <input type="radio" name="engage" checked={commercial} onChange={() => setCommercial(true)} className="mr-2" />
            <strong>Request commercial pricing</strong>
            <p className="text-xs text-muted mt-1 ml-5">We'll be in touch about commercial terms.</p>
          </label>
          <input type="text" tabIndex={-1} autoComplete="off" value={hp} onChange={e => setHp(e.target.value)} className="absolute -left-[9999px]" aria-hidden="true" />
          <Button onClick={doSubmit} disabled={busy}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <CheckCircle2 size={14} />} Submit application
          </Button>
        </div>
      )}

      {step === 'done' && (
        <div className="flex flex-col items-center text-center gap-3 py-4">
          <CheckCircle2 size={32} className="text-green" />
          <h2 className="font-display text-xl font-semibold">Application received</h2>
          <p className="text-sm text-muted">
            We review each application by hand and respond within 2 business days. Once approved,
            you'll get an activation email to set up your workspace. Verify your email address in
            the meantime.
          </p>
          <Link to="/" className="text-sm text-role hover:underline mt-2">Back to home</Link>
        </div>
      )}
    </AuthLayout>
  )
}

function StepBar({ step }: { step: 1 | 2 | 3 }) {
  return (
    <div className="flex items-center gap-2" aria-hidden>
      {[1, 2, 3].map(n => (
        <div key={n} className={'h-1.5 flex-1 rounded-full ' + (n <= step ? 'bg-forest' : 'bg-line')} />
      ))}
    </div>
  )
}
