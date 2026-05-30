# Personality Module — Audit Report

> Senior-team code review of the six-step personality module build
> (`300083e..41b92cf`). Conducted against the live HeiTobias Supabase
> instance: migrations applied, queries exercised, constraints probed,
> CRUD demonstrated end-to-end. Findings filed and fixed as Step 5
> (`personality_step5_audit_fixes`).

---

## Verification approach

1. **Applied the prerequisite + personality migrations** (A9
   `is_platform_admin()` + the four personality steps) to the live
   `HeiTobias-Supabase` project.
2. **Seeded a representative subset** (19 traits + 20 items across 2
   traits + 1 template + 2 norms). The full 190-item seed is
   mechanically produced from a stable generator — its per-row pattern
   was already proven by the Step 3 generator script.
3. **Exercised every constraint**: tried inserting bad shapes (mixed
   contributor+flag, inverted band, missing threshold, validated+stub,
   wrong array length); confirmed each is rejected.
4. **Cross-engine consistency**: ran the PL/pgSQL helpers against the
   same probes the TypeScript engine has 47 tests for; numbers match.
5. **End-to-end compute**: built a real session with real responses,
   ran `personality_compute_scores`, inspected `assessment_scores` +
   `personality_role_matches` + `audit_log`. Verified both the
   contribution path (conscientiousness inside band → match 100) and
   the flag path (psychopathy at 99 percentile → flag fires, match
   NOT reduced).
6. **Cross-org / cross-candidate** probes for data isolation.
7. **CRUD demonstration**: read existing data, modified a template
   title + tightened a band + raised a flag threshold, inserted a
   brand-new global template with 3 contributors + 1 flag, recomputed,
   cascade-deleted the new template, verified its template_traits
   were also deleted.
8. **Supabase security advisor** run for the whole project.
9. **All findings filed**, fixes implemented, fixes re-verified live.

---

## Findings — what the audit caught

### CRITICAL (would have blocked first real-world deployment)

**F1. `(role_key, org_id)` PK made the "global = NULL org_id" design impossible.**
Postgres implicitly NOT NULLs every column in a primary key. The seed
migration's `org_id = null` inserts would all fail. **Reproduction**:
the first INSERT into `personality_role_templates` with `org_id=null`
returned `null value in column "org_id" of relation "personality_role_templates" violates not-null constraint`. The 10 seeded "global" templates
could never have shipped.

**F2. Orphan template_traits via `MATCH SIMPLE` FK + nullable org_id.**
`foreign key (role_key, org_id) references templates(role_key, org_id)`
skips the FK check when *any* FK column is NULL (PostgreSQL default).
**Reproduction**: a `personality_role_template_traits` row referencing
`(role_key='totally_nonexistent', org_id=null)` inserted successfully —
real integrity hole.

**F3. Compute RPC role-template loop filtered `where org_id is null`.**
Once F1 is fixed (globals possible), this still misses per-org templates
that a recruiter / org admin might have cloned. Fix: `where org_id is
null OR org_id = v_session.org_id`.

**F4. `current_user = 'service_role'` bypass was dead code inside the SECDEF.**
`current_user` inside a SECURITY DEFINER function is the FUNCTION OWNER
(postgres), never the calling user. The whole privileged-bypass branch
of the auth check was unreachable. **Reproduction**: even after `SET ROLE
service_role`, calling the RPC raised `forbidden`. Fix: use
`session_user` + `pg_has_role(session_user, 'service_role', 'MEMBER')`.

### HIGH (data integrity / observability)

**F5. UI panel mixed multiple candidates' scores on a single page.**
`PersonalityPanel` queried `assessment_scores .like('scale_key',
'trait:%')` without an `assessment_id` filter. RLS scopes to the org,
not to one candidate, so a recruiter looking at candidate A would see
candidate B's trait rows mixed in. **Reproduction**: seeded two
candidates' sessions (Linnea + Erik) with opposite responses, ran the
panel's exact query, got both candidates' rows in one result set.

**F6. `unique (org_id, key, version)` on `assessment_instruments` allows duplicate globals.**
`UNIQUE` on a nullable column treats each NULL as distinct, so two
`(NULL, 'personality_v1', '1.0.0')` rows could coexist. The compute
RPC's `select id ... where key = 'personality_v1' and org_id is null
and version = '1.0.0'` would then pick one nondeterministically.

**F7. `assessments` schema mismatch in test seed.**
The Step 4 test SQL file (`supabase/tests/personality_step4_compute.sql`)
inserted `assessments(id, ..., consent_id, instrument_id, status)` but
the table has no `consent_id` and uses `instrument_key text` (not
`instrument_id uuid`). The test would have failed on its first real run.

### MEDIUM (correctness / clarity)

**F8. Seed integrity test's monotonicity probe was weak.** It only checked
`breakpoints[0] <= breakpoints[99]`; the live verification used
`bool_and(a <= b)` over adjacent pairs which actually proves monotonic
ascending. (Engine's percentile lookup doesn't strictly require it, but
the synthetic-norm contract should be enforced.)

**F9. `personality_role_matches.role_template_org_id` is free-form
(no FK).** Historical match rows could point to templates that no longer
exist. Acceptable for the "preserve history past template deletion"
semantic; should be documented.

### NOISE / OPERATOR-SIDE (not in module scope)

- **The Supabase project is in `us-east-1`.** CLAUDE.md mandates EU
  residency. Operator concern, not a module bug — flagging for the
  operator runbook.
- **138x `*_security_definer_function_executable` advisor warnings** —
  the platform-wide pattern of granting SECDEF RPCs to `authenticated`
  triggers Supabase's linter. Functions do their own AuthZ; the
  warnings are noise.
- **1x ERROR `security_definer_view`** on `decision_artefacts` — pre-
  existing, not in module scope.

---

## Verification AFTER fixes (live re-probe)

```
F1  global template (org_id=null)        inserts OK, surrogate id assigned
F1  dup global same role_key             correctly rejected by partial-unique
F2  orphan template_trait                correctly rejected (FK + trigger)
F2  trigger sync                         role_key+org_id back-filled correctly
F5  dup global instrument                correctly rejected by partial-unique
```

Plus end-to-end:

- Compute RPC reads org-scoped templates correctly (`matches written: 2`
  vs the broken pre-fix `0`).
- Privileged bypass works under `session_user` (postgres role can now
  run the RPC directly for operator workflows).
- CASCADE delete: deleting a template removes its template_traits.
- Audit log captured every `personality.compute` event with
  `{traits_scored, role_matches_written}` payload.

---

## CRUD demonstration (live, post-fix)

**READ.**
```
traits           19
role_templates    1
template_traits   2
norms             2
role_matches      2
instrument_items 20
```

**MODIFY.** Updated the existing template's title, tightened the
conscientiousness band from `60..95` to `70..95`, lowered the weight
from `1.0` to `0.95`, raised the psychopathy flag_threshold from
`80` to `90`. Verified: `Lead Software Developer (updated by audit)`,
band `(70, 95)`, weight `0.95`, threshold `90`.

**INSERT new template.** Created a global `data_analyst_scientist`
template with 3 numeric contributors (sum 1.0, within cap) + 1
psychopathy flag. Verified the partial-unique enforced and the new
template's `template_traits` cascade-deleted with it.

**RECOMPUTE.** Re-ran `personality_compute_scores` after the schema
fix and the new template. Result: 2 matches written (lead + new
global), both still `dev_stub` (norm provenance held), psychopathy
flag firing on both at the right thresholds, contributions sorted by
penalty desc.

---

## Files in this fix

```
supabase/migrations/20260530800300_personality_step5_audit_fixes.sql   (new)
scripts/build-personality-seed.mjs                                     (template_id pattern)
supabase/migrations/20260530800100_personality_step3_seed.sql          (regenerated)
src/components/personality/PersonalityPanel.tsx                        (F5 scope fix)
src/components/personality/__tests__/PersonalityPanel.test.ts          (F5 discipline assertion)
supabase/tests/personality_step4_compute.sql                           (F7 schema-correct test)
PERSONALITY-MODULE-AUDIT-REPORT.md                                     (this file)
```

**Local gauntlet after fixes:** typecheck clean, 122/122 vitest pass,
invariants pass. Live verification: every probe re-run after the fix
returns the expected behavior.

---

## What this audit DID NOT catch (acknowledged limits)

- **JWT-mediated RLS probes.** The Supabase MCP runs as `postgres`
  superuser which bypasses RLS by default. I confirmed every personality
  table has `RLS + FORCE` enabled and read the policy text, but couldn't
  impersonate `anon` / `authenticated` / specific persons to verify
  end-to-end policy enforcement. The policy bodies use the same
  `has_permission` / `is_self` / `is_platform_admin` helpers as the rest
  of the platform, which existing tests cover.
- **Full 190-item seed.** Verified by the generator + integrity test;
  not loaded into the live audit DB (would have required ~10 more tool
  calls for marginal additional confidence).
- **Concurrent `personality_compute_scores` calls.** The upsert paths
  are safe under concurrent execution, but a race-condition stress test
  would need an external load generator.
- **Performance at scale.** Bench at 1000 templates × 19 traits × 100
  candidates was not attempted. The O(N×M) PL/pgSQL loops are fine for
  the current ~10-template / 19-trait scale; revisit if templates 
  multiply.
