import { useState } from 'react'
import { Loader2, Mail, ShieldCheck } from 'lucide-react'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { Card, CardBody } from '../../components/ui/card.js'
import { Button } from '../../components/ui/button.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /privacy/request — unauthenticated data-subject request.
//
// For people with no active account (former candidates, etc). Three steps:
//   1. enter email + request kind → POST /api/dsr/unauth {action:open}
//   2. verify ownership via magic link (token) → {action:verify}
//   3. see what data is held → {action:summary}
//
// Existence-leak discipline: step 1 always shows the same neutral message.
// In non-prod the API returns a dev token so the flow is walkable without
// SMTP; in prod the token is only emailed.

type Step = 'enter' | 'sent' | 'verified'

export function DsrRequestPage() {
  usePageTitle('Data subject request')
  const [step, setStep] = useState<Step>('enter')
  const [email, setEmail] = useState('')
  const [kind, setKind] = useState<'export' | 'erase'>('export')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [devToken, setDevToken] = useState<string | null>(null)
  const [tokenInput, setTokenInput] = useState('')
  const [summary, setSummary] = useState<Record<string, unknown> | null>(null)

  const post = async (body: Record<string, unknown>) => {
    const r = await fetch('/api/dsr/unauth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    return r.json() as Promise<Record<string, unknown>>
  }

  const open = async () => {
    setBusy(true); setErr(null)
    try {
      const res = await post({ action: 'open', email, kind })
      if (res.error) { setErr(String(res.error)); return }
      setDevToken((res.dev_verify_token as string) ?? null)
      setStep('sent')
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Request failed')
    } finally { setBusy(false) }
  }

  const verifyAndSummarise = async () => {
    setBusy(true); setErr(null)
    try {
      const token = tokenInput || devToken || ''
      const v = await post({ action: 'verify', token })
      if (!v.ok) { setErr(`Verification failed: ${String(v.reason ?? 'invalid token')}`); return }
      const s = await post({ action: 'summary', token })
      if (!s.ok) { setErr(`Could not load summary: ${String(s.reason ?? 'error')}`); return }
      setSummary(s)
      setStep('verified')
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Verification failed')
    } finally { setBusy(false) }
  }

  return (
    <PublicLayout>
      <div className="max-w-xl mx-auto px-5 py-12 flex flex-col gap-6">
        <header>
          <p className="text-xs uppercase tracking-wider text-muted font-bold">Your data rights</p>
          <h1 className="font-display text-3xl font-bold mt-1">Data subject request</h1>
          <p className="text-muted mt-2 text-sm">
            For people without an account. If you have an account,{' '}
            <a className="text-role underline" href="/me/privacy">manage your data here</a> instead.
          </p>
        </header>

        {err && <div className="rounded border border-rust/40 bg-reject-bg p-3 text-sm text-rust">{err}</div>}

        {step === 'enter' && (
          <Card><CardBody className="flex flex-col gap-4">
            <label className="flex flex-col gap-1">
              <span className="text-xs text-muted">Your email address</span>
              <input
                type="email"
                className="border border-line rounded px-3 py-2 text-sm bg-surface"
                value={email}
                onChange={e => setEmail(e.target.value)}
                placeholder="you@example.com"
              />
            </label>
            <fieldset className="flex flex-col gap-1">
              <legend className="text-xs text-muted mb-1">What would you like to do?</legend>
              <label className="flex items-center gap-2 text-sm">
                <input type="radio" name="kind" checked={kind === 'export'} onChange={() => setKind('export')} />
                Get a copy of my data (access — Art. 15)
              </label>
              <label className="flex items-center gap-2 text-sm">
                <input type="radio" name="kind" checked={kind === 'erase'} onChange={() => setKind('erase')} />
                Request erasure of my data (Art. 17)
              </label>
            </fieldset>
            <Button onClick={open} disabled={busy || !email}>
              {busy ? <Loader2 size={14} className="animate-spin" /> : <Mail size={14} />}
              Send verification link
            </Button>
            <p className="text-xs text-faint">
              We'll email a verification link to confirm you own this address before revealing any
              data. We respond to all requests within 30 days (GDPR Art. 12(3)).
            </p>
          </CardBody></Card>
        )}

        {step === 'sent' && (
          <Card><CardBody className="flex flex-col gap-4">
            <div className="flex items-center gap-2 text-ink">
              <ShieldCheck size={18} className="text-forest" />
              <p className="text-sm">
                If <strong>{email}</strong> is associated with data, a verification link has been
                sent. Click it to continue. (No account information is revealed until you verify.)
              </p>
            </div>
            {devToken && (
              <div className="rounded border border-amber/40 bg-internal-bg/40 p-3 text-xs">
                <strong>Dev mode:</strong> SMTP isn't wired in this environment, so here's your
                verification token to continue the flow.
                <div className="font-mono break-all mt-1">{devToken}</div>
              </div>
            )}
            <label className="flex flex-col gap-1">
              <span className="text-xs text-muted">Paste your verification token</span>
              <input
                className="border border-line rounded px-3 py-2 text-sm bg-surface font-mono"
                value={tokenInput}
                onChange={e => setTokenInput(e.target.value)}
                placeholder={devToken ?? 'token from your email'}
              />
            </label>
            <Button onClick={verifyAndSummarise} disabled={busy || (!tokenInput && !devToken)}>
              {busy ? <Loader2 size={14} className="animate-spin" /> : <ShieldCheck size={14} />}
              Verify and continue
            </Button>
          </CardBody></Card>
        )}

        {step === 'verified' && summary && (
          <Card><CardBody className="flex flex-col gap-3">
            <h2 className="font-display text-xl font-semibold">Verified</h2>
            {summary.data_held ? (
              <>
                <p className="text-sm text-muted">We hold the following data associated with your email:</p>
                <ul className="text-sm flex flex-col gap-1">
                  {Object.entries((summary.counts as Record<string, number>) ?? {}).map(([k, v]) => (
                    <li key={k} className="flex justify-between border-b border-line py-1">
                      <span className="text-muted">{k.replace(/_/g, ' ')}</span>
                      <span className="font-mono">{v}</span>
                    </li>
                  ))}
                </ul>
                <p className="text-sm text-ink mt-2">{String(summary.message)}</p>
              </>
            ) : (
              <p className="text-sm text-ink">{String(summary.message)}</p>
            )}
          </CardBody></Card>
        )}
      </div>
    </PublicLayout>
  )
}
