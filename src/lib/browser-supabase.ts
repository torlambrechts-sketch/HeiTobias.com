import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../types/database.js'

const URL = import.meta.env.VITE_SUPABASE_URL as string | undefined
// Prefer the modern publishable key (sb_publishable_...); fall back to the
// legacy anon JWT for compatibility. Either works with supabase-js and is
// safe to expose to the browser (RLS still applies).
const PUBLISHABLE = (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ??
  import.meta.env.VITE_SUPABASE_ANON_KEY) as string | undefined

let client: SupabaseClient<Database> | null = null

export function envReady(): { ok: true } | { ok: false; missing: string[] } {
  const missing: string[] = []
  if (!URL) missing.push('VITE_SUPABASE_URL')
  if (!PUBLISHABLE) missing.push('VITE_SUPABASE_PUBLISHABLE_KEY')
  return missing.length === 0 ? { ok: true } : { ok: false, missing }
}

export function browserSupabase(): SupabaseClient<Database> {
  if (client) return client
  if (!URL || !PUBLISHABLE) {
    throw new Error(
      'browserSupabase(): missing Vite env. ' +
        'Copy .env.example to .env.local and fill VITE_SUPABASE_URL + VITE_SUPABASE_PUBLISHABLE_KEY.',
    )
  }
  client = createClient<Database>(URL, PUBLISHABLE, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      storage: window.sessionStorage,
    },
  })
  return client
}
