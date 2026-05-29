import { useCallback, useState } from 'react'
import { Loader2 } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { env } from '../lib/env.js'
import { Button } from './ui/button.js'

// Dev-only sign-in helper. Pages used to hardcode demo credentials in
// production code paths ("Sign in as Linnea (demo)"). Those credentials
// must NEVER reach a production build, so they now live here behind an
// env().isProd check that returns null in production.
//
// The component renders nothing in production. In dev/staging it
// renders a small button that signs into the demo persona.

export const DEMO_PERSONAS = [
  { email: 'linnea.strand@fjordtech.test',      label: 'Linnea Strand — FjordTech people_ops_admin' },
  { email: 'astrid.berg@nordic-recruit.test',   label: 'Astrid Berg — Nordic Recruit org_admin' },
  { email: 'magnus.holm@nordic-recruit.test',   label: 'Magnus Holm — recruiter' },
  { email: 'erik.lund@fjordtech.test',          label: 'Erik Lund — hiring_manager' },
  { email: 'sara.vik@fjordtech.test',           label: 'Sara Vik — manager' },
  { email: 'jonas.dahl@fjordtech.test',         label: 'Jonas Dahl — employee' },
] as const

export type DemoPersonaEmail = typeof DEMO_PERSONAS[number]['email']

export function DevOnlySignIn({ email = 'linnea.strand@fjordtech.test', label }: { email?: DemoPersonaEmail; label?: string }) {
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const supabase = browserSupabase()
  const signIn = useCallback(async () => {
    setBusy(true); setErr(null)
    const { error } = await supabase.auth.signInWithPassword({ email, password: 'demo' })
    setBusy(false)
    if (error) setErr(error.message)
  }, [supabase, email])

  if (env().isProd) return null

  return (
    <div className="rounded border border-amber/40 bg-internal-bg/40 p-3 text-sm">
      <div className="text-[10.5px] uppercase tracking-wider font-bold text-internal-fg mb-2">
        Dev-only sign-in
      </div>
      <Button onClick={signIn} disabled={busy}>
        {busy ? <Loader2 size={14} className="animate-spin" /> : null}
        {label ?? `Sign in as ${email.split('@')[0]} (demo)`}
      </Button>
      {err && <div className="mt-2 text-xs text-rust">{err}</div>}
      <div className="mt-2 text-[10.5px] text-internal-fg/80">
        Hidden in production builds (NODE_ENV=production).
      </div>
    </div>
  )
}
