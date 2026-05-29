#!/usr/bin/env node
// npm run seed:demo:wipe
//
// Removes all rows where is_demo_data = true. Useful for resetting a
// staging environment between demo walkthroughs.
//
// REFUSES to run in production unless the operator-ack flag is present
// AND the SEED_DEMO_DATA env var is true (same guards as seed-demo).
//
// Demo-flag wipes are safe: they only touch is_demo_data=true rows.
// Foreign-key cascades clean up dependent rows.

import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

function fail(msg) {
  console.error('\n❌ seed:demo:wipe refused\n')
  console.error('   ' + msg.split('\n').join('\n   '))
  console.error('')
  process.exit(1)
}

const SEED = (process.env.SEED_DEMO_DATA ?? '').toLowerCase()
if (SEED !== 'true') {
  fail('SEED_DEMO_DATA env var is not "true". Same guard as seed:demo.')
}
const NODE_ENV = process.env.NODE_ENV ?? 'development'
const ACK = process.argv.includes('--i-know-this-is-staging-not-production')
if (NODE_ENV === 'production' && !ACK) {
  fail('NODE_ENV=production but operator-ack flag missing. Use:\n  npm run seed:demo:wipe -- --i-know-this-is-staging-not-production')
}

const URL = process.env.SUPABASE_URL
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!URL || !KEY) fail('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.')
const sb = createClient(URL, KEY, { auth: { persistSession: false } })

const TABLES = [
  'team_definition_runs',
  'requisition_candidates',
  'requisitions',
  'roles_catalog',
  'memberships',
  'people',
  'organizations',
]
console.log('seed:demo:wipe — removing is_demo_data=true rows…\n')
for (const t of TABLES) {
  const { error, count } = await sb.from(t).delete({ count: 'exact' }).eq('is_demo_data', true)
  if (error) { console.error(`  ✗ ${t}: ${error.message}`); continue }
  console.log(`  ✓ ${t}: ${count ?? 0} rows removed`)
}
console.log('\nDone.\n')
