import 'dotenv/config'
import { describe, it, expect } from 'vitest'
import { anonClient } from '../lib/supabase.js'

describe('Supabase connectivity (Step 1 smoke)', () => {
  it('anon client can reach the API and has no session', async () => {
    const supabase = anonClient()
    const { data, error } = await supabase.auth.getSession()
    expect(error).toBeNull()
    expect(data.session).toBeNull()
  })
})
