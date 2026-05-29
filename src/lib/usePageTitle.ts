import { useEffect } from 'react'

// Set the browser tab title. Most pages should call this once on
// mount; updates compose through the page lifecycle.
//
// We deliberately format as "{section} — HeiTobias" rather than the
// other way around so the section is visible when many tabs are open
// (the section is what differentiates them; the brand is constant).

const SUFFIX = 'HeiTobias'

export function usePageTitle(section: string | null | undefined): void {
  useEffect(() => {
    const prev = document.title
    document.title = section ? `${section} — ${SUFFIX}` : SUFFIX
    return () => { document.title = prev }
  }, [section])
}
