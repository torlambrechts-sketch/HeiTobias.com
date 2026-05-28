/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // DESIGN.md §3 tokens — warm cream-green canvas + forest chrome.
        canvas:    'var(--canvas)',
        'canvas-2':'var(--canvas-2)',
        surface:   'var(--surface)',

        rail:      'var(--rail)',
        forest:    'var(--forest)',
        'forest-2':'var(--forest-2)',
        green:     'var(--green)',

        ink:       'var(--ink)',
        muted:     'var(--muted)',
        faint:     'var(--faint)',

        line:      'var(--line)',
        'line-2':  'var(--line-2)',

        // Soft tinted status pill pairs.
        'open-bg':      'var(--open-bg)',      'open-fg':      'var(--open-fg)',
        'draft-bg':     'var(--draft-bg)',     'draft-fg':     'var(--draft-fg)',
        'internal-bg':  'var(--internal-bg)',  'internal-fg':  'var(--internal-fg)',
        'reject-bg':    'var(--reject-bg)',    'reject-fg':    'var(--reject-fg)',
        'interview-bg': 'var(--interview-bg)', 'interview-fg': 'var(--interview-fg)',
        'offer-bg':     'var(--offer-bg)',     'offer-fg':     'var(--offer-fg)',

        // Domain entities.
        role:   'var(--role)',
        person: 'var(--person)',
        amber:  'var(--amber)',
        rust:   'var(--rust)',
      },
      fontFamily: {
        display: ['Playfair Display', 'Georgia', 'serif'],
        body:    ['Inter', 'system-ui', 'sans-serif'],
        sans:    ['Inter', 'system-ui', 'sans-serif'],
      },
      borderRadius: {
        DEFAULT: '6px',
        lg:      '8px',
      },
      boxShadow: {
        soft: '0 1px 2px rgba(58,77,63,.05), 0 6px 18px rgba(58,77,63,.05)',
      },
    },
  },
  plugins: [],
}
