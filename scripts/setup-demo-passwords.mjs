#!/usr/bin/env node
// Sets password='demo' on each seeded auth.users row so the smoke UI can sign in.
// Idempotent: just updates the password each time. Requires SUPABASE_SERVICE_ROLE_KEY.

import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const url = process.env.SUPABASE_URL
const key = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !key) {
  console.error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required (see .env.example).')
  process.exit(1)
}

const supabase = createClient(url, key, { auth: { persistSession: false } })

// The seeded user UUIDs from supabase/seed.sql.
const USERS = [
  { id: 'b1000000-0000-0000-0000-000000000001', email: 'astrid.berg@nordic-recruit.test' },
  { id: 'b1000000-0000-0000-0000-000000000002', email: 'magnus.holm@nordic-recruit.test' },
  { id: 'b1000000-0000-0000-0000-000000000003', email: 'linnea.strand@fjordtech.test' },
  { id: 'b1000000-0000-0000-0000-000000000004', email: 'erik.lund@fjordtech.test' },
  { id: 'b1000000-0000-0000-0000-000000000005', email: 'sara.vik@fjordtech.test' },
  { id: 'b1000000-0000-0000-0000-000000000006', email: 'jonas.dahl@fjordtech.test' },
  { id: 'b1000000-0000-0000-0000-000000000007', email: 'petra.nilsson@candidate.test' },
  { id: 'b1000000-0000-0000-0000-000000000008', email: 'henrik.ek@candidate.test' },
]

const DEMO_PASSWORD = 'demo'

let failed = 0
for (const u of USERS) {
  const { error } = await supabase.auth.admin.updateUserById(u.id, {
    password: DEMO_PASSWORD,
    email_confirm: true,
  })
  if (error) {
    console.error(`FAIL ${u.email}: ${error.message}`)
    failed++
  } else {
    console.log(`ok   ${u.email}`)
  }
}

if (failed > 0) {
  console.error(`\n${failed} user(s) failed.`)
  process.exit(1)
}
console.log(`\nAll ${USERS.length} demo passwords set to '${DEMO_PASSWORD}'.`)
