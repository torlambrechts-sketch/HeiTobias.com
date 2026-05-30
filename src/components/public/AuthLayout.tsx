import { type ReactNode } from 'react'
import { Link } from 'react-router-dom'

// AuthLayout — centered card chrome for login / signup / reset surfaces.
// Minimal: wordmark + the card + a footer link row. No app shell.
export function AuthLayout({ title, subtitle, children, footer }: {
  title: string
  subtitle?: string
  children: ReactNode
  footer?: ReactNode
}) {
  return (
    <div className="min-h-screen bg-canvas flex flex-col">
      <header className="px-5 h-16 flex items-center">
        <Link to="/" className="flex items-center gap-2 font-display font-bold text-lg">
          <span className="w-8 h-8 rounded-lg bg-forest text-white flex items-center justify-center">T</span>
          HeiTobias
        </Link>
      </header>
      <main className="flex-1 flex items-center justify-center px-4 py-8">
        <div className="w-full max-w-md">
          <h1 className="font-display text-3xl font-bold text-center">{title}</h1>
          {subtitle && <p className="text-muted text-sm text-center mt-2">{subtitle}</p>}
          <div className="mt-6 bg-surface border border-line rounded-xl p-6 shadow-soft">
            {children}
          </div>
          {footer && <div className="mt-4 text-center text-sm text-muted">{footer}</div>}
        </div>
      </main>
    </div>
  )
}
