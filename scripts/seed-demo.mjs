#!/usr/bin/env node
// npm run seed:demo
//
// Seeds the demo orgs + people + roles + requisitions + Team Definition
// run + Maria-emerging-misfit case. Used for staging environment resets
// and local dev. NEVER auto-runs in production.
//
// Double guard before any SQL executes:
//   1. SEED_DEMO_DATA env var must be exactly 'true'
//   2. The target database must be EMPTY of real data
//      (zero rows in core tables after exclude is_demo_data=true)
//   3. NODE_ENV must NOT be 'production' UNLESS SEED_DEMO_DATA=true
//      AND --i-know-this-is-staging-not-production flag is present
//
// Refuses with a clear error if any guard fails.

import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
import { readFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __filename = fileURLToPath(import.meta.url)
const __dirname  = dirname(__filename)

function fail(msg) {
  console.error('\n❌ seed:demo refused\n')
  console.error('   ' + msg.split('\n').join('\n   '))
  console.error('')
  process.exit(1)
}

// ─── Guard 1: SEED_DEMO_DATA ─────────────────────────────────────
const SEED = (process.env.SEED_DEMO_DATA ?? '').toLowerCase()
if (SEED !== 'true') {
  fail([
    'SEED_DEMO_DATA env var is not "true".',
    '',
    'Set in your shell or .env.local:',
    '  SEED_DEMO_DATA=true npm run seed:demo',
    '',
    'In production this env var must remain unset (or "false") in the',
    'hosting platform\'s secret manager. Production deploys do NOT seed demo data.',
  ].join('\n'))
}

// ─── Guard 2: NODE_ENV vs --i-know-this-is-staging-not-production ──
const NODE_ENV = process.env.NODE_ENV ?? 'development'
const ACK_FLAG = process.argv.includes('--i-know-this-is-staging-not-production')
if (NODE_ENV === 'production' && !ACK_FLAG) {
  fail([
    'NODE_ENV=production but the operator-ack flag is missing.',
    '',
    'Even with SEED_DEMO_DATA=true, running this against production requires:',
    '  npm run seed:demo -- --i-know-this-is-staging-not-production',
    '',
    'This flag exists because confusing a staging env for production is the',
    'most likely operational mistake. Forcing the explicit phrasing makes that',
    'mistake one keystroke harder.',
  ].join('\n'))
}

// ─── Guard 3: target DB must be empty of real data ──────────────
const URL = process.env.SUPABASE_URL
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!URL || !KEY) {
  fail([
    'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in environment.',
    'Copy .env.example to .env.local and fill in the values, then retry.',
  ].join('\n'))
}
const sb = createClient(URL, KEY, { auth: { persistSession: false } })

console.log('seed:demo — verifying target database…')
const checks = [
  { table: 'people',       filter: (q) => q.is('is_demo_data', false) },
  { table: 'organizations', filter: (q) => q.is('is_demo_data', false) },
  { table: 'requisitions',  filter: (q) => q.is('is_demo_data', false) },
]
for (const c of checks) {
  const { count, error } = await c.filter(
    sb.from(c.table).select('id', { count: 'exact', head: true })
  )
  if (error) fail(`Could not check ${c.table}: ${error.message}`)
  if ((count ?? 0) > 0) {
    fail([
      `Target database has ${count} non-demo rows in ${c.table}.`,
      '',
      'seed:demo refuses to run on a database that already contains real data.',
      'For staging resets between demos, first run:',
      '  npm run seed:demo:wipe',
      'which removes only the rows where is_demo_data = true.',
    ].join('\n'))
  }
}

// ─── Execute the demo seeds in order ────────────────────────────
const seedDir = join(__dirname, '..', 'supabase', 'seed-demo')
let files = []
try {
  files = readdirSync(seedDir).filter(f => f.endsWith('.sql')).sort()
} catch (e) {
  fail(`Cannot read ${seedDir}: ${e.message}`)
}
if (files.length === 0) {
  fail(`No .sql files found in supabase/seed-demo/.`)
}

console.log(`seed:demo — applying ${files.length} seed file(s)…`)
for (const f of files) {
  const path = join(seedDir, f)
  const sql = readFileSync(path, 'utf8')
  process.stdout.write(`  • ${f}…`)
  // The Supabase JS client doesn't expose raw SQL execution against the
  // user database via the standard SDK. Operators run this through the
  // Supabase CLI (supabase db push) OR a direct psql connection with
  // SUPABASE_DB_URL. For now this script's responsibility is the GUARDS;
  // applying the SQL is delegated to a follow-on shell command.
  process.stdout.write(' (queued — apply via `supabase db push` or psql $SUPABASE_DB_URL -f <file>)\n')
  // Length-only check so the script remains useful as a guard validator:
  if (sql.length < 10) {
    fail(`Seed file ${f} is suspiciously short (${sql.length} bytes).`)
  }
}

console.log('\n✓ Guards passed. Seeds queued for application.\n')
console.log('Apply them with one of:')
console.log('  • supabase db push                       (recommended)')
console.log(`  • for f in supabase/seed-demo/*.sql; do psql "$SUPABASE_DB_URL" -f "$f"; done`)
console.log('\nAfter seeding, demo personas can sign in (dev only — production keeps')
console.log('SEED_DEMO_DATA=false and these credentials never exist on prod):')
console.log('  • sara.lindqvist@demo-lindqvist.test    agency org_admin')
console.log('  • ingrid.holst@demo-holst.test          employer org_admin')
console.log('  • maria.lindqvist@demo-holst.test       employee (emerging-misfit demo)')
console.log('\nReset SEED_DEMO_DATA=false in production environment before launch.\n')
