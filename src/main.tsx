import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import { App } from './App.js'
import { validateConfig, formatValidationError } from './lib/config.js'

// Validate browser env at startup. Fails FAST with a clear list of
// missing variables rather than dying three async requests in. The
// EnvBoundary component still renders a friendly user-facing fallback;
// this is the engineer-facing fail-fast at boot.
const cfg = validateConfig('browser')
if (!cfg.ok) {
  // eslint-disable-next-line no-console
  console.error(formatValidationError(cfg))
}

const root = document.getElementById('root')
if (!root) throw new Error('#root element not found in index.html')
createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
