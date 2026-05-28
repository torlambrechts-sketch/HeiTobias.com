import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../types/database.js'

const URL = import.meta.env.VITE_SUPABASE_URL as string | undefined
const ANON = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

let client: SupabaseClient<Database> | null = null

export function envReady(): { ok: true } | { ok: false; missing: string[] } {
  const missing: string[] = []
  if (!URL) missing.push('VITE_SUPABASE_URL')
  if (!ANON) missing.push('VITE_SUPABASE_ANON_KEY')
  return missing.length === 0 ? { ok: true } : { ok: false, missing }
}

export function browserSupabase(): SupabaseClient<Database> {
  if (client) return client
  if (!URL || !ANON) {
    throw new Error(
      'browserSupabase(): missing Vite env. ' +
        'Copy .env.example to .env.local and fill VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY.',
    )
  }
  client = createClient<Database>(URL, ANON, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      storage: window.sessionStorage,
    },
  })
  return client
}
