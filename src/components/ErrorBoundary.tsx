import { Component, type ErrorInfo, type ReactNode } from 'react'
import { AlertCircle, RefreshCw } from 'lucide-react'
import { log } from '../lib/log.js'

// App-level ErrorBoundary. Catches uncaught render errors and shows a
// designed crash page instead of the React default blank screen.
//
// What it does:
//   * componentDidCatch logs to the structured logger (which forwards
//     to Sentry once the DSN is wired, per src/lib/log.ts)
//   * renders a screen with a Try-Again button that resets the
//     boundary (re-mounts children)
//   * gives the user a clear "this is a bug" framing rather than
//     pretending nothing happened
//
// What it does NOT do:
//   * recover automatically (the React docs are explicit that a thrown
//     render error means the tree below is broken)
//   * catch async errors (those go through useToast / ErrorState)

interface State {
  err: Error | null
}

export class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  override state: State = { err: null }

  static getDerivedStateFromError(err: Error): State {
    return { err }
  }

  override componentDidCatch(err: Error, info: ErrorInfo): void {
    log.error('react.render_error', {
      message: err.message,
      stack: err.stack,
      component_stack: info.componentStack,
    })
  }

  reset = () => this.setState({ err: null })

  override render() {
    if (!this.state.err) return this.props.children
    return (
      <main className="min-h-screen flex items-center justify-center px-4 bg-canvas">
        <div className="max-w-lg text-center">
          <div className="w-14 h-14 mx-auto rounded-full bg-reject-bg flex items-center justify-center mb-3">
            <AlertCircle size={24} className="text-rust" aria-hidden />
          </div>
          <h1 className="font-display text-2xl font-bold text-ink mb-2">Something went wrong</h1>
          <p className="text-sm text-muted leading-relaxed mb-4">
            A render error happened. The error has been logged. You can try the action
            again — if it keeps failing, the link or the underlying data may be in a state
            we did not anticipate.
          </p>
          <details className="text-left text-xs text-faint bg-canvas-2 border border-line rounded p-3 mb-4">
            <summary className="cursor-pointer text-muted">Technical detail</summary>
            <pre className="mt-2 whitespace-pre-wrap break-words">{this.state.err.message}</pre>
          </details>
          <button
            type="button"
            onClick={this.reset}
            className="inline-flex items-center gap-2 px-4 py-2 rounded bg-forest text-white text-sm hover:bg-forest/90"
          >
            <RefreshCw size={14} /> Try again
          </button>
          <a href="/" className="block mt-3 text-xs text-faint hover:text-ink">Or go home →</a>
        </div>
      </main>
    )
  }
}
