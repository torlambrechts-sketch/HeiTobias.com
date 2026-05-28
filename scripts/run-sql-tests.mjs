#!/usr/bin/env node
// Runs every supabase/tests/*.sql file as a pgTAP test against SUPABASE_DB_URL.
// Each file should wrap its assertions in a transaction and call plan/ok/finish.
// Exits non-zero if any assertion fails or any file errors.

import { readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import 'dotenv/config'
import pg from 'pg'

const TESTS_DIR = fileURLToPath(new URL('../supabase/tests/', import.meta.url))

const dbUrl = process.env.SUPABASE_DB_URL
if (!dbUrl) {
  console.error('SUPABASE_DB_URL is required (see .env.example).')
  process.exit(1)
}

const files = (await readdir(TESTS_DIR))
  .filter((f) => f.endsWith('.sql'))
  .sort()

if (files.length === 0) {
  console.log('No .sql tests to run.')
  process.exit(0)
}

const client = new pg.Client({ connectionString: dbUrl })
await client.connect()

let totalFailed = 0
for (const file of files) {
  const sql = await readFile(join(TESTS_DIR, file), 'utf-8')
  process.stdout.write(`# ${file}\n`)
  try {
    const result = await client.query(sql)
    const resultsets = Array.isArray(result) ? result : [result]
    for (const rs of resultsets) {
      if (!rs.rows) continue
      for (const row of rs.rows) {
        const line = String(Object.values(row)[0] ?? '')
        process.stdout.write(`${line}\n`)
        if (line.startsWith('not ok')) totalFailed++
      }
    }
  } catch (err) {
    console.error(`FAIL ${file}: ${err.message}`)
    totalFailed++
  }
}

await client.end()

if (totalFailed > 0) {
  console.error(`\n${totalFailed} failure(s).`)
  process.exit(1)
}
console.log('\nAll SQL tests passed.')
