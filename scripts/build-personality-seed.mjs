#!/usr/bin/env node
/**
 * Generates supabase/migrations/20260530800100_personality_step3_seed.sql
 * from the source data files in supabase/seed/. Re-run this script if any
 * of the source files (question_bank.csv, question_bank.json,
 * role_templates.json) change.
 *
 * Output is a single SQL migration that:
 *   1. Upserts 19 personality_traits (metadata + citations).
 *   2. Inserts 1 assessment_instruments row (personality_v1, licensed) +
 *      190 assessment_items rows under it.
 *   3. Upserts 10 personality_role_templates + their
 *      personality_role_template_traits rows (mix of numeric contributors
 *      and HUMAN-REVIEW flags — the schema's chk_template_trait_shape
 *      enforces the two shapes are mutually exclusive).
 *   4. Seeds personality_norms (one row per trait with a deterministic
 *      synthetic dev_stub distribution, validity_status='dev_stub').
 *
 * Why a generator (vs hand-writing the migration): 190 items × per-item
 * INSERT statements would be unmaintainable; if a wording changes you
 * re-run this script and review the SQL diff. The script is
 * deterministic: same inputs → byte-identical output.
 */

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SEED = join(ROOT, 'supabase', 'seed')
const OUT  = join(ROOT, 'supabase', 'migrations', '20260530800100_personality_step3_seed.sql')

// ─── Load sources ───────────────────────────────────────────────────
const itemsCsv      = readFileSync(join(SEED, 'personality_items.csv'), 'utf8')
const bankJson      = JSON.parse(readFileSync(join(SEED, 'personality_question_bank.json'), 'utf8'))
const templatesJson = JSON.parse(readFileSync(join(SEED, 'personality_role_templates.json'), 'utf8'))

// ─── Parse the CSV (RFC-4180-ish: quoted fields can contain commas) ──
function parseCsv(text) {
  const rows = []
  let i = 0
  let field = ''
  let row = []
  let inQuotes = false
  while (i < text.length) {
    const ch = text[i]
    if (inQuotes) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i += 2; continue }
      if (ch === '"') { inQuotes = false; i++; continue }
      field += ch; i++; continue
    }
    if (ch === '"') { inQuotes = true; i++; continue }
    if (ch === ',') { row.push(field); field = ''; i++; continue }
    if (ch === '\r') { i++; continue }
    if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; i++; continue }
    field += ch; i++
  }
  if (field.length || row.length) { row.push(field); rows.push(row) }
  return rows.filter(r => r.length > 1 || (r.length === 1 && r[0] !== ''))
}

const csvRows = parseCsv(itemsCsv)
const csvHdr  = csvRows.shift()
const idx = Object.fromEntries(csvHdr.map((h, i) => [h, i]))
const items = csvRows.map(r => ({
  item_id:        r[idx.item_id],
  domain:         r[idx.domain],
  trait_key:      r[idx.trait_key],
  source:         r[idx.source],
  license:        r[idx.license],
  response_scale: r[idx.response_scale],
  key:            parseInt(r[idx.key], 10),
  reverse_score:  r[idx.reverse_score].toLowerCase() === 'true',
  text:           r[idx.text],
}))

// ─── Trait registry pulled from the JSON bank's domain → trait headers ─
// Some traits in the JSON bank may not appear in role_templates.json
// (e.g. emotional_intelligence is in question_bank but not all templates).
// We seed every distinct trait_key from the item bank as a trait row.
const traits = new Map()
for (const [domain, byTrait] of Object.entries(bankJson.domains)) {
  for (const [traitName, t] of Object.entries(byTrait)) {
    traits.set(t.trait_key, {
      trait_key:        t.trait_key,
      name:             traitName,
      domain,
      framework:        t.framework,
      source:           t.source,
      license:          t.license,
      alpha_estimate:   t.alpha_estimate ?? null,
      scored_direction: t.scored_direction ?? null,
      definition:       t.definition ?? null,
      validity_summary: t.validity_summary ?? null,
      sensitive:        !!t.sensitive,
    })
  }
}

// Sanity: every CSV item references a known trait.
const unknown = items.filter(it => !traits.has(it.trait_key)).map(it => it.item_id)
if (unknown.length) {
  console.error(`Items reference unknown traits: ${unknown.join(', ')}`)
  process.exit(1)
}

// ─── Generate a deterministic synthetic norm sample per trait ───────
// We need 100 percentile breakpoints per trait (the value at p=1..p=100).
// To keep the output deterministic + small, we precompute the breakpoints
// directly from an inverse normal of (i/101), mapped onto a 1..5 scale
// with mean=3.0 and sd=0.7 (typical IPIP Big-Five trait-mean dispersion).
// The bounds are clamped to [1, 5] so any single-item percentile is
// representable on the response scale.
//
// This is a SYNTHETIC, DEV_STUB norm — its only purpose is to make the
// dev_stub pipeline produce meaningful variation. Every row carries
// validity_status='dev_stub' + _dev_stub=true; H-2 closes by replacing
// with population_key='nordic_v1' + validity_status='validated'.

// Acklam inverse-normal CDF (mirrors src/lib/personality/scoring.ts).
function invNormCdf(p) {
  const a=[-3.969683028665376e+01,2.209460984245205e+02,-2.759285104469687e+02,1.383577518672690e+02,-3.066479806614716e+01,2.506628277459239e+00]
  const b=[-5.447609879822406e+01,1.615858368580409e+02,-1.556989798598866e+02,6.680131188771972e+01,-1.328068155288572e+01]
  const c=[-7.784894002430293e-03,-3.223964580411365e-01,-2.400758277161838e+00,-2.549732539343734e+00,4.374664141464968e+00,2.938163982698783e+00]
  const d=[7.784695709041462e-03,3.224671290700398e-01,2.445134137142996e+00,3.754408661907416e+00]
  const plow=0.02425, phigh=1-plow; let q,r
  if (p<plow){q=Math.sqrt(-2*Math.log(p));return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5])/((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)}
  if (p<=phigh){q=p-0.5;r=q*q;return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q/(((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1)}
  q=Math.sqrt(-2*Math.log(1-p));return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5])/((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
}

function syntheticBreakpoints({ mean = 3.0, sd = 0.7 } = {}) {
  const out = []
  for (let i = 1; i <= 100; i++) {
    const z = invNormCdf(i / 101)
    const raw = mean + sd * z
    const clamped = Math.max(1, Math.min(5, raw))
    out.push(Math.round(clamped * 1000) / 1000)  // 3 dp keeps the JSON compact
  }
  return out
}

// ─── SQL emission helpers ───────────────────────────────────────────
function sqlStr(s) { return s == null ? 'null' : `'${String(s).replace(/'/g, "''")}'` }
function sqlBool(b) { return b ? 'true' : 'false' }
function sqlNum(n) { return n == null ? 'null' : String(n) }
function sqlArrayText(arr) {
  if (!arr || arr.length === 0) return `'{}'::text[]`
  return `ARRAY[${arr.map(sqlStr).join(',')}]::text[]`
}
function sqlJsonbArrayOfNumbers(arr) {
  return `'${JSON.stringify(arr)}'::jsonb`
}

// ─── Emit ───────────────────────────────────────────────────────────
const INSTRUMENT_KEY = 'personality_v1'
const lines = []
lines.push(`-- AUTOGENERATED by scripts/build-personality-seed.mjs from supabase/seed/.`)
lines.push(`-- DO NOT EDIT BY HAND. Re-run the script if the source CSV/JSON changes.`)
lines.push(`--`)
lines.push(`-- Step 3 of the personality module: seed traits + item bank + role templates`)
lines.push(`-- + synthetic dev_stub norms. The instrument ships as validity_status='licensed'`)
lines.push(`-- because IPIP items are public-domain licensed; everything downstream of the`)
lines.push(`-- (still-synthetic) norms remains dev_stub until H-2 closes.`)
lines.push(``)
lines.push(`begin;`)
lines.push(``)
lines.push(`-- ─── 1. Traits ──────────────────────────────────────────────────────`)
for (const t of traits.values()) {
  lines.push(`insert into public.personality_traits(trait_key,name,domain,framework,source,license,alpha_estimate,scored_direction,definition,validity_summary,sensitive)`)
  lines.push(`values (${sqlStr(t.trait_key)},${sqlStr(t.name)},${sqlStr(t.domain)},${sqlStr(t.framework)},${sqlStr(t.source)},${sqlStr(t.license)},${sqlNum(t.alpha_estimate)},${sqlStr(t.scored_direction)},${sqlStr(t.definition)},${sqlStr(t.validity_summary)},${sqlBool(t.sensitive)})`)
  lines.push(`on conflict (trait_key) do update set name=excluded.name,domain=excluded.domain,framework=excluded.framework,source=excluded.source,license=excluded.license,alpha_estimate=excluded.alpha_estimate,scored_direction=excluded.scored_direction,definition=excluded.definition,validity_summary=excluded.validity_summary,sensitive=excluded.sensitive;`)
}
lines.push(``)
lines.push(`-- ─── 2. Instrument + items ───────────────────────────────────────────`)
lines.push(`-- Global instrument (org_id IS NULL). validity_status='licensed' because IPIP`)
lines.push(`-- items are real, public-domain, LICENSED instruments (matches the enum's`)
lines.push(`-- definition: 'a real instrument's content is plugged in').`)
lines.push(`insert into public.assessment_instruments(org_id, key, name, vendor, licensed_by, validity_status, version, body_json)`)
lines.push(`values (null, ${sqlStr(INSTRUMENT_KEY)}, 'Personality (IPIP + Dark Triad)', 'IPIP-NEO / IPIP-HEXACO / Dark-Triad-style', 'IPIP (Public Domain) / Project-original',`)
lines.push(`        'licensed', '1.0.0',`)
lines.push(`        jsonb_build_object('module','personality','item_count', ${items.length}, 'response_scale','Likert-5 (1-5)','reverse_formula','6 - x'))`)
lines.push(`on conflict (org_id, key, version) do update set name=excluded.name, vendor=excluded.vendor, licensed_by=excluded.licensed_by, validity_status=excluded.validity_status, body_json=excluded.body_json;`)
lines.push(``)
lines.push(`-- 190 items. item_json carries the personality-module-specific metadata`)
lines.push(`-- (trait_key, reverse_score, key direction) so the generic assessment_items`)
lines.push(`-- table doesn't need a personality-specific column.`)
for (const it of items) {
  const itemJson = JSON.stringify({
    trait_key: it.trait_key,
    domain: it.domain,
    reverse_score: it.reverse_score,
    key: it.key,
    source: it.source,
    license: it.license,
  })
  lines.push(`insert into public.assessment_items(instrument_id, key, prompt, item_type, item_json, _dev_stub)`)
  lines.push(`select i.id, ${sqlStr(it.item_id)}, ${sqlStr(it.text)}, 'likert', ${sqlStr(itemJson)}::jsonb, false`)
  lines.push(`  from public.assessment_instruments i where i.org_id is null and i.key = ${sqlStr(INSTRUMENT_KEY)} and i.version = '1.0.0'`)
  lines.push(`on conflict (instrument_id, key) do update set prompt = excluded.prompt, item_json = excluded.item_json;`)
}
lines.push(``)
lines.push(`-- ─── 3. Role templates + per-template traits ─────────────────────────`)
lines.push(`-- After the Step 5 audit fixes, role_templates use a surrogate id PK with`)
lines.push(`-- a partial-unique index on (role_key) where org_id IS NULL. The seed`)
lines.push(`-- uses INSERT...RETURNING + a CTE to capture each template's id, then`)
lines.push(`-- inserts the template_traits keyed on template_id (the FK now used).`)
lines.push(`-- The trigger _personality_template_trait_sync back-fills role_key+org_id.`)
const WEIGHT_CAP = templatesJson.meta?.weight_cap ?? 0.35
const REF        = templatesJson.meta?.match_tolerance_REF ?? 40
for (const r of templatesJson.roles) {
  // Upsert the template. To keep the seed idempotent in the surrogate-PK
  // world, we DELETE any existing global row first (cascades to its
  // template_traits via the FK), then INSERT fresh.
  lines.push(`delete from public.personality_role_templates where role_key = ${sqlStr(r.key)} and org_id is null;`)
  lines.push(`with new_t as (`)
  lines.push(`  insert into public.personality_role_templates(role_key, org_id, title, family, summary, key_citations, weight_cap, match_tolerance_ref, validity_status, _dev_stub)`)
  lines.push(`  values (${sqlStr(r.key)}, null, ${sqlStr(r.title)}, ${sqlStr(r.family)}, ${sqlStr(r.summary)}, ${sqlArrayText(r.key_citations)}, ${WEIGHT_CAP}, ${REF}, 'dev_stub', true)`)
  lines.push(`  returning id`)
  lines.push(`)`)
  // Use a single multi-row INSERT for all traits of this template, sourcing
  // the template_id from the CTE.
  const traitValues = r.traits.map(tt => {
    const isFlag = !!tt.review_flag
    const band_low  = isFlag || tt.band == null ? 'null' : sqlNum(tt.band[0])
    const band_high = isFlag || tt.band == null ? 'null' : sqlNum(tt.band[1])
    const threshold = tt.flag_threshold == null ? 'null' : sqlNum(tt.flag_threshold)
    return `(${sqlStr(tt.trait)}, ${band_low}, ${band_high}, ${sqlStr(tt.direction)}::public.personality_trait_direction, ${sqlNum(tt.weight)}, ${sqlBool(isFlag)}, ${threshold})`
  }).join(',\n         ')
  lines.push(`insert into public.personality_role_template_traits(template_id, trait_key, band_low, band_high, direction, weight, review_flag, flag_threshold)`)
  lines.push(`select new_t.id, x.trait_key, x.band_low, x.band_high, x.direction, x.weight, x.review_flag, x.flag_threshold`)
  lines.push(`  from new_t, (values`)
  lines.push(`         ${traitValues}`)
  lines.push(`       ) as x(trait_key, band_low, band_high, direction, weight, review_flag, flag_threshold);`)
}
lines.push(``)
lines.push(`-- ─── 4. Synthetic dev_stub norms (one row per trait) ─────────────────`)
lines.push(`-- 100 percentile breakpoints per trait. Generated by Acklam inverse-normal`)
lines.push(`-- against (i/101) for i in 1..100, on a 1..5 Likert scale with mean=3.0`)
lines.push(`-- and sd=0.7. CLAMPED to [1,5] so any clean response set has a defined`)
lines.push(`-- percentile. EVERY ROW carries validity_status='dev_stub' and _dev_stub=true.`)
lines.push(`-- H-2 closes by adding rows with population_key='nordic_v1' +`)
lines.push(`-- validity_status='validated'.`)
const breakpoints = syntheticBreakpoints()
for (const t of traits.values()) {
  lines.push(`insert into public.personality_norms(trait_key, population_key, sample_n, breakpoints, validity_status, _dev_stub, source_note)`)
  lines.push(`values (${sqlStr(t.trait_key)}, 'global_dev_stub', 5000, ${sqlJsonbArrayOfNumbers(breakpoints)}, 'dev_stub', true,`)
  lines.push(`  'Synthetic Acklam-derived breakpoints. NOT a real norm sample. H-2 closes by replacing with Nordic-validated rows.')`)
  lines.push(`on conflict (trait_key, population_key) do update set breakpoints=excluded.breakpoints, sample_n=excluded.sample_n, _dev_stub=excluded._dev_stub, source_note=excluded.source_note;`)
}
lines.push(``)
lines.push(`commit;`)
lines.push(``)

writeFileSync(OUT, lines.join('\n'))
console.log(`Wrote ${OUT}`)
console.log(`  traits:         ${traits.size}`)
console.log(`  items:          ${items.length}`)
console.log(`  role templates: ${templatesJson.roles.length}`)
