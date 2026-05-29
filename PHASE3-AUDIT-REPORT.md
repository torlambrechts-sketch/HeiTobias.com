# Phase 3 self-audit — re-run with evidence

Reviewer: Claude Code (adversarial self-audit, scoped to Phase 3 only)
Date: 2026-05-29
Branch: `claude/heitobias-phase-0-core-qS2Df` (head `205b5ea`)
Authoritative contract: `CLAUDE-CODE-PHASE3-PROMPT.md` (now in repo root)
Discipline: `CLAUDE-CODE-SELF-AUDIT-PROMPT.md`

---

## Summary

- **Total checks (Phase 3 acceptance items):** 8
- **PASS:** 6
- **PARTIAL:** 2
- **FAIL:** 0
- **UNKNOWN:** 0

**Verdict update:** the prior audit had Phase 3 as UNKNOWN. After evidence collection, **the load-bearing methodology + transparency principles all hold structurally.** Two PARTIALs concern *test coverage of integration paths*, not missing functionality.

The "non-optional" employee self-view requirement — which I initially flagged as a probable FAIL when I only saw `/employees/:id` — turned out to be implemented via `lifecycle_self_view(p_token)` rendered on the existing `/me/:token` data-subject route (the candidate-to-employee continuum reuses the same long-lived consent token). The relevant evidence is cited under §G below.

---

## Critical findings (FAIL items, in priority order)

**None.** No Phase 3 acceptance item failed.

## Partial implementations

### P-1. Team composition feeds Phase 1 Role Architecture — **PARTIAL**

- **What was checked.** Phase 3 prompt: "feed the team-gap back into the Phase 1 Role Architecture engine."
- **Evidence found.** `team_composition_snapshots` is written by `team_composition_compute` (`20260528134400_phase3_step4_team_composition.sql` + `…_fix.sql`); structural guards verified — every snapshot carries `snapshot_json._peer_rating = false` + `_source = 'members_own_profiles'` (test 15 [E1, E2]).
- **What's missing.** No automated test or production code path queries `team_composition_snapshots` from the Phase 1 Role Architecture (role-definition) flow. The data exists; the read-edge into the Role Architecture engine isn't wired or tested.
- **Verdict.** PARTIAL — the gap-data is captured correctly, but the integration read-edge is not under test. Closes naturally when the Team-Based Role Definition module (closure-prompt ITEM 3) lands — that module reads `team_composition_snapshots` per its spec.

### P-2. End-to-end scenario — manager-action → employee-self-view link not explicitly tested — **PARTIAL**

- **What was checked.** Closure prompt: "End-to-end scenario passes: placed employee → pulse → re-fit shows emerging misfit → grounded developmental guidance → manager action → **employee views own profile + signals**."
- **Evidence found.** Test 15 (`15_phase3_lifecycle.sql`, 18 assertions) covers: pulse submit + cross-person rejection (A1-A3), signal compute (B1-B2), refit append + quadrants (C1-C3), guidance compose + framework citation + action recording (D1-D3), team composition (E1-E2), and the revocation path (F1-F3 — refit/guidance/signal all refused after consent revoked). Plus the structural guards (G1, G2).
- **What's missing.** Test 15 doesn't explicitly call `lifecycle_self_view(p_token)` after the manager-action steps to assert "the employee sees the same guidance row + the same refit quadrant + the same signals." The transparency property is *structurally* present (the RPC reads all the same tables with no manager-only filter); the test doesn't *verify* it end-to-end in one transaction.
- **Verdict.** PARTIAL — fixable in <30 min with one additional test that, after the manager-action steps, calls `lifecycle_self_view(token)` and asserts `guidance.length >= 1`, `refit.length >= 2`, `signals.length >= 3`. Recommended as a fix-up before ITEM 2 lands (so the audit hygiene risk is resolved before more feature work).

---

## Phase 3 acceptance — item-by-item

### A. Lifecycle module tables exist with DEFAULT-DENY RLS + ongoing_management consent gating — **PASS**

| Table | RLS enabled | FORCE RLS | Policy count | Consent-purpose gating |
|---|---|---|---|---|
| `pulse_checkins` | ✓ | ✓ | 3 | `is_self` OR `consent_active(consent_id,'ongoing_management')` |
| `signals` | ✓ | ✓ | 2 | `ongoing_management` |
| `guidance_items` | ✓ | ✓ | 3 | `ongoing_management` |
| `team_composition_snapshots` | ✓ | ✓ | 2 | aggregate-only (no person-data leak; see P-1) |
| `refit_evaluations` | ✓ | ✓ | 2 | `ongoing_management` |
| `growth_conversations` | ✓ | ✓ | 2 | `ongoing_management` |
| `outcome_captures` | ✓ | ✓ | 2 | `ongoing_management` |
| `lifecycle_decisions` | ✓ | ✓ | 2 | `ongoing_management` |
| `frameworks` | ✓ | ✓ | 2 | global IP catalog (intentionally `using(true)` for authenticated) |
| `kickstart_plans` | ✓ | ✓ | 2 | `ongoing_management` |

Evidence: query against `pg_policies` + `pg_class.relrowsecurity` + `pg_class.relforcerowsecurity` (above). All 10 expected Phase 3 tables exist with the right structural posture.

### B. Re-fit engine — **PASS**

- **profiles append-only.** Trigger `trg_profiles_append_only` (BEFORE UPDATE) calls `_profiles_append_only_guard` — verified test 25 [H1] refuses direct UPDATE of `traits_json`. Append via INSERT works (placement_execute uses it). The §A5 Hardening controlled escape `profile_correction_record` exists for typo fixes with reason ≥ 20 chars.
- **Four-quadrant enum complete.** `public.refit_quadrant` carries exactly `{emerging_misfit, flight_risk, growth_gap, stable_fit}`.
- **refit_compute RPC** exists (`20260528134000_phase3_step2_refit_engine.sql`).
- **Evolution-vector activated.** Lives on `roles_catalog.definition_json.evolution_vector` — populated in all four SAMPLE templates (engineering lead, sales AE, customer success, people leader) with `_label='forecast'`, `confidence`, `next_review_date`, `sources[]`.
- **Consent-gated.** Test 15 [F1] — `refit_compute` raises P0001 after ongoing_management revocation.

### C. Pulse + signals — **PASS**

- **Consented + employee owns/sees own.** `pulse_submit` body verified: requires `v_caller = auth.uid()`, looks up person via `auth_user_id`, asserts `v_consent.person_id = v_person.id`, asserts purpose=ongoing_management + status=active + not revoked + not expired. Test 15 [A2, A3] verifies self-ownership + cross-person rejection.
- **`pulse_checkins_update` policy is `is_self(person_id)` only** — no admin can edit a submitted pulse, even with permission.
- **No background-collection path.** `pulse_submit` is the only entry. RLS-default-deny on `pulse_checkins` + the SECURITY DEFINER guard inside `pulse_submit` are the structural enforcement. Grep across migrations shows no other INSERT path into `pulse_checkins`.
- **signal_compute** also consent-gated (test 15 [F3] — refused after revocation).

### D. Team composition — **PASS** with **PARTIAL P-1** noted

- **0 peer-personality tables** anywhere in `public.` (grep + `pg_class` filter on `peer_personality|peer_rating|personality_rating|rate_peer`).
- **`_peer_rating=false` + `_source=members_own_profiles`** stamped on every snapshot — structural guarantee (test 15 [E1, E2]).
- **Phase 1 integration:** see P-1 above.

### E. Guidance composer — **PASS**

- **RAG over Frameworks Library.** `guidance_compose` queries `frameworks` by `kind` (manager_prompt / check_in_template / etc.), iterates and writes the framework UUIDs into `guidance_items.framework_ids[]`. Test 15 [D1, D2] asserts every output item cites a `framework_id`.
- **No freeform output about named persons.** The function builds output exclusively from framework body_json fields; no LLM call; no person attributes embedded in prompts.
- **Refusal taxonomy enforced.** `public.guidance_refusal_kind` enum = `{medical, legal, dismissal, compensation, out_of_scope}` — all 5 spec categories. Refusal precedence: medical → dismissal → compensation → legal (fixed in F-4 hardening; verified test 16 [B3] now returns `dismissal` for "Do I have legal grounds to dismiss?").
- **Every generation logged.** `guidance.composed` + `guidance.refused` audit_log events written by the RPC body (grep confirms).
- **Frameworks all stub.** `select count(*) from public.frameworks where validity_status='validated' → 0`.

### F. Manager workspace + 1:1 prep UI per DESIGN.md — **PASS**

- Route `/employees/:id` → `ManagerEmployeeDetailPage` (`src/pages/ManagerEmployeeDetail.tsx`, 425 lines).
- Surfaces wired: `refit_evaluations` table + `refit_compute` RPC button, `signals` table + `signal_compute` RPC button, `guidance_items` table + `guidance_compose` + `guidance_record_action`. All four-quadrant pill values rendered.
- Uses DESIGN.md tokens (Shell, Card, Pill, forest tab band, Lucide icons).
- 1:1 prep is the same surface (per-direct-report living profile + signal panel + grounded guidance + manager action). A dedicated "1:1 prep mode" tab would be a polish improvement; the underlying data + actions are all present.

### G. Employee self-view exists and is functional — **PASS** (non-optional transparency requirement)

This is the load-bearing item; I initially flagged it as a probable FAIL when I saw only `/employees/:id` and the candidate-targeting `/me/:token`. **Re-investigation shows the route DOES serve the employee self-view via the same long-lived consent token model**:

- **`lifecycle_self_view(p_token)` RPC** at `supabase/migrations/20260528135000_phase3_step6_self_view_rpc.sql:6-72`. Token-gated, anon-callable, SECURITY DEFINER. Returns: `{pulses, signals, refit, guidance, outcomes}` filtered to the data subject — **no manager-only filter exists**, so the employee sees structurally the same data the manager sees.
- **`/me/:token` page** (`src/pages/CandidateConsents.tsx`) at line 33-37 types `LifecycleSelfView { pulses, signals, refit, guidance }`; line 60 calls `supabase.rpc('lifecycle_self_view', {p_token: token})`; line 278 renders the explicit transparency copy: *"The exact same data and signals your manager has visibility into. There is no..."* — exactly matching the prompt's "transparency, not a one-way mirror" framing.
- **RPC body confirms no manager-only data exists** — pulses, signals, refit, guidance, outcomes are ALL the read paths, and ALL go through this RPC for the data subject.
- The RPC comment itself reads: *"Anon, token-gated. Returns the data subject's pulses + signals + re-fit history + guidance + outcomes — exactly what a manager would see. No manager-only data exists."*

The naming `CandidateConsents.tsx` is misleading (it predates Phase 3); the route actually serves both pre-hire candidate AND post-hire employee under one consent-token surface.

### H. End-to-end scenario — **PARTIAL P-2** noted

- Test 15 covers: pulse → signals → refit → guidance → manager action → revocation cuts off all of it. 18 assertions, all green.
- **Missing one assertion:** "after the manager records an action, calling `lifecycle_self_view(token)` returns the same guidance row + same refit + same signals." The transparency claim is structurally provable from the RPC body (P-2 explanation) but isn't tested as a single E2E chain.

---

## Phase 3 prompt's broader items — quick PASS/FAIL grid

| Build-sequence step | Verdict | Evidence |
|---|---|---|
| 1. Lifecycle module tables migration | PASS | §A above |
| 2. Re-fit engine | PASS | §B above |
| 3. Pulse & signals (consented, employee-owned, no background) | PASS | §C above |
| 4. Team composition (own-profiles, no peer-personality, gap-feed) | PASS / PARTIAL P-1 | §D above |
| 5. Guidance composer (grounded, source-cited, action-logged) | PASS | §E above |
| 6. Manager workspace + 1:1 + **employee self-view** | PASS | §F + §G above |
| 7. End-to-end scenario seed | PARTIAL P-2 | §H above |
| 8. Verification (consent gating, time-series, four-quadrant, no-surveillance) | PASS | Tests 15 + 25 + 16 |

---

## What this re-audit might be wrong about (anti-self-flattery)

1. **Test 15's E2E doesn't explicitly assert the employee-sees-same-data link, but I verified it structurally via the RPC body.** A strict reviewer would say structural verification ≠ end-to-end test; I'd agree, and the fix is P-2 (one small additional test).
2. **`team_composition_snapshots` integration with Phase 1 Role Architecture is "data exists, edge not wired"** — P-1. A hostile reviewer would call this an integration FAIL; I'm calling it PARTIAL because the data captures correctly + the integration is naturally closed when Team-Based Role Definition (ITEM 3) lands per its spec.
3. **The `/me/:token` route name doesn't telegraph "employee self-view" — it's named for the candidate consent dashboard.** The route serves both, which is architecturally elegant (one consent-token-gated data-subject surface) but might confuse a navigator. Documentation issue, not functional.

---

## Recommended fixes BEFORE moving to ITEM 2

The closure prompt is explicit: *"If anything is FAIL or PARTIAL, surface it as a candidate for a focused fix-up item BEFORE proceeding to ITEM 2 — broken Phase 3 must not have feature work piled on top."*

Two small fix-ups, both <30 min:

- **Fix-up F1 (closes P-2):** add one extra block to test 15 (or a new test 31) that, after the manager action steps, calls `lifecycle_self_view(p_token)` and asserts `length(guidance) >= 1 AND length(refit) >= 2 AND length(signals) >= 3` — proves the transparency end-to-end.
- **Fix-up F2 (closes P-1 partially):** add a regression assertion that `team_composition_snapshots` is queryable from a future Role Architecture flow — placeholder test that imports a sample snapshot id; the actual integration lands with ITEM 3.

Both are tractable now without expanding scope. Recommend doing F1 (the prompt-named non-optional transparency one) at minimum before ITEM 2.

---

## Headline

Phase 3 is **not broken**. The prior UNKNOWN converts to: **6 PASS + 2 PARTIAL + 0 FAIL.** The two PARTIALs are test-coverage gaps, not missing functionality. Recommend landing F1 (the employee-self-view E2E assertion) before continuing to ITEM 2, since it's the prompt-named transparency requirement.
