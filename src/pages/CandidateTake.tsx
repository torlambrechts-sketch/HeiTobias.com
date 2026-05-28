import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Check, ChevronRight, Loader2 } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Button } from '../components/ui/button.js'
import { Card, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { ValidityChip } from '../components/ui/badges.js'

type Item = {
  id: string
  key: string
  prompt: string
  type: string
  choices: number[] | null
  scale: string | null
  _dev_stub: boolean
  answered: boolean
}

type TakeState = {
  invite_id: string
  assessment_id: string
  instrument_key: string
  instrument_name: string
  validity_status: 'dev_stub' | 'licensed' | 'validated'
  consent_captured: boolean
  completed: boolean
  used: boolean
  expires_at: string
  items: Item[]
}

type Phase = 'loading' | 'error' | 'consent' | 'item' | 'done'

export function CandidateTakePage() {
  const { token } = useParams<{ token: string }>()
  const supabase = browserSupabase()

  const [state, setState] = useState<TakeState | null>(null)
  const [errMsg, setErrMsg] = useState<string | null>(null)
  const [phase, setPhase] = useState<Phase>('loading')
  const [submitting, setSubmitting] = useState(false)

  const load = useCallback(async () => {
    if (!token) {
      setErrMsg('Missing invite token in URL.')
      setPhase('error')
      return
    }
    const { data, error } = await supabase.rpc('assessment_take_state', { p_token: token })
    if (error) {
      setErrMsg(error.message)
      setPhase('error')
      return
    }
    const s = data as unknown as TakeState
    setState(s)
    if (s.completed) setPhase('done')
    else if (!s.consent_captured) setPhase('consent')
    else setPhase('item')
  }, [supabase, token])

  useEffect(() => {
    void load()
  }, [load])

  const captureConsent = useCallback(async () => {
    if (!token) return
    setSubmitting(true)
    const { error } = await supabase.rpc('assessment_capture_consent', { p_token: token })
    setSubmitting(false)
    if (error) {
      setErrMsg(error.message)
      setPhase('error')
      return
    }
    await load()
  }, [supabase, token, load])

  const submitResponse = useCallback(
    async (item_id: string, value: number) => {
      if (!token) return
      setSubmitting(true)
      const { error } = await supabase.rpc('assessment_submit_response', {
        p_token: token,
        p_item_id: item_id,
        p_response_json: { value } as never,
      })
      setSubmitting(false)
      if (error) {
        setErrMsg(error.message)
        setPhase('error')
        return
      }
      await load()
    },
    [supabase, token, load],
  )

  if (phase === 'loading') {
    return (
      <Shell>
        <Centered>
          <Loader2 className="w-6 h-6 animate-spin text-muted" />
          <p className="font-mono text-xs uppercase tracking-wider text-muted mt-3">Loading…</p>
        </Centered>
      </Shell>
    )
  }

  if (phase === 'error') {
    return (
      <Shell>
        <Card className="max-w-md mx-auto border-accent">
          <CardEyebrow className="text-accent">Invite problem</CardEyebrow>
          <CardTitle className="mt-1">We couldn't open this assessment</CardTitle>
          <p className="mt-3 font-body text-sm text-muted">{errMsg ?? 'Unknown error.'}</p>
          <p className="mt-3 font-body text-xs text-muted">
            If your link expired, ask your recruiter to send a new one.
          </p>
        </Card>
      </Shell>
    )
  }

  if (!state) return null

  if (phase === 'done') {
    return (
      <Shell>
        <Card className="max-w-md mx-auto">
          <CardEyebrow>Assessment complete</CardEyebrow>
          <CardTitle className="mt-1">Thanks for finishing.</CardTitle>
          <p className="mt-3 font-body text-sm text-muted">
            Your responses are scored and shared (under your active consent) with the team you
            applied through. You can revoke this consent at any time.
          </p>
        </Card>
      </Shell>
    )
  }

  if (phase === 'consent') {
    return (
      <Shell>
        <Card className="max-w-lg mx-auto">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <CardEyebrow>Step 1 of 2 · Consent</CardEyebrow>
            <ValidityChip status={state.validity_status} />
          </div>
          <CardTitle className="mt-2">Your profile is yours.</CardTitle>
          <p className="mt-4 font-body text-sm text-ink leading-relaxed">
            To use this assessment, we need your consent to process your responses for one specific
            purpose: <strong>hiring_decision</strong>. This is the legal basis we'll record in our
            consent ledger.
          </p>
          <ul className="mt-4 space-y-2 font-body text-sm text-ink">
            <li className="flex gap-2"><Check className="w-4 h-4 mt-0.5 text-person flex-shrink-0" /> Purpose-limited to the role you applied for.</li>
            <li className="flex gap-2"><Check className="w-4 h-4 mt-0.5 text-person flex-shrink-0" /> You can revoke at any time. Revocation removes recruiter access immediately.</li>
            <li className="flex gap-2"><Check className="w-4 h-4 mt-0.5 text-person flex-shrink-0" /> Data stored in the EU region only.</li>
            <li className="flex gap-2"><Check className="w-4 h-4 mt-0.5 text-person flex-shrink-0" /> Every access is logged in an immutable audit trail.</li>
          </ul>
          <div className="mt-6 flex flex-col gap-3">
            <Button onClick={captureConsent} disabled={submitting} className="w-full">
              {submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : 'I consent — start the assessment'}
            </Button>
            <p className="font-mono text-[0.65rem] uppercase tracking-wider text-muted text-center">
              Closing this page without consenting stores nothing.
            </p>
          </div>
        </Card>
      </Shell>
    )
  }

  // phase === 'item'
  const remaining = state.items.filter((i) => !i.answered)
  const current = remaining[0] ?? null
  const total = state.items.length
  const done = total - remaining.length

  if (!current) {
    // All items answered locally but assessment status not yet marked completed by the recruiter
    return (
      <Shell>
        <Card className="max-w-md mx-auto">
          <CardEyebrow>All items answered</CardEyebrow>
          <CardTitle className="mt-1">Submitted.</CardTitle>
          <p className="mt-3 font-body text-sm text-muted">
            Your recruiter will finalize the scoring. You can close this page.
          </p>
        </Card>
      </Shell>
    )
  }

  return (
    <Shell>
      <Card className="max-w-lg mx-auto">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <CardEyebrow>Item {done + 1} of {total}</CardEyebrow>
          <ValidityChip status={state.validity_status} />
        </div>
        <h2 className="mt-3 font-display text-xl leading-snug text-ink">{current.prompt}</h2>
        <p className="mt-2 font-mono text-[0.65rem] uppercase tracking-wider text-muted">
          1 = strongly disagree · 5 = strongly agree
        </p>
        <div className="mt-6 grid grid-cols-5 gap-2">
          {(current.choices ?? [1, 2, 3, 4, 5]).map((value) => (
            <button
              key={value}
              disabled={submitting}
              onClick={() => void submitResponse(current.id, value)}
              className={[
                'aspect-square border-2 border-ink rounded font-display text-2xl font-bold',
                'bg-surface text-ink',
                'hover:bg-ink hover:text-paper active:translate-y-px',
                'disabled:opacity-50 disabled:cursor-not-allowed',
                'transition-colors',
              ].join(' ')}
            >
              {value}
            </button>
          ))}
        </div>
        {/* Progress dots */}
        <div className="mt-6 flex gap-1.5 justify-center">
          {state.items.map((i) => (
            <span
              key={i.id}
              className={[
                'inline-block w-2.5 h-2.5 rounded-full border-2 border-ink',
                i.answered ? 'bg-ink' : 'bg-paper',
              ].join(' ')}
            />
          ))}
        </div>
        <p className="mt-4 font-mono text-[0.65rem] uppercase tracking-wider text-muted text-center flex items-center justify-center gap-1.5">
          {submitting ? <Loader2 className="w-3 h-3 animate-spin" /> : <ChevronRight className="w-3 h-3" />}
          Tap a number — your answer is saved instantly
        </p>
      </Card>
    </Shell>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-paper px-4 py-8 sm:py-12">
      <header className="max-w-lg mx-auto mb-6">
        <p className="font-mono text-[0.65rem] uppercase tracking-wider text-muted">HeiTobias</p>
        <p className="font-display text-lg text-ink mt-0.5">Candidate assessment</p>
      </header>
      {children}
      <footer className="max-w-lg mx-auto mt-8 pt-6 border-t border-dashed border-hairline">
        <p className="font-mono text-[0.6rem] uppercase tracking-wider text-muted">
          EU-region hosted · purpose-limited · revocable · audited
        </p>
      </footer>
    </main>
  )
}

function Centered({ children }: { children: React.ReactNode }) {
  return <div className="min-h-[50vh] flex flex-col items-center justify-center">{children}</div>
}
