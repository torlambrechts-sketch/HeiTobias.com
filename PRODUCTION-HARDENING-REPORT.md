# Production Hardening Report

> Output of the production-hardening pass requested in May 2026.
> Scope: every change that did not require real production credentials.
> Option B as accepted by the user: land the code; defer the credential-
> bearing operator steps to `PRODUCTION-LAUNCH-CHECKLIST.md`.

---

## TL;DR

The product can build, type-check, test, and lint clean on a fresh
clone. The CI pipeline blocks deploys on every architectural invariant
that would otherwise rot silently: H-stub discipline, FORCE RLS, search-
path lockdown on SECURITY DEFINER functions, and a grep against the
production bundle for hardcoded demo credentials.

Demo data is now opt-in twice over (env var + empty-DB check). DSR
endpoints and a retention scheduler exist as inert scaffolds that the
operator wires up. Backups, SMTP secrets, Sentry init, and DNS are
documented as handoff items because none of them are code changes.

---

## What changed in this pass

### 1 — Secrets, env, demo-seed guard
* `.env.example` rewritten as the complete production env inventory.
* `src/lib/env.ts` and `src/lib/config.ts` centralise environment
  parsing and *fail loudly* when a required key is missing at boot.
* `src/components/DevOnlySignIn.tsx` renders nothing in production.
* ~14 page files had their hardcoded
  `supabase.auth.signInWithPassword({email: ..., password: 'demo'})`
  calls gated behind `import.meta.env.DEV` so Vite tree-shakes them
  out of the production bundle. INVARIANT-4 verifies this by greping
  the dist output.
* `scripts/seed-demo.mjs` + `scripts/seed-demo-wipe.mjs` enforce a
  **triple guard**: `SEED_DEMO_DATA=true` env var, *and* NODE_ENV ≠
  production (unless the operator passes
  `--i-know-this-is-staging-not-production`), *and* a target DB that is
  empty of real (non-`is_demo_data`) rows. Adding to package.json:
  `seed:demo` / `seed:demo:wipe`.
* Two demo migrations moved out of `supabase/migrations/` into
  `supabase/seed-demo/`. The migration history that auto-applies on
  every deploy no longer carries fake org/role data.

### 2 — Auth hardening
* `vercel.json` ships HSTS (`max-age=63072000; includeSubDomains;
  preload`), CSP locked to Supabase + Sentry, X-Frame-Options DENY,
  X-Content-Type-Options nosniff, Referrer-Policy
  strict-origin-when-cross-origin, Permissions-Policy that denies
  camera/mic/geolocation/payment.
* `public/robots.txt` denies all app surfaces; only the public
  `/architecture.html` reference page is allowed.
* `src/lib/csrf.ts` provides `getCsrfToken()` / `csrfFetch()` so the
  app can send a CSRF header on non-GET writes when the operator
  enables the matching check on the Supabase side.
* `docs/AUTH-HARDENING.md` is the operator checklist for the
  Supabase Dashboard settings (URL config, magic-link expiry, password
  sign-in disabled for end users, rate limits, session length).

### 3 — Email infrastructure
* Migration `20260530400000_prod_email_outbox.sql` adds
  `email_outbox` (template_key, locale, subject, body_text, body_html,
  status, attempts, provider_message_id) and `email_suppressions`
  (email, reason, source_event_json).
* Three SECDEF RPCs with locked `search_path`:
  * `email_enqueue(...)` — checks suppressions, reads org settings
    for from/reply_to, writes the row.
  * `email_mark(...)` — worker callback to update status / record
    provider_message_id.
  * `email_record_bounce(...)` — append to suppressions on hard bounce.
* `src/lib/email.ts` defines `EmailTemplateKey` (7 templates: invite,
  candidate take, password reset, email verification, consent revoke
  ack, admin pending invite, admin leave request) and the FALLBACK_EN
  copy. Localisation chain: per-locale → en → FALLBACK_EN.

### 4 — Observability
* `src/lib/log.ts` exports a structured logger with request_id +
  ambient context (user_id, org_id, action), JSON in prod and human-
  readable in dev. `setSentryCapture()` is the seam to wire up Sentry
  when the DSN is in env. `metric.inc(name, fields)` is the seam for
  custom metrics. The science-defensibility incident metric
  `read_during_seal_count` is one of them.
* Edge functions `api/health.ts` and `api/ready.ts` cover liveness
  + readiness. `/health` is for uptime monitors; `/ready` probes
  audit_log via the service-role key so we know the DB is reachable
  with write-shaped credentials.
* `docs/MONITORING.md` enumerates the alerts, sample Sentry init,
  and uptime monitor recommendations. The PII rule for Sentry is
  documented: **never** send a candidate's email, name, profile, or
  assessment payload to Sentry; redact at the SDK before send.

### 5 — CI/CD
* `.github/workflows/pr.yml` runs typecheck → vitest → build →
  invariant-checks on every PR, with a Postgres 16 service for tests
  that need a DB.
* `.github/workflows/staging.yml` reuses the PR pipeline then deploys
  to staging.
* `.github/workflows/production.yml` reuses the PR pipeline, then
  requires manual approval via the `production-approval` environment,
  then deploys with the explicit guard that **refuses to deploy if
  `SEED_DEMO_DATA=true`**, then runs a post-deploy `/api/health` loop.
* `scripts/invariant-checks.mjs` is the load-bearing CI gate. Four
  invariants, all enforced:
  * **INVARIANT-1** — no `validity_status='validated'` in any
    INSERT/UPDATE in any migration or seed file (CREATE FUNCTION
    bodies are stripped before scanning so the legitimate sign-off
    RPC is not flagged).
  * **INVARIANT-2** — every SECDEF function in migrations declares
    `set search_path = ''`.
  * **INVARIANT-3** — every table with `enable row level security`
    anywhere in the migration history also has a `force row level
    security` somewhere; final state must be FORCED.
  * **INVARIANT-4** — the production dist bundle contains no
    `password: 'demo'` + `linnea.strand@fjordtech.test` pair (proof
    the credential gating tree-shook correctly).
* `supabase/migrations/20260530400100_prod_force_rls_audit_log.sql`
  closes the one outstanding FORCE-RLS gap that INVARIANT-3 surfaced
  (`audit_log` was ENABLEd but never FORCEd).

### 6 — Backups, retention, DSR
* `docs/BACKUPS.md` is the operator runbook for PITR + daily
  logical dumps to an EU-region object-locked S3 bucket, restore drill
  cadence, and the explicit non-goals (no PII in dev snapshots).
* `docs/RETENTION.md` is the retention policy table (employment data,
  candidate data, consent ledger, audit log, email outbox, DSR ledger)
  with windows and triggers.
* `supabase/migrations/20260530400200_prod_data_subject_requests.sql`
  adds `data_subject_requests` (ledger), `retention_runs` (sweep log),
  the `current_person_id()` helper, three SECDEF RPCs (`dsr_open`,
  `dsr_fulfil`, `dsr_export_my_data`), and seeds the `dsr.read` /
  `dsr.fulfil` RBAC permissions onto `org_admin` and `people_ops_admin`.
* `supabase/migrations/20260530400300_prod_retention_sweep.sql` adds
  `retention_sweep()` as a no-op nightly job and best-effort schedules
  it via pg_cron (if the extension is enabled). The no-op writes one
  ledger row per policy key per night, so we know the scheduler is
  alive even though it deletes nothing.
* `api/dsr/request.ts` and `api/dsr/export.ts` are edge wrappers
  around the RPCs. They authenticate by forwarding the Bearer token to
  Supabase; no business logic in the edge layer.

---

## What is deliberately **not** changed

This pass landed code. The operator still needs to:

1. Create the EU-region Supabase project; populate every env var named
   in `.env.example` into the Vercel production environment.
2. Verify the sending domain (SPF + DKIM + DMARC).
3. Enable PITR on Supabase; provision the EU-region S3 backup bucket
   with object lock + KMS; cron the daily dump.
4. Stand up the Sentry EU project; paste the DSN into env.
5. Wire the uptime monitor (UptimeRobot/BetterStack/Pingdom).
6. Sign off the H-stub disclosure (I/O psych advisor), the retention
   table (DPO), and the AI-Act risk classification (legal advisor).
7. Configure the Vercel `production-approval` environment with at
   least two named reviewers.
8. Run the first restore drill.

Everything above maps to a checkbox in `PRODUCTION-LAUNCH-CHECKLIST.md`.

---

## How the H-stub discipline holds in production

Two independent checks fire on every PR before a merge:

1. **DB CHECK constraint** (already present in earlier migrations) —
   a row carrying `validity_status = 'validated'` must also carry the
   real numeric value, and `_dev_stub` must be `false`. Stub rows
   cannot pretend to be validated even by accident.
2. **CI invariant** — INVARIANT-1 scans every migration and seed file
   for INSERT/UPDATE statements that hardcode `validity_status =
   'validated'` and blocks the deploy. Function bodies (where the
   legitimate runtime sign-off lives) are stripped before scanning.

The user-visible UI continues to badge every stubbed surface so a human
reviewer can never mistake a placeholder for validated science. The
launch checklist explicitly asks for a query that confirms zero
`validity_status='validated'` rows in production after first deploy.

---

## Why the demo seed cannot accidentally land in production

Three gates, any one of which is sufficient to refuse:

* **CI workflow** — `production.yml` exits non-zero with a clear error
  if `SEED_DEMO_DATA=true` is set in the production environment, before
  any DB migration runs.
* **Seed script** — `scripts/seed-demo.mjs` refuses to execute unless
  `SEED_DEMO_DATA=true`, `NODE_ENV ≠ production` (or an explicit ack
  flag), *and* the target DB is empty of non-demo rows.
* **Bundle grep** — INVARIANT-4 fails the build if the production dist
  ever contains the demo credentials, catching a future regression where
  a dev sign-in button is left ungated.

---

## What is still risky

In ranked order of how much it would hurt:

1. **No production restore drill has happened yet.** The backup runbook
   describes the right cadence, but until an operator restores from the
   first real backup into a throwaway project and verifies queries,
   "we have backups" is a promise, not a guarantee. Launch gate H-5.
2. **Retention sweep is a no-op by default.** This is the right
   posture — over-deleting is unrecoverable — but somebody must walk
   the dry-run period to "applied" mode after H-6 sign-off. If the
   handover is sloppy, retention silently does nothing for months.
3. **Sentry DSN ships unset.** The logger has the seam, but until the
   DSN is wired, production errors only land in Vercel's function logs.
   That is observable, just not centralised.
4. **CSP allows `'unsafe-inline'` for styles** because shadcn/ui +
   Tailwind both emit inline style attributes for dynamic values. We
   should follow up with a nonce-based policy once the toolchain
   supports it cleanly. The risk surface today is small but non-zero.

---

## Files added or changed (high-signal list)

```
.env.example                                            (rewritten)
.github/workflows/pr.yml                                (new)
.github/workflows/staging.yml                           (new)
.github/workflows/production.yml                        (new)
PRODUCTION-LAUNCH-CHECKLIST.md                          (new)
PRODUCTION-HARDENING-REPORT.md                          (new — this file)
api/health.ts                                           (new)
api/ready.ts                                            (new)
api/dsr/export.ts                                       (new)
api/dsr/request.ts                                      (new)
docs/AUTH-HARDENING.md                                  (new)
docs/MONITORING.md                                      (new)
docs/BACKUPS.md                                         (new)
docs/RETENTION.md                                       (new)
package.json                                            (added seed:demo / seed:demo:wipe)
public/robots.txt                                       (new)
scripts/invariant-checks.mjs                            (new)
scripts/seed-demo.mjs                                   (new)
scripts/seed-demo-wipe.mjs                              (new)
src/components/DevOnlySignIn.tsx                        (new)
src/lib/config.ts                                       (new)
src/lib/csrf.ts                                         (new)
src/lib/email.ts                                        (new)
src/lib/env.ts                                          (new)
src/lib/log.ts                                          (new)
src/main.tsx                                            (validateConfig at boot)
src/pages/**/*.tsx                                      (14 files: demo sign-in gated behind DEV)
supabase/migrations/20260530400000_prod_email_outbox.sql        (new)
supabase/migrations/20260530400100_prod_force_rls_audit_log.sql (new)
supabase/migrations/20260530400200_prod_data_subject_requests.sql (new)
supabase/migrations/20260530400300_prod_retention_sweep.sql     (new)
supabase/seed-demo/01_demo_orgs.sql                     (moved from migrations/)
supabase/seed-demo/02_demo_roles_requisitions.sql       (moved from migrations/)
vercel.json                                             (new)
```

---

**Status:** code changes complete. Operator handoff is via
`PRODUCTION-LAUNCH-CHECKLIST.md`. Do not flip DNS until every box on
that list is ticked.
