import { createContext, useContext, useState, type ReactNode } from 'react'
import en   from '../i18n/en.json'
import nbNO from '../i18n/nb-NO.json'
import svSE from '../i18n/sv-SE.json'
import daDK from '../i18n/da-DK.json'

// Minimal i18n. No external dependency — just a Locale enum, four
// dictionaries (en + the three Nordic locales the platform serves),
// a Provider, and two hooks: useT() returns a translate function,
// useLocale() returns the active locale + a setter.
//
// CLAUDE.md mandate: all user-facing strings localisable. The Nordic
// dictionaries ship empty in this commit — translation is HANDOFF to
// native-speaker localisers, not engineering. Until they fill in, the
// translate function falls back to English (and then to the supplied
// `fallback` argument, then to the key as last resort).

export type Locale = 'en' | 'nb-NO' | 'sv-SE' | 'da-DK'

export const LOCALES: { code: Locale; label: string; nativeLabel: string }[] = [
  { code: 'en',    label: 'English',   nativeLabel: 'English'   },
  { code: 'nb-NO', label: 'Norwegian', nativeLabel: 'Norsk'     },
  { code: 'sv-SE', label: 'Swedish',   nativeLabel: 'Svenska'   },
  { code: 'da-DK', label: 'Danish',    nativeLabel: 'Dansk'     },
]

const dictionaries: Record<Locale, Record<string, string>> = {
  'en':    en    as Record<string, string>,
  'nb-NO': nbNO  as Record<string, string>,
  'sv-SE': svSE  as Record<string, string>,
  'da-DK': daDK  as Record<string, string>,
}

type Ctx = { locale: Locale; setLocale: (l: Locale) => void }
const LocaleContext = createContext<Ctx>({ locale: 'en', setLocale: () => undefined })

const STORAGE_KEY = 'heitobias.locale'

function readPersistedLocale(): Locale {
  try {
    const v = window.localStorage.getItem(STORAGE_KEY)
    if (v && LOCALES.some(l => l.code === v)) return v as Locale
  } catch { /* ignore */ }
  return 'en'
}

export function LocaleProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(() => readPersistedLocale())
  const setLocale = (l: Locale) => {
    setLocaleState(l)
    try { window.localStorage.setItem(STORAGE_KEY, l) } catch { /* ignore */ }
  }
  return (
    <LocaleContext.Provider value={{ locale, setLocale }}>
      {children}
    </LocaleContext.Provider>
  )
}

export function useLocale(): { locale: Locale; setLocale: (l: Locale) => void } {
  return useContext(LocaleContext)
}

export function useT(): (key: string, fallback?: string) => string {
  const { locale } = useContext(LocaleContext)
  return (key: string, fallback?: string) => {
    return dictionaries[locale][key]
        ?? dictionaries.en[key]
        ?? fallback
        ?? key
  }
}
