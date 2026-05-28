import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../types/database.js'

function required(key: string): string {
  const v = process.env[key]
  if (!v) throw new Error(`Missing required environment variable: ${key}`)
  return v
}

/**
 * Anon client — uses the publishable anon key. RLS applies; safe for the browser.
 * In tests, this is what proves "unauthenticated request sees nothing".
 */
export function anonClient(): SupabaseClient<Database> {
  return createClient<Database>(required('SUPABASE_URL'), required('SUPABASE_ANON_KEY'), {
    auth: { persistSession: false },
  })
}

/**
 * Service-role client — bypasses RLS. Server-side and test-fixture setup ONLY.
 * Never expose this key in the browser.
 */
export function serviceClient(): SupabaseClient<Database> {
  return createClient<Database>(required('SUPABASE_URL'), required('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false },
  })
}

/**
 * Per-user client with a specific JWT. Used in RLS tests to simulate "logged in as X" —
 * RLS predicates resolve from auth.uid() which is read out of the JWT claims.
 */
export function userClient(accessToken: string): SupabaseClient<Database> {
  return createClient<Database>(required('SUPABASE_URL'), required('SUPABASE_ANON_KEY'), {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  })
}
