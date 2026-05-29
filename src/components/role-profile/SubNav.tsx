import { useEffect, useState } from 'react'

const ANCHORS: { id: string; label: string }[] = [
  { id: 'identity',      label: '1. Identity & governance' },
  { id: 'tasks',         label: '2. Tasks & outcomes' },
  { id: 'competencies',  label: '3. Weighted competencies' },
  { id: 'trait_targets', label: '4. Trait target bands' },
  { id: 'cognitive',     label: '5. Cognitive demand' },
  { id: 'context',       label: '6. Context factors' },
  { id: 'values',        label: '7. Values & motivation' },
  { id: 'success',       label: '8. Success criteria' },
  { id: 'evolution',     label: '9. Evolution vector' },
  { id: 'team_gap',      label: '10. Team-gap context' },
  { id: 'validation',    label: '11. Validation & defensibility' },
]

// Sticky left subnav with scrollspy using IntersectionObserver.
// On narrow viewports the subnav collapses to a horizontal pill row.
export function SubNav() {
  const [active, setActive] = useState<string>('identity')

  useEffect(() => {
    const els = ANCHORS.map(a => document.getElementById(a.id)).filter(Boolean) as HTMLElement[]
    if (els.length === 0) return
    const obs = new IntersectionObserver((entries) => {
      const visible = entries
        .filter(e => e.isIntersecting)
        .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
      if (visible[0]) setActive(visible[0].target.id)
    }, { rootMargin: '-20% 0px -55% 0px', threshold: [0, 0.1, 0.5, 1] })
    els.forEach(el => obs.observe(el))
    return () => obs.disconnect()
  }, [])

  return (
    <>
      {/* Desktop: 220px sticky subnav */}
      <nav className="hidden lg:block sticky top-20 self-start w-[220px] flex-shrink-0">
        <ul className="flex flex-col gap-1 text-sm">
          {ANCHORS.map(a => (
            <li key={a.id}>
              <a
                href={`#${a.id}`}
                className={
                  'block px-3 py-1.5 rounded text-faint hover:text-ink hover:bg-canvas-2 ' +
                  (active === a.id ? 'text-ink bg-canvas-2 font-semibold border-l-2 border-forest -ml-0.5 pl-[10px]' : '')
                }
              >
                {a.label}
              </a>
            </li>
          ))}
        </ul>
      </nav>
      {/* Mobile: horizontal pill row */}
      <nav className="lg:hidden flex flex-wrap gap-1 text-xs uppercase tracking-wider font-bold mb-3">
        {ANCHORS.map(a => (
          <a
            key={a.id}
            href={`#${a.id}`}
            className={'px-2 py-1 rounded border ' + (active === a.id ? 'bg-forest text-white border-forest' : 'border-line text-faint')}
          >
            {a.label.replace(/^\d+\.\s+/, '')}
          </a>
        ))}
      </nav>
    </>
  )
}
