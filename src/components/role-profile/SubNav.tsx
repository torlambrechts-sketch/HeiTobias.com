import { useEffect, useState } from 'react'

const ANCHORS: { id: string; num: string; label: string }[] = [
  { id: 'identity',      num: '01', label: 'Identity & governance' },
  { id: 'tasks',         num: '02', label: 'Tasks & outcomes' },
  { id: 'competencies',  num: '03', label: 'Weighted competencies' },
  { id: 'trait_targets', num: '04', label: 'Trait target bands' },
  { id: 'cognitive',     num: '05', label: 'Cognitive demand' },
  { id: 'context',       num: '06', label: 'Context factors' },
  { id: 'values',        num: '07', label: 'Values & motivation' },
  { id: 'success',       num: '08', label: 'Success criteria' },
  { id: 'evolution',     num: '09', label: 'Evolution vector' },
  { id: 'team_gap',      num: '10', label: 'Team-gap context' },
  { id: 'validation',    num: '11', label: 'Validation & defensibility' },
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
      {/* Desktop: 220px sticky subnav. Matches role-profile-detail.html: a Playfair-numbered
          prefix (01–11) sits left of each label; active item highlights the number in role-blue
          + the label in ink. */}
      <nav className="hidden lg:block sticky top-20 self-start w-[220px] flex-shrink-0">
        <ul className="flex flex-col gap-0.5 text-sm">
          {ANCHORS.map(a => (
            <li key={a.id}>
              <a
                href={`#${a.id}`}
                className={
                  'flex items-center gap-2.5 px-3 py-2 rounded text-faint hover:text-ink hover:bg-canvas-2 leading-snug ' +
                  (active === a.id ? 'text-ink bg-canvas-2 font-bold' : '')
                }
              >
                <span className={'font-display text-xs w-[18px] flex-shrink-0 ' + (active === a.id ? 'text-role' : 'text-faint')}>
                  {a.num}
                </span>
                <span>{a.label}</span>
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
            <span className="font-display mr-1">{a.num}</span>{a.label}
          </a>
        ))}
      </nav>
    </>
  )
}
