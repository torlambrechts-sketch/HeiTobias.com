import { useState } from 'react'
import { CheckCircle2, Loader2, Send } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { PublicLayout } from '../../components/public/PublicLayout.js'
import { Card, CardBody } from '../../components/ui/card.js'
import { Button } from '../../components/ui/button.js'
import { usePageTitle } from '../../lib/usePageTitle.js'

// /contact — demo request form. Writes to contact_requests via the anon
// contact_request_submit RPC (honeypot + rate-limit inside). The "2
// business days" line is the founder's real commitment, not a fabricated
// SLA — keep it accurate.

export function ContactPage() {
  usePageTitle('Contact')
  const supabase = browserSupabase()
  const [sent, setSent] = useState(false)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [form, setForm] = useState({
    name: '', email: '', organization: '', role: '', interest: 'employer', message: '',
  })
  const [hp, setHp] = useState('') // honeypot

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setBusy(true); setErr(null)
    const { data, error } = await supabase.rpc('contact_request_submit' as never, {
      p_kind: 'demo',
      p_name: form.name,
      p_email: form.email,
      p_organization: form.organization || null,
      p_role: form.role || null,
      p_interest: form.interest,
      p_message: form.message || null,
      p_payload: {},
      p_hp: hp,
    } as never)
    setBusy(false)
    if (error) { setErr(error.message); return }
    if ((data as { ok?: boolean })?.ok) setSent(true)
  }

  return (
    <PublicLayout active="contact">
      <div className="max-w-xl mx-auto px-5 py-12">
        <header className="mb-6">
          <p className="text-xs uppercase tracking-wider text-forest font-bold">Contact</p>
          <h1 className="font-display text-3xl font-bold mt-1">Request a demo</h1>
          <p className="text-muted mt-2 text-sm">
            Tell us a little about your context and we'll show you the platform on your own roles.
          </p>
        </header>

        {sent ? (
          <Card><CardBody className="flex flex-col items-center text-center gap-3 py-10">
            <CheckCircle2 size={32} className="text-green" />
            <h2 className="font-display text-xl font-semibold">Thank you — we've got it</h2>
            <p className="text-sm text-muted max-w-sm">
              We respond to demo requests within 2 business days. (That's our actual commitment,
              not a marketing number.)
            </p>
          </CardBody></Card>
        ) : (
          <Card><CardBody>
            <form onSubmit={submit} className="flex flex-col gap-3">
              {err && <div className="rounded border border-rust/40 bg-reject-bg p-2 text-xs text-rust">{err}</div>}
              <Field label="Name" required value={form.name} onChange={v => setForm({ ...form, name: v })} />
              <Field label="Email" type="email" required value={form.email} onChange={v => setForm({ ...form, email: v })} />
              <Field label="Organisation" value={form.organization} onChange={v => setForm({ ...form, organization: v })} />
              <Field label="Your role" value={form.role} onChange={v => setForm({ ...form, role: v })} />
              <label className="flex flex-col gap-1">
                <span className="text-xs text-muted">I'm interested as a…</span>
                <select className="border border-line rounded px-3 py-2 text-sm bg-surface" value={form.interest} onChange={e => setForm({ ...form, interest: e.target.value })}>
                  <option value="agency">Recruitment agency</option>
                  <option value="employer">Employer</option>
                  <option value="academic">Academic / researcher</option>
                  <option value="press">Press</option>
                  <option value="other">Other</option>
                </select>
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-xs text-muted">What would you like to see?</span>
                <textarea className="border border-line rounded px-3 py-2 text-sm font-body" rows={4} value={form.message} onChange={e => setForm({ ...form, message: e.target.value })} />
              </label>
              {/* Honeypot — hidden from humans, bots fill it. */}
              <input
                type="text" tabIndex={-1} autoComplete="off" value={hp} onChange={e => setHp(e.target.value)}
                className="absolute -left-[9999px]" aria-hidden="true"
              />
              <Button type="submit" disabled={busy || !form.name || !form.email}>
                {busy ? <Loader2 size={14} className="animate-spin" /> : <Send size={14} />} Send request
              </Button>
              <p className="text-xs text-faint">
                We respond within 2 business days. By submitting you agree to our{' '}
                <a className="text-role underline" href="/legal/privacy">privacy policy</a>.
              </p>
            </form>
          </CardBody></Card>
        )}
      </div>
    </PublicLayout>
  )
}

function Field({ label, value, onChange, type = 'text', required = false }: {
  label: string; value: string; onChange: (v: string) => void; type?: string; required?: boolean
}) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-xs text-muted">{label}{required && ' *'}</span>
      <input
        type={type} required={required} value={value} onChange={e => onChange(e.target.value)}
        className="border border-line rounded px-3 py-2 text-sm bg-surface"
      />
    </label>
  )
}
