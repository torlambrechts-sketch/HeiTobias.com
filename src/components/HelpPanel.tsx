import { useCallback, useState } from 'react'
import { useLocation, Link } from 'react-router-dom'
import { HelpCircle, Loader2, MessageSquarePlus, X } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { useToast } from './ui/Toast.js'

// In-app contextual help panel (Phase 5.3). A "?" button in the app bar
// opens a side panel with:
//   * contextual help articles keyed off the current route
//   * a "send feedback" form → feedback_submit RPC
//
// Contextual articles are a small static map; deep ones link to the
// public trust page where the methodology is explained in full.

type Article = { title: string; body: React.ReactNode }

function articlesFor(path: string): Article[] {
  if (path.startsWith('/team-def')) {
    return [
      { title: 'What is Delphi independence?', body: <>Evaluators rate independently before seeing each other's input, which reduces anchoring and groupthink. Stage 2 is sealed so no one can peek. <Link className="text-role underline" to="/trust">More on the methodology →</Link></> },
      { title: 'Why a sealed rating stage?', body: <>Sealing preserves measurement validity — if ratings could be seen mid-stage, they'd converge artificially. The seal is enforced server-side and audited.</> },
    ]
  }
  if (path.startsWith('/roles')) {
    return [
      { title: 'Why are trait targets ranges?', body: <>Because "more is better" is usually false for personality traits. Targets are bands with a direction + justification. <Link className="text-role underline" to="/trust">Read why →</Link></> },
      { title: 'What does a dev_stub badge mean?', body: <>The value's engine is built but the scientific calibration is pending expert sign-off. We label it rather than fake it.</> },
    ]
  }
  if (path.startsWith('/employees') || path.startsWith('/team')) {
    return [
      { title: 'Re-fit is developmental, not a verdict', body: <>The re-fit trajectory is a growth-conversation input, not a performance grade. Engagement signals are flight-risk/well-being indicators, never performance proxies.</> },
      { title: 'Why guidance refuses some prompts', body: <>The guidance composer refuses medical, legal, dismissal, salary, and protected-characteristic prompts — and logs the refusal. It's grounded in the frameworks library, never freeform.</> },
    ]
  }
  if (path.startsWith('/req') || path.startsWith('/requisitions')) {
    return [
      { title: 'Fit informs, never decides', body: <>Every hiring decision is recorded by a named human with a rationale. No score auto-advances or auto-rejects anyone.</> },
    ]
  }
  return [
    { title: 'Getting around', body: <>Use ⌘K / Ctrl-K to search people, roles, and requisitions. The bell shows your notifications.</> },
    { title: 'Your data rights', body: <>Manage your own data anytime from <Link className="text-role underline" to="/me/privacy">My data &amp; privacy</Link>.</> },
  ]
}

export function HelpPanel() {
  const [open, setOpen] = useState(false)
  const [mode, setMode] = useState<'help' | 'feedback'>('help')
  const location = useLocation()

  return (
    <>
      <button
        type="button"
        aria-label="Help"
        onClick={() => { setOpen(true); setMode('help') }}
        className="flex items-center justify-center w-8 h-8 rounded hover:bg-canvas-2 transition-colors text-muted"
      >
        <HelpCircle size={18} />
      </button>

      {open && (
        <div className="fixed inset-0 z-50 flex justify-end" role="dialog" aria-label="Help">
          <div className="absolute inset-0 bg-ink/20" onClick={() => setOpen(false)} />
          <div className="relative w-full max-w-sm bg-surface border-l border-line h-full overflow-y-auto shadow-hard">
            <div className="sticky top-0 bg-surface border-b border-line px-4 py-3 flex items-center justify-between">
              <p className="font-display font-semibold">{mode === 'help' ? 'Help' : 'Send feedback'}</p>
              <button type="button" onClick={() => setOpen(false)} aria-label="Close help"><X size={16} className="text-muted hover:text-ink" /></button>
            </div>

            {mode === 'help' ? (
              <div className="p-4 flex flex-col gap-4">
                {articlesFor(location.pathname).map((a, i) => (
                  <div key={i} className="border-b border-line pb-3">
                    <p className="font-medium text-sm">{a.title}</p>
                    <div className="text-sm text-muted mt-1 leading-relaxed">{a.body}</div>
                  </div>
                ))}
                <div className="flex flex-col gap-2">
                  <Link to="/docs" className="text-sm text-role hover:underline">Browse the full FAQ →</Link>
                  <button type="button" onClick={() => setMode('feedback')} className="inline-flex items-center gap-1.5 text-sm text-role hover:underline">
                    <MessageSquarePlus size={14} /> Send feedback
                  </button>
                </div>
              </div>
            ) : (
              <FeedbackForm path={location.pathname} onDone={() => setOpen(false)} onBack={() => setMode('help')} />
            )}
          </div>
        </div>
      )}
    </>
  )
}

function FeedbackForm({ path, onDone, onBack }: { path: string; onDone: () => void; onBack: () => void }) {
  const supabase = browserSupabase()
  const toast = useToast()
  const [category, setCategory] = useState<'general' | 'bug' | 'idea' | 'data_concern'>('general')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)

  const submit = useCallback(async () => {
    if (message.trim().length < 3) return
    setBusy(true)
    const { error } = await supabase.rpc('feedback_submit' as never, {
      p_message: message, p_category: category, p_page_path: path,
    } as never)
    setBusy(false)
    if (error) { toast.error(`Could not send: ${error.message}`); return }
    toast.success('Thanks — your feedback was sent.')
    onDone()
  }, [supabase, toast, message, category, path, onDone])

  return (
    <div className="p-4 flex flex-col gap-3">
      <label className="flex flex-col gap-1">
        <span className="text-xs text-muted">Category</span>
        <select value={category} onChange={e => setCategory(e.target.value as typeof category)} className="border border-line rounded px-3 py-2 text-sm bg-surface">
          <option value="general">General</option>
          <option value="bug">Bug</option>
          <option value="idea">Idea</option>
          <option value="data_concern">Data concern</option>
        </select>
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-xs text-muted">Your feedback</span>
        <textarea rows={5} value={message} onChange={e => setMessage(e.target.value)} className="border border-line rounded px-3 py-2 text-sm font-body" placeholder="What's on your mind?" />
      </label>
      <div className="flex items-center justify-between">
        <button type="button" onClick={onBack} className="text-sm text-muted hover:text-ink">← Back</button>
        <button
          type="button" onClick={submit} disabled={busy || message.trim().length < 3}
          className="inline-flex items-center gap-1.5 bg-forest text-white rounded-lg px-4 py-1.5 text-sm disabled:opacity-50"
        >
          {busy ? <Loader2 size={14} className="animate-spin" /> : null} Send
        </button>
      </div>
    </div>
  )
}
