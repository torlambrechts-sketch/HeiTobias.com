import { Component, type ErrorInfo, type ReactNode } from 'react'
import { AlertTriangle } from 'lucide-react'
import { Card, CardBody, CardEyebrow, CardTitle } from './ui/card.js'
import { envReady } from '../lib/browser-supabase.js'

/**
 * Catches render-time errors so the page never goes silently blank. Surfaces
 * a helpful message when the most common cause — missing Vite env — is the
 * culprit. Otherwise renders the error message so a developer sees something
 * instead of a white screen.
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
      <main className="min-h-screen bg-canvas px-4 py-12">
        <div className="max-w-2xl mx-auto">
          <Card>
            <CardBody className="flex items-start gap-3">
              <AlertTriangle className="w-5 h-5 text-rust flex-shrink-0 mt-0.5" />
              <div className="space-y-2">
                <CardEyebrow className="text-rust">Render error</CardEyebrow>
                <CardTitle className="text-lg">The page couldn't render.</CardTitle>
                {!env.ok ? (
                  <div className="text-sm text-ink space-y-2">
                    <p>
                      Most likely cause: missing Vite env (
                      <code className="text-xs">{env.missing.join(', ')}</code>
                      ).
                    </p>
                    <ol className="list-decimal pl-5 space-y-1">
                      <li>Copy <code className="text-xs">.env.example</code> to <code className="text-xs">.env.local</code>.</li>
                      <li>Fill in the Supabase URL + anon key.</li>
                      <li>Restart: <code className="text-xs">npm run dev</code>.</li>
                    </ol>
                  </div>
                ) : (
                  <p className="text-sm text-ink">
                    {this.state.error.message || 'Unknown error.'} See the browser console for the stack.
                  </p>
                )}
              </div>
            </CardBody>
          </Card>
        </div>
      </main>
    )
  }
}
