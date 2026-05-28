/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // DESIGN.md tokens — paper/ink with functional accents.
        paper:    'var(--paper)',
        surface:  'var(--surface)',
        ink:      'var(--ink)',
        muted:    'var(--muted)',
        line:     'var(--line)',
        hairline: 'var(--hairline)',
        accent:   'var(--accent)',
        role:     'var(--role)',
        person:   'var(--person)',
        highlight:'var(--highlight)',
        'fit-grow':    'var(--fit-grow)',
        'fit-flight':  'var(--fit-flight)',
        'fit-stable':  'var(--fit-stable)',
        'fit-misfit':  'var(--fit-misfit)',
      },
      fontFamily: {
        display: ['Fraunces', 'Georgia', 'serif'],
        body:    ['Archivo', 'system-ui', 'sans-serif'],
        mono:    ['"Space Mono"', 'ui-monospace', 'monospace'],
      },
      borderWidth: {
        DEFAULT: 'var(--border-weight)',
        strong:  'var(--border-strong)',
      },
      boxShadow: {
        hard:        'var(--shadow-hard)',
        'hard-role': '6px 6px 0 var(--role)',
        'hard-person': '6px 6px 0 var(--person)',
      },
      borderRadius: {
        DEFAULT: '4px',
      },
    },
  },
  plugins: [],
}
