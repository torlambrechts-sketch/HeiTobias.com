import { Component, type ErrorInfo, type ReactNode } from 'react'
import { AlertTriangle } from 'lucide-react'
import { Card, CardEyebrow, CardTitle } from './ui/card.js'
import { envReady } from '../lib/browser-supabase.js'

/**
 * Catches render-time errors so the page never goes silently blank. Surfaces
 * a helpful message when the most common cause — missing Vite env — is the
 * culprit. Other errors are rendered with their message so the user (or
 * developer) sees something instead of a white screen.
 */
export class EnvBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  override state = { error: null as Error | null }

  static getDerivedStateFromError(error: Error) {
    return { error }
  }

  override componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('Render error:', error, info)
  }

  override render() {
    if (!this.state.error) return this.props.children
    const env = envReady()
    return (
      <main className="min-h-screen bg-paper px-4 py-12">
        <div className="max-w-2xl mx-auto">
          <Card className="border-accent">
            <div className="flex items-start gap-3">
              <AlertTriangle className="w-5 h-5 text-accent flex-shrink-0 mt-0.5" />
              <div className="space-y-2">
                <CardEyebrow className="text-accent">Render error</CardEyebrow>
                <CardTitle className="text-lg">The page couldn't render.</CardTitle>
                {!env.ok ? (
                  <div className="font-body text-sm text-ink space-y-2">
                    <p>
                      Most likely cause: missing Vite env (
                      <code className="font-mono text-xs">{env.missing.join(', ')}</code>
                      ).
                    </p>
                    <ol className="list-decimal pl-5 space-y-1">
                      <li>Copy <code className="font-mono text-xs">.env.example</code> to <code className="font-mono text-xs">.env.local</code>.</li>
                      <li>Fill in the Supabase URL + anon key.</li>
                      <li>Restart: <code className="font-mono text-xs">npm run dev</code>.</li>
                    </ol>
                  </div>
                ) : (
                  <p className="font-body text-sm text-ink">
                    {this.state.error.message || 'Unknown error.'} See the browser console for the stack.
                  </p>
                )}
              </div>
            </div>
          </Card>
        </div>
      </main>
    )
  }
}
