import type { SupabaseClient } from '@supabase/supabase-js'
import type { RoleProfileRow } from '../types/roleProfile.js'

// Data access for the Role Profile detail page. Reads through RLS — no
// service-role bypass on the client. Returns null when the role doesn't
// exist OR when RLS denies the read (the page treats both as a 404).
export async function fetchRoleProfile(
  supabase: SupabaseClient,
  id: string,
  version?: number,
): Promise<RoleProfileRow | null> {
  let q = supabase.from('roles_catalog' as never).select('*').eq('id', id)
  if (version !== undefined) q = q.eq('version', version)
  const { data, error } = await q.maybeSingle()
  if (error) {
    // 406/PGRST116 = no rows; treat as null. Anything else, throw.
    if (error.code === 'PGRST116') return null
    throw error
  }
  return (data as unknown as RoleProfileRow) ?? null
}

// Version history for a role — returns sibling versions sorted oldest first.
export async function fetchRoleVersionHistory(
  supabase: SupabaseClient,
  id: string,
): Promise<RoleProfileRow[]> {
  // Walk the supersedes_id chain backwards from id, then collect anyone who
  // supersedes_id => id (going forward). Simpler approach: search by
  // (org_id, title) tuple of the seed row and order by version.
  const { data: seed, error: seedErr } = await supabase
    .from('roles_catalog' as never)
    .select('org_id,title')
    .eq('id', id)
    .maybeSingle()
  if (seedErr || !seed) return []
  const s = seed as unknown as { org_id: string | null; title: string }
  let q = supabase
    .from('roles_catalog' as never)
    .select('*')
    .eq('title', s.title)
    .order('version', { ascending: true })
  if (s.org_id === null) q = q.is('org_id', null)
  else q = q.eq('org_id', s.org_id)
  const { data, error } = await q
  if (error) throw error
  return (data as unknown as RoleProfileRow[]) ?? []
}
