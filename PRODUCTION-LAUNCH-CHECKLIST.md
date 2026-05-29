# Production Launch Checklist

> Single page. Every item is a *blocker*. Do not flip the DNS until every
> box is ticked, every owner has signed, and the most recent CI run on
> `main` is green.

---

## H-0 — Secrets & environment

- [ ] `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
      `SUPABASE_DB_URL` set in the Vercel **production** environment.
- [ ] `SESSION_SECRET` (32-byte random) and `CSRF_SECRET` (32-byte
      random) set; values not in any repo, dev .env, or shared doc.
- [ ] `APP_URL = https://app.heitobias.com`,
      `ALLOWED_ORIGINS = https://app.heitobias.com` set.
- [ ] `SMTP_PROVIDER`, `SMTP_HOST`, `SMTP_USER`, `SMTP_PASS`,
      `FROM_EMAIL`, `REPLY_TO_EMAIL` set; FROM_EMAIL is on a verified
      sending domain with SPF + DKIM + DMARC aligned (see
      `docs/AUTH-HARDENING.md`).
- [ ] `SENTRY_DSN` set; project region = EU.
- [ ] **`SEED_DEMO_DATA` is unset OR `false`**. (CI's `production.yml`
      refuses to deploy if it is `true`.)
- [ ] `grep -rE "(password|secret|key|token).*=.*['\"][a-zA-Z0-9_-]{8,}"
      src/ scripts/ api/` returns no real secrets (test/demo strings ok).

## H-1 — Auth hardening

- [ ] Supabase Authentication → URL Configuration: redirect URLs include
      only `https://app.heitobias.com/**`. No localhost in production.
- [ ] Magic-link expiry = **1 hour** (default per `docs/AUTH-HARDENING.md`).
- [ ] Password sign-in **disabled** for end users. Only ops uses email
      sign-in for break-glass access.
- [ ] Rate limits configured: sign-in 5/min/IP, sign-up 1/min/IP, magic
      link 3/hour/email.
- [ ] HSTS, X-Frame-Options DENY, CSP, Referrer-Policy verified in
      `vercel.json` and reachable in browser devtools after first deploy.

## H-2 — Database

- [ ] All migrations applied: `npx supabase db push --linked` ran
      without error against the production project.
- [ ] `select count(*) from public.audit_log` returns a value (proves
      RLS does not block ops's `audit.read` role).
- [ ] No table has `force_row_security = false` AND `row_security = true`
      (one-line probe in psql; see `docs/POSTDEPLOY-PROBES.md`).
- [ ] `select count(*) from public.people where is_demo_data = true`
      returns **0** in production.
- [ ] `select count(*) from public.assessment_instruments where
      validity_status = 'validated'` returns **0** in production (H-stub
      discipline holds).

## H-3 — Email infrastructure

- [ ] Send a test invite from the admin UI to a real address; email
      arrives within 60s; DKIM passes; clicking the magic link signs in.
- [ ] Send to a known-bounce address; `email_outbox.status = 'failed'`
      within 5 minutes; `email_suppressions` row created.
- [ ] Resend to that address from the UI is **blocked** by the
      suppression check inside `email_enqueue`.

## H-4 — Observability

- [ ] `/api/health` returns 200 from the public domain.
- [ ] `/api/ready` returns 200 from the public domain.
- [ ] Sentry: trigger a deliberate error in staging, confirm it lands in
      the production Sentry project's *staging environment* bucket.
- [ ] Uptime monitor (UptimeRobot / BetterStack / Pingdom) pings
      `/api/health` every 60s with EU-region check points; on-call
      alerts wired (PagerDuty / OpsGenie).
- [ ] Custom metric `read_during_seal_count` configured as a *page*
      alert at > 0 (this is the science-defensibility incident, not a
      warning — see `docs/MONITORING.md`).

## H-5 — Backups & retention

- [ ] PITR enabled on the production Supabase project, window ≥ 7 days
      (see `docs/BACKUPS.md`).
- [ ] Daily logical-dump cron writes to
      `heitobias-backups-eu-north-1` with object lock + KMS; the
      most recent dump is < 26h old.
- [ ] First restore drill performed; outcome recorded in
      `docs/INCIDENTS.md`.
- [ ] `select count(*) from public.retention_runs` is **non-zero** the
      morning after first deploy (proves the scheduler runs even though
      it's a no-op).
- [ ] DSR endpoints `/api/dsr/request` and `/api/dsr/export` reachable
      and return 401 for an unauthenticated request, 200 for an
      authenticated one.

## H-6 — Science & policy sign-off

- [ ] I/O psychology advisor has signed off the H-stub disclosure shown
      to candidates and employers (UI badge + the placeholder text on
      every science-touching surface).
- [ ] DPO has signed off `docs/RETENTION.md` and confirmed the policy
      table matches the public privacy notice.
- [ ] Legal advisor has signed off the EU AI Act risk classification and
      the human-in-the-loop checkpoints around hiring decisions.
- [ ] H-stub remediation backlog is on the public roadmap with a
      committed timeline; no surface ships with `validity_status =
      'validated'` until that timeline lands.

## H-7 — Domain & DNS

- [ ] `app.heitobias.com` → Vercel production deployment.
- [ ] `api.heitobias.com` (if used) → Vercel production deployment.
- [ ] DNS TTL ≤ 300s for the 48 hours before launch so a rollback is
      fast.
- [ ] Email envelope domain (MAIL FROM) aligned with FROM_EMAIL for
      DMARC.

## H-8 — Final smoke (T-1 hour)

- [ ] CI on `main` is green.
- [ ] `production.yml` manual-approval gate is in the **production-approval**
      environment with at least two named reviewers.
- [ ] On-call rotation for the next 72 hours has been confirmed in the
      shared calendar.
- [ ] Rollback rehearsal in staging completed within the past 30 days.
- [ ] One operator executes the launch deploy; one separate operator
      tails `/api/health`, the Sentry feed, and `audit_log` for the
      first 30 minutes.

---

## After launch (T+24h)

- [ ] No P0 / P1 incidents.
- [ ] No `read_during_seal_count > 0` alerts fired.
- [ ] No DSR requests are over the 30-day pending threshold (will not
      apply at T+24h — the alert exists; the gate is at T+30d).
- [ ] The first nightly retention sweep ran and wrote rows.

---

## After launch (T+7d)

- [ ] First weekly review meeting held; status of every H-stub on the
      backlog reviewed.
- [ ] First restore drill rehearsed against the production backup
      pipeline (not against production itself — into a throwaway project).

---

**Owner:** Production lead. **Sign-off required from:** DPO, I/O psych
advisor, legal advisor, security lead, on-call lead. **Last reviewed:**
on the day of launch — re-read this list every time, even if it looks
familiar.
