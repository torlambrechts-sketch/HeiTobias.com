# Ops-layer external review — senior dev + design agency pass

> Reviewed 2026-05-29, branch `claude/heitobias-phase-0-core-qS2Df`.
> Walked the ops-layer + gap-closure additions as two independent
> reviewers would. Companion to the earlier `EXTERNAL-REVIEW.md` from
> the original closure pass; focused on what landed AFTER that review
> (Ops Part 1, Part 2, the architecture-driven gap closures).
> Findings categorized **fix-now** (applied this pass), **fix-later**
> (named, deferred), or **accept** (intentional).

---

## Senior dev review

### What I checked

```
* TODO/FIXME/XXX in src/                   → 1 hit (RoleProfile placeholder copy)
* console.log calls                        → 0
* dangerouslySetInnerHTML usage            → 3 (all read en.json — trusted source)
* window.alert / .confirm / .prompt        → 12 (UX smell — see below)
* <img> without alt attribute              → 1 (BrandStrip — fixed)
* Files >300 lines (refactor candidates)   → 6
* dead `to="#"` nav links                  → 7 (fixed to existing surfaces)
* SQL test coverage                        → 72 SQL + 65 vitest = 137/138 PASS
* RLS policies on new tables               → all present (notifications, integration_*)
* SECURITY DEFINER + search_path=''        → consistent across 40+ RPCs
* Rationale ≥20-char gate                  → present on every consequential admin RPC
```

### Findings

**fix-now (applied this pass)**

1. **Dead Shell nav links** — 7 `<NavSub to="#">` items were stubs.
   Re-pointed to nearest existing surface (Role library → /roles/dd…001,
   Re-fit/composition/1:1 prep → /team, Insights → /admin) so every
   menu item navigates somewhere meaningful.
2. **BrandStrip `<img alt="">`** — now `alt="{org_name} logo"` (a11y).
3. **Demo guided tour expanded** 5 → 8 stops covering Part 1 + Part 2 +
   architecture HTML in one continuous walkthrough.

**fix-later (documented)**

4. **12 window.alert/confirm/prompt calls** across WorkspaceAdmin, ReconciliationPanel,
   MePage. Break visual coherence + not keyboard-traversable. Pattern fix:
   `<RationalePrompt>` modal component to replace prompt(). Single-day work.
5. **WorkspaceAdmin.tsx is 1044 lines.** Internal sub-helpers + tabs should be
   split into separate files for maintainability.
6. **RoleProfile non-Profile tabs are placeholder TODOs.** Each has a real
   underlying surface; threading them in is per-tab focused work.
7. **Bundle main 446 kB** — at the warning threshold. Sections.tsx (477 LOC)
   from RoleProfile eagerly imported; WorkspaceAdmin sub-tabs likewise.
8. **Per-route module gating only on `/team-def/*`** — others rely on RLS at
   the data layer. Adding UI gating elsewhere is belt-and-suspenders.

**accept (intentional)**

9. **dangerouslySetInnerHTML in 3 components** — all read from `en.json`
   (developer-authored, version-controlled, NOT user input).
10. **No tests on the new Part 2/3 page components** — the SECDEF RPCs they
    call are SQL-test-covered; component-render tests would test React, not
    business logic.

### Defensibility holds

- No fabricated science: every score/threshold/norm carries `validity_status = 'dev_stub'`
- Peer-personality block at schema CHECK + UI body copy (both belts intact)
- decision_artefacts written on every consequential admin write (≥20-char rationale)
- Audit log immutable + insert-only; export writes its own audit row
- RLS holds on all new tables: notifications, integration_connectors, integration_sync_runs, admin_decisions
- SECURITY DEFINER + `search_path = ''` consistent across all RPCs

---

## Design agency review

### What I checked

```
* Navigation coherence                     → 7 dead links repaired (fix-now)
* Visual system consistency                → Tailwind tokens consistent;
                                              DESIGN.md accents present
* Empty / loading / error states           → present on every async surface
* Copy tone (developmental framing)        → preserved on /team, /me,
                                              SurveillanceGuardrail
* Surveillance guardrail visibility        → body copy (not tooltip)
                                              on team-def Stage 2 + /team
* Reference architecture available         → /architecture.html ships in dist,
                                              linked from Home + Demo
* Demo banner                              → visible to demo-org users
```

### Findings

**fix-now**
- Demo guided tour rewritten as 8 stops covering the full Part 1 + Part 2 +
  architecture surfaces — continuous narrative now.

**fix-later**
- Locale switching is structurally complete; en.json has the 11 load-bearing
  keys; Nordic dictionaries are HANDOFF (localiser engagement).
- Mobile layout pass: admin tables don't reflow cleanly on narrow viewports.
- Empty-state illustrations would lift perceived quality.
- DemoBanner could use session-persistent dismiss (cookie).
- BrandStrip on `/take/<token>` only applied to the consent phase, not intro/
  item/done.

**accept**
- Architecture HTML's brutalist visual identity (Fraunces/Archivo/Space Mono)
  is deliberately different from the app's Tailwind feel. Different audience,
  different doc. Right call.

### Verdict from the agency seat

Architecture coherence ✓ · Navigation coherence ✓ (post-fix-now) ·
Surveillance guardrail visible ✓ · Developmental framing consistent ✓ ·
Demo flows believably ✓.

---

## Final closure summary (ops layer + gaps)

| Step | Item | Result |
|------|------|--------|
| 1 | Notification dispatch outbox | DB scaffold + admin Notifications tab; transports operator-wired |
| 2 | HRIS connector registry | DB scaffold + admin Integrations tab; vendor APIs operator-wired |
| 3 | Per-route module gating (`/team-def/*`) | `useOrgModule` + `<ModuleGate>` + DB trigger |
| 4 | `/me` consent revoke by purpose | `consent_revoke_by_purpose` RPC + UI button |
| 5 | Brand-aware `/take/<token>` | `assessment_take_brand` RPC + `<BrandStrip>` |
| 6 | Demo guided-tour update | 5 stops → 8 stops covering full surface |
| 7 | External review (this file) | Senior dev + agency double-pass |

### Test surface (post-this-pass)

```
SQL (pgTAP):
  31  Phase 3 closure fix-ups               10/10
  32  Team-Based Role Def CP3.1               9/9
  33  Team-Based Role Def CP3.3               8/8
  34  Team-Based Role Def CP3.4               7/7
  35  Team-Based Role Def CP3.5               7/7
  36  Use-for-requisition attach              6/6
  37  Ops Part 1 admin operations             8/8
  38  Ops Part 1 demo discipline              6/6
  39  Ops Part 2 surfaces                     5/5
  40  Ops Part 3 gap closures                 6/6
```

**Total SQL: 72 / Vitest: 65/66 / Grand total: 137 of 138 PASS** (1 pre-existing
env-var smoke fail unrelated to this work).

Typecheck + build clean. Main bundle 446 kB; 26 per-route chunks.

### What still stays out of scope

- **HANDOFF H-1 to H-10** — expert-owned science (codebase REFUSES to fabricate)
- **Operator items** — EU-region Supabase, real SMTP / Slack / HiBob credentials,
  audit retention policy as code, CI runner wiring
- **Phase 4 modeling surfaces** — gated behind un-granted `modeling.signoff`
- **Fix-later items above** — visual polish, refactors, modal-replacing the
  prompt() calls

### Next moves (not code)

1. **Design-partner conversations** — `/demo` + `/architecture.html` are the
   walkthrough kit. The honest stub seam is a feature, not a bug.
2. **I/O psychologist engagement** — closes H-1 / H-2 / H-3 / H-7 / H-10.
3. **Legal / AI-Act advisor engagement** — H-3 + H-6.
4. **Operator hand-off** — pick EU Supabase region, SMTP vendor, audit retention
   window. Integrations tab gives the operator a check-list.
5. **Nordic localiser engagement** — fill nb-NO / sv-SE / da-DK dictionaries.

The architecture document at `/architecture.html` is honest reference — every
layer + component maps to either built code, a documented stub seam, or an
explicitly out-of-scope item.
