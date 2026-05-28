import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../types/database.js'

function required(key: string, val: string | undefined): string {
  if (!val) throw new Error(`Missing required Vite env: ${key} (set in .env)`)
  return val
}

const URL = required('VITE_SUPABASE_URL', import.meta.env.VITE_SUPABASE_URL)
const ANON = required('VITE_SUPABASE_ANON_KEY', import.meta.env.VITE_SUPABASE_ANON_KEY)

let client: SupabaseClient<Database> | null = null

export function browserSupabase(): SupabaseClient<Database> {
  if (client) return client
  client = createClient<Database>(URL, ANON, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      storage: window.sessionStorage,
    },
  })
  return client
}
