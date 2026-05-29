import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it, expect } from 'vitest'

const __filename = fileURLToPath(import.meta.url)
const here = dirname(__filename)
const ROLE_PROFILE_DIR = join(here, '..')

function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1')
}

const dialog        = readFileSync(join(ROLE_PROFILE_DIR, 'UseForRequisitionDialog.tsx'), 'utf8')
const dialogCode    = stripComments(dialog)
const pageHeader    = readFileSync(join(ROLE_PROFILE_DIR, 'PageHeader.tsx'), 'utf8')
const pageHeaderCode = stripComments(pageHeader)

describe('CP4 — Use-for-requisition picker', () => {
  // ============ T57 — Dialog enforces ≥20-char rationale ============
  it('[T57] UseForRequisitionDialog gates submit on a >=20-char rationale counter', () => {
    expect(dialogCode).toMatch(/const\s+MIN_RATIONALE\s*=\s*20/)
    expect(dialogCode).toMatch(/rationale\.trim\(\)\.length\s*>=\s*MIN_RATIONALE/)
    expect(dialogCode).toMatch(/disabled=\{[^}]*!valid/)
  })

  // ============ T58 — Picker disables rows that already match this role ============
  it('[T58] Dialog visually disables requisitions already pointing at this role (no-op suppress)', () => {
    expect(dialogCode).toMatch(/const\s+same\s*=\s*r\.role_id\s*===\s*row\.id/)
    expect(dialogCode).toMatch(/disabled=\{same\}/)
    expect(dialogCode).toMatch(/already attached/i)
  })

  // ============ T59 — Dialog uses the SECDEF RPC, never direct UPDATE ============
  it('[T59] Dialog uses rpc_requisition_attach_role; no direct .update on requisitions', () => {
    expect(dialogCode).toMatch(/rpc_requisition_attach_role/)
    expect(dialogCode).not.toMatch(/\.from\(['"]requisitions['"]\)[\s\S]{0,40}\.update\b/)
  })

  // ============ T60 — On success, navigate to the requisition ============
  it('[T60] On success, dialog navigates to /requisitions/<picked.id>', () => {
    expect(dialogCode).toMatch(/navigate\(`?\/requisitions\/\$\{picked\.id\}/)
  })

  // ============ T61 — PageHeader trigger is gated on template/template-org ============
  it('[T61] PageHeader "Use for requisition" button is disabled for templates', () => {
    // Must check row.is_template OR row.org_id === null in the disabled clause.
    expect(pageHeaderCode).toMatch(/disabled=\{row\.is_template\s*\|\|\s*row\.org_id\s*===\s*null\}/)
    // The legacy "coming in CP6 follow-up" stub copy is gone.
    expect(pageHeaderCode).not.toMatch(/coming in CP6 follow-up/i)
  })

  // ============ T62 — PageHeader actually mounts the dialog conditionally ============
  it('[T62] PageHeader opens the dialog on click and mounts <UseForRequisitionDialog> when open', () => {
    expect(pageHeaderCode).toMatch(/setDialogOpen\(true\)/)
    expect(pageHeaderCode).toMatch(/\{dialogOpen\s*&&\s*<UseForRequisitionDialog/)
  })
})
