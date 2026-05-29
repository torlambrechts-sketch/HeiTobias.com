#!/usr/bin/env node
// Pre-deploy invariant checks. Runs as part of the CI pipeline; failure
// blocks the deploy. Each check asserts a load-bearing architectural
// invariant — if any fails, the build is wrong, not flaky.
//
// What we check:
//   1. No row in any seed migration carries validity_status='validated'
//      (CLAUDE.md §5 guard — the demo must never look like validated science)
//   2. No SECDEF function in src lacks `set search_path = ''`
//      (security hardening — prevents search_path injection)
//   3. No RLS-protected table is missing FORCE ROW LEVEL SECURITY
//      (Phase 0 hardening discipline)
//   4. No hardcoded demo credentials reach the production bundle
//      (grep dist/ after build)
//
// The first three are SQL-based and run against the migration files
// (lightweight; no DB connection needed). The fourth runs against the
// build output.

import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __filename = fileURLToPath(import.meta.url)
const __dirname  = dirname(__filename)
const ROOT       = join(__dirname, '..')

const errors = []

function read(path) {
  try { return readFileSync(path, 'utf8') } catch { return null }
}

// ─── INVARIANT 1: no fabricated 'validated' rows in seed/migration text
const migrationsDir = join(ROOT, 'supabase', 'migrations')
const seedDemoDir   = join(ROOT, 'supabase', 'seed-demo')
const seedFile      = join(ROOT, 'supabase', 'seed.sql')
const filesToScan = [
  ...readdirSync(migrationsDir).map(f => join(migrationsDir, f)),
  ...readdirSync(seedDemoDir).map(f => join(seedDemoDir, f)),
  seedFile,
]
for (const path of filesToScan) {
  const sql = read(path)
  if (!sql) continue
  // Strip out CREATE FUNCTION bodies — they contain runtime logic (e.g. the
  // legitimate sign-off RPC that promotes a model card to 'validated'), not
  // migration-time seeds. We only care about top-level seed/migration writes.
  const topLevel = stripFunctionBodies(sql)
  const stmts = topLevel.match(/\b(insert\s+into|update)\s+[^;]+;/gi) || []
  for (const stmt of stmts) {
    if (!/\bvalidity_status\b/i.test(stmt)) continue
    if (!/'validated'/i.test(stmt)) continue
    if (/<>\s*'validated'/i.test(stmt)) continue
    if (/!=\s*'validated'/i.test(stmt)) continue
    const excerpt = stmt.slice(0, 100).replace(/\s+/g, ' ')
    errors.push(`INVARIANT-1 fail: ${path} sets validity_status='validated' on a seeded row. ` +
                `Demo seeds must NEVER carry validated status. Found: "${excerpt}…"`)
    break
  }
}

// Strip PL/pgSQL function bodies bounded by `$$ ... $$` (or any dollar-tag).
// Crude but sufficient for this codebase's style: every function body uses
// `$$` or `$tag$` delimiters.
function stripFunctionBodies(sql) {
  return sql.replace(/\$([a-zA-Z0-9_]*)\$[\s\S]*?\$\1\$/g, '$$BODY$$')
}

// ─── INVARIANT 2: SECDEF functions in migrations must set search_path=''
for (const path of readdirSync(migrationsDir).map(f => join(migrationsDir, f))) {
  const sql = read(path)
  if (!sql) continue
  // For every SECURITY DEFINER declaration, check that the same function
  // block also contains `set search_path`.
  const blocks = sql.split(/create\s+(?:or\s+replace\s+)?function/i).slice(1)
  for (const blk of blocks) {
    const head = blk.slice(0, 1200).toLowerCase()
    if (head.includes('security definer') && !head.includes("set search_path = ''") && !head.includes('set search_path=\'\'')) {
      const fnName = (blk.match(/^[\s\S]*?\bpublic\.(\w+)/) || [])[1] ?? '<unknown>'
      errors.push(`INVARIANT-2 fail: SECDEF function public.${fnName} in ${path} lacks "set search_path = ''". ` +
                  `Hardening discipline requires every SECDEF function to lock its search_path.`)
    }
  }
}

// ─── INVARIANT 3: every table with `enable row level security` somewhere in
// the migration history must ALSO have a matching FORCE statement somewhere
// in the migration history. The two don't have to live in the same migration
// — adding FORCE later is fine — but the FINAL state must be FORCED.
{
  const enabled = new Set()
  const forced  = new Set()
  for (const path of readdirSync(migrationsDir).map(f => join(migrationsDir, f))) {
    const sql = read(path)
    if (!sql) continue
    for (const m of sql.matchAll(/alter\s+table\s+public\.(\w+)\s+enable\s+row\s+level\s+security/gi)) {
      enabled.add(m[1])
    }
    for (const m of sql.matchAll(/alter\s+table\s+public\.(\w+)\s+force\s+row\s+level\s+security/gi)) {
      forced.add(m[1])
    }
  }
  for (const table of enabled) {
    if (!forced.has(table)) {
      errors.push(`INVARIANT-3 fail: public.${table} has RLS enabled in the migration history ` +
                  `but no migration ever FORCEs it. Without FORCE, the table owner can bypass RLS — ` +
                  `production cannot rely on that.`)
    }
  }
}

// ─── INVARIANT 4 (build-time only): demo credentials must not be in dist
const distDir = join(ROOT, 'dist')
let distExists = false
try { distExists = statSync(distDir).isDirectory() } catch { distExists = false }
if (distExists) {
  function* walk(dir) {
    for (const e of readdirSync(dir)) {
      const p = join(dir, e)
      const s = statSync(p)
      if (s.isDirectory()) yield* walk(p)
      else yield p
    }
  }
  for (const p of walk(distDir)) {
    if (!p.endsWith('.js') && !p.endsWith('.css') && !p.endsWith('.html')) continue
    const content = read(p)
    if (!content) continue
    // Catch any hardcoded `password: 'demo'` (or "demo") regardless of
    // which test email it's paired with. The earlier version only
    // flagged the Linnea email, which let the Astrid/Magnus/Sara
    // personas slip through. Demo creds belong in the dev tree only.
    if (/password\s*:\s*['"]demo['"]/.test(content) && /@[\w-]+\.test\b/.test(content)) {
      errors.push(`INVARIANT-4 fail: production bundle ${p.replace(ROOT, '')} contains demo sign-in credentials ` +
                  `(\`password: 'demo'\` next to a \`*.test\` email). These must be gated behind ` +
                  `import.meta.env.DEV so Vite tree-shakes them out.`)
    }
  }
}

if (errors.length > 0) {
  console.error('\n❌ Invariant checks FAILED — deploy blocked.\n')
  for (const e of errors) console.error('  • ' + e + '\n')
  process.exit(1)
}
console.log('✓ Invariant checks passed.')
