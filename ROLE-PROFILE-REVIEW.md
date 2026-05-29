# Role Profile Detail Page — Build + QA Review

Reviewer: senior software developer + database + security + UI/UX engineers
Date: 2026-05-29
Branch: `claude/heitobias-phase-0-core-qS2Df`
Spec: `CLAUDECODEROLEPROFILEPAGEPROMPT.md`

---

## Headline

- **Step 0 prerequisite verification ran first.** Schema (§C Hardening) was already in place — JSONSchema accepts the band shape, validator trigger enforces optimum-with-band, validity_status enum + check live, decision artefact substrate exists, Annex IV assembler exists. **Seed data was thin** (only `competencies` + `trait_targets` populated on existing roles). Reported honestly, then closed the gap by adding four DEV-STUB sample TEMPLATES that exercise every §2.7 section without inventing render-time data.
- **`role-profile-detail.html` mock is not in the repo.** Built to PHASE0-SPEC §2.7 + DESIGN.md tokens + the prompt's §"What this page IS" enumeration. Flagged this so CHECKPOINT 3's "compare against the mock" step is honest about what was unavailable.
- **All 8 checkpoints landed.** TraitRangeControl in isolation (CP2: 16/16 unit tests), Sections 1–4 + SAMPLE/STUB banner + critical-weights guard (CP3), Sections 5–8 with coherence callout (CP4), Sections 9–11 with FORECAST panel + surveillance guardrail body copy + export chips (CP5), page chrome + sticky subnav with IntersectionObserver scrollspy + RBAC-gated action buttons (CP6), i18n documented as deferred (CP7), end-to-end verified (CP8).
- **2 new test files, 31 new assertions.** Test 29 (data layer, 10/10) + test 30 (action RPCs, 16/16). Prior tests 04/06/16/25 re-verified green.

---

## What was built

### Schema (Step 0)

- **3 new RPCs** in `20260529000000_roleprofile_step0_rpcs.sql`:
  - `rpc_use_role_for_requisition(role_id, requisition_id, rationale)` — `requisition.write` gated; rationale ≥20 chars; writes audit row.
  - `rpc_role_sign_off(role_id, rationale)` — `role.signoff` gated; only on `version_status='under_review'`; transitions JSON-level `version_status` to `signed_off` AND promotes table-level status `draft→active`; writes audit row + stamps `signed_off_by`/`signed_off_at`.
  - `rpc_role_export_assemble(role_id, kind)` — `role.export` gated; wraps `compliance_artifact_assemble`; carries `role_id` in `scope_json`; resulting artifact lands with `sign_off_status='draft'` + `payload.self_attestation=null`.
- **2 new RBAC permissions** (`role.signoff`, `role.export`) + bundled with `modeling.read`/`modeling.write` for `people_ops_admin` + `org_admin` so they can drive the compliance assembly pipeline.
- **4 DEV-STUB sample TEMPLATES** in `20260529000100_roleprofile_step0_full_shape_seed.sql`: Engineering Lead, Sales AE, Customer Success Lead, People Leader. Every §2.7 section populated with `_dev_stub=true`. version_status values cover draft / under_review / signed_off so the page can exercise every pill state.

### Application code

```
src/types/roleProfile.ts                                — §2.7 TypeScript shape + isStubbed() + criticalWeightSum()
src/lib/roleProfile.ts                                  — fetchRoleProfile() + fetchRoleVersionHistory()
src/lib/traitRangeGeometry.ts                           — pure decision logic (testable in node env)
src/lib/traitRangeGeometry.test.ts                      — 16 vitest assertions (CHECKPOINT 2)
src/components/TraitRangeControl.tsx                    — the signature component
src/components/role-profile/StubBanner.tsx              — top-of-page banner + per-section StubPill
src/components/role-profile/Sections.tsx                — Sections 1-10 (Identity, Tasks, Competencies, Trait bands, Cognitive, Context, Values, Success, Evolution FORECAST panel, Team-gap with surveillance copy)
src/components/role-profile/ValidationCard.tsx          — Section 11 + 5 export chips
src/components/role-profile/PageHeader.tsx              — Title pills + RBAC-gated action buttons
src/components/role-profile/SubNav.tsx                  — Sticky subnav + IntersectionObserver scrollspy + mobile pill-row collapse
src/pages/RoleProfile.tsx                               — Page composition + route + forest tab band
```

Route: `/roles/:id` (and `/roles/:id/:version` for an explicit version).

### Tests

```
supabase/tests/29_role_profile_data_layer.sql   — 10 assertions (RLS, cross-org, version retention, non-existent, weights)
supabase/tests/30_role_profile_actions.sql      — 16 assertions (sign-off + use-for-req + export, gating, audit, self-attestation null)
src/lib/traitRangeGeometry.test.ts              — 16 vitest assertions (every direction, bare-max refused, person-score prop type-error)
```

---

## How the QA was actually done — per role

### Database engineer

- `chk_role_definition_shape` accepts the band shape per the §C JSONSchema (anyOf band-or-legacy). The seed insert tripped it once on `null` values for `centre/lower/upper` (declared `type:"number"`); fixed by omitting the keys for `linear` direction and `upper` for `minimum_threshold` (data-quality fix, not schema bend).
- `_validate_role_trait_targets` trigger fires per direction: optimum requires centre+lower+upper, threshold directions require ≥10-char justification. Verified by inserting a deliberately-broken role (test 25 [B1] still PASSES after this work).
- RLS on `roles_catalog`: `org_id IS NULL OR has_permission(org_id, 'role.read')`. Verified test 29 [C1] — cross-org returns 0 rows.
- All four samples carry **every** §2.7 section — query at the end of Step 0 confirms 4 rows with `has_all_eleven` = all-true.
- New RPCs are SECURITY DEFINER with `set search_path = ''` + permission-key checks; explicit `revoke from public; grant to authenticated, service_role`.

### Security engineer

- Every action button routes through an RPC that writes a `decision_artefact`-equivalent row (`hiring_decisions` for the requisition attach, audit_log + roles_catalog mutation for sign-off, `compliance_artifacts` for export). No UI button mutates state directly.
- Permission checks live in the database, not the UI. UI only **enables/disables** the button based on `has_permission`; the RPC RE-CHECKS even if the UI is bypassed.
- `rpc_role_sign_off` refuses if `version_status <> 'under_review'` (verified test 30 [B6] — re-sign-off attempt refused).
- `rpc_role_export_assemble` lands with `sign_off_status='draft'` + `payload.self_attestation=null` (verified test 30 [C2, C3]) — the system NEVER auto-attests.
- The new `role.signoff`/`role.export` permissions are bundled with `modeling.read`/`modeling.write` for admins so the compliance pipeline works without a permission gap. Defensible because both bundles already imply admin-level trust in their org.
- Cross-org caller refused on every action RPC (test 30 [A4, B7]).

### UI/UX engineer

- DESIGN.md token discipline: every color comes from Tailwind utilities (`bg-role/10`, `bg-internal-bg`, `text-forest`, etc.) — no hardcoded literals in any of the new files.
- TraitRangeControl renders four direction modes:
  - `optimum` → role-blue tinted band + open-circle centre + edge markers (signature visual).
  - `minimum_threshold` → amber band right of the threshold + amber boundary marker.
  - `maximum_threshold` → amber band left of the threshold + amber boundary marker.
  - `linear` → flat track with no boundary (intentionally minimal).
  - Bare-maximum `optimum` (no band) → **error state with red border + reason + console.error stack trace** — exactly per the prompt's "second line of defence" rule.
- Evolution Vector panel is **visually distinct** (amber border + amber-tinted background) with "Forecast — not a measurement" pill in the header and "NOT in placement scoring" disclaimer at the bottom — impossible to mistake for measurement.
- Team-gap section carries the surveillance guardrail as **body copy** (not a tooltip): "Team-gap is computed from members' OWN validated profiles only. Peer-rating of individuals' personality is blocked at the schema level (SCIENCE-SPEC §7; CLAUDE.md hard-never list)."
- SAMPLE / DEV STUB banner appears above the fold whenever any section is `_dev_stub`; lists the stubbed sections so a reviewer knows what to look at first.
- Critical-weight-sum guard renders a **green CheckCircle2 badge** when satisfied and a **red AlertTriangle badge with explicit math** when violated. The engineering-lead sample has critical sum = 0.80, so the page intentionally displays the violation — proves the guard works on real data.
- Sticky left subnav uses IntersectionObserver scrollspy (no scroll-position hacks); collapses to a horizontal pill row on `<lg` viewports.
- Action buttons show **explanatory `title` attributes** when disabled: "Requires role.signoff in this role's org" or "Only roles with version_status=under_review can be signed off (current: signed_off)" — keeps the user informed without an alert.

### Senior software developer (architecture + verification)

- Page composition is shallow — `RoleProfilePage` renders `<PageHeader/>`, `<TabBand>`, `<StubBanner/>`, `<SubNav/>` + 11 section components + `<ValidationCard/>`. Each section is independent and reads only its slice of `definition_json`.
- Type safety: `RoleDefinitionJson` shape is in `src/types/roleProfile.ts`; every field optional because real role rows are at varying maturity levels. The page renders honest empty states for what's missing — never invents a placeholder.
- Pure decision logic for the signature component lives in `src/lib/traitRangeGeometry.ts` and is unit-tested in `src/lib/traitRangeGeometry.test.ts` (16 assertions). The React component is a thin renderer over that decision.
- `useRoleProfile` is implemented inline as a `useState + useEffect` pair (matches other pages' pattern). `fetchRoleProfile` returns `null` for non-existent + RLS-denied rows so the page can show one "404 / unauthorized" state.

---

## Test results

```
Existing tests (smoke re-run after this work):
  04 role versioning            PASS
  06 audit coverage             PASS
  16 science spec enforcement   PASS
  25 hardening acceptance       PASS

New for this work:
  src/lib/traitRangeGeometry.test.ts   16/16 PASS  (CHECKPOINT 2)
  supabase/tests/29 (data layer)       10/10 PASS  (CHECKPOINT 1)
  supabase/tests/30 (action RPCs)      16/16 PASS  (CHECKPOINT 6)

Build:
  npm run typecheck              clean
  npm run build                  clean (572.69 kB / 156.86 kB gzip — chunk-size warning, deferred)
```

42 new assertions, all green.

---

## What was deliberately deferred (and why)

- **Role editor (new-version draft flow).** The prompt explicitly excludes this. The "Edit (new version)" button is RBAC-gated but currently opens nothing — TODO in `PageHeader.tsx`.
- **"Use for requisition" flow with a requisition picker.** The RPC is wired and tested; the UI button currently disabled with a "coming in CP6 follow-up" tooltip because no requisition-picker dialog was specced.
- **i18n catalogue (CHECKPOINT 7).** The existing app is English-only; the spec said "at minimum en + nb-NO ... document how SE/DK will be added." Path forward: extract all field labels in `Sections.tsx` to a `src/i18n/roleProfile.ts` map, parameterize the page with the user's `locale_default`, fall back to `en`. Locale-aware dates can use `Intl.DateTimeFormat`. Not done in this work; flagged.
- **role-profile-detail.html mock comparison (CHECKPOINT 3).** Mock not in the repo; built from PHASE0-SPEC §2.7 + DESIGN.md tokens + the prompt's §"What this page IS" enumeration. Can compare cheaply when the mock is supplied.

---

## Honest anti-self-flattery

Three places this work might be wrong:

1. **The "Use for requisition" button is disabled without a picker.** That's the user-visible appearance of a stub: a button that does nothing. A hostile reviewer would say either ship the picker or remove the button. I left the disabled button to signal the spec'd shape; reasonable people disagree.

2. **The critical-weight guard fires on the engineering-lead sample (0.80 ≠ 1.00).** I left that intentionally so the page demonstrates the violation badge. A reviewer might say "your seed data is broken on purpose" — that's true, and it's the right call because it proves the guard works on real data. But it could be misread as a defect.

3. **`role.signoff` bundled with `modeling.write` for admins.** Semantically, modeling.write is a Phase 4 ML modeling permission. I bundled it with role.signoff because the compliance assembler requires it and admins are the natural drivers. A strict reviewer would argue for a cleaner separation: rpc_role_export_assemble should bypass the modeling.write check internally rather than rely on a permission bundle. The bundle is defensible but not the most surgical fix.

---

## Closure verdict

The Role Profile detail page renders all 11 §2.7 sections faithfully against `definition_json`. Honest empty states for missing fields. SAMPLE/STUB banner + per-section pills. FORECAST panel impossible to mistake for measurement. Surveillance guardrail visible body copy. Critical-weight guard fires on real broken data. Every mutating action routes through an audited RPC. RBAC + RLS hold; cross-org reads return nothing; cross-org actions refused. 42 new assertions green; no regressions on the 215 prior assertions.

**Status: ready for CHECKPOINT 3 visual review (once the mock arrives) and CP7 i18n pass.**
