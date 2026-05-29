# Backups & Disaster Recovery

> **Status:** runbook. None of this is automated by code in this repo —
> backup infrastructure lives in the hosting platform configuration. This
> document is the operator's checklist for what to enable and how to
> verify it. Treat each item as a **launch gate**: production cannot go
> live until every section has a green answer.

---

## 1 — Database (Supabase / Postgres)

### 1.1 Point-in-time recovery (PITR)
- [ ] Supabase project plan is **Pro** or higher (PITR is not available on
      Free / Starter).
- [ ] PITR retention window is set to **at least 7 days** (recommended
      14 days for production).
- [ ] Confirm in the Supabase dashboard: *Project Settings → Database →
      Backups → Point in Time Recovery*.

### 1.2 Daily logical dumps (defense in depth)
PITR depends on the hosting platform staying healthy. We also take an
independent dump on our own infrastructure.

- [ ] Scheduled job runs `pg_dump --format=custom --no-owner --no-acl`
      against the production DB at **02:00 UTC** daily (window chosen to
      avoid SCD/EU business hours).
- [ ] Dump is written to an **EU-region** S3 bucket
      (`heitobias-backups-eu-north-1`) with:
      - Object lock: **governance mode, 30 days minimum**.
      - Server-side encryption: **SSE-KMS** with a dedicated CMK.
      - Bucket policy: read access only to the on-call IAM role; write
        access only to the backup runner.
- [ ] Lifecycle policy: dumps > 30 days transition to Glacier; > 365 days
      are deleted (unless a hold is in place — see *Hold for litigation*).

### 1.3 Restore drills
- [ ] Quarterly restore drill: pick a backup, restore into a throwaway
      Supabase project, verify a small set of canary queries (row counts
      on `people`, `organizations`, `audit_log`; a fit_results sample).
- [ ] Drill outcome is recorded in
      `docs/INCIDENTS.md` (date, RTO measured, RPO measured, notes).
- [ ] Target SLOs:
      - **RTO (recovery time):** ≤ 4 hours.
      - **RPO (recovery point):** ≤ 1 hour (PITR resolution).

### 1.4 Hold for litigation
If a hold notice arrives (DPA inquiry, ongoing dispute, regulator
request), the on-call:
1. Marks the relevant backups with the S3 object-lock legal hold flag.
2. Pauses the lifecycle policy on those objects.
3. Records the hold (date, scope, reason) in
   `docs/INCIDENTS.md` under *Holds*.
4. Removes the hold only on written instruction from the DPO.

---

## 2 — File storage (Supabase Storage / S3)

- [ ] Storage buckets that hold personal artefacts (CVs, assessment
      attachments) have versioning **enabled**.
- [ ] Cross-region replication is **OFF** (EU-only data residency; do
      not let replication leak out of region).
- [ ] Same 30-day retention as DB dumps via lifecycle policy.

---

## 3 — Configuration backups

- [ ] Vercel project settings exported quarterly (manual; the Vercel
      CLI does not give us a clean export today).
- [ ] Supabase RLS policies and RPCs are versioned in this repo's
      `supabase/migrations/` — no separate backup needed.
- [ ] Secrets (SMTP, Sentry DSN, IAM keys) live in the hosting platform
      secret manager and are documented in `docs/SECRETS-INVENTORY.md`
      (paths only; never values).

---

## 4 — What we explicitly do NOT back up

- [ ] **No PII** in CI / dev / staging snapshots used by engineers. Dev
      environments use `npm run seed:demo` against an EMPTY database; we
      never restore a production snapshot into a dev project.
- [ ] **No clear-text exports** outside the EU region. The backup
      pipeline must fail if the destination bucket is configured for any
      region outside EU.

---

## 5 — Verification (run quarterly)

1. Open Supabase dashboard → Backups → confirm PITR window matches the
   target above.
2. Open S3 → `heitobias-backups-eu-north-1` → confirm at least 30 daily
   objects exist and the most recent is < 26h old.
3. Execute the restore drill from §1.3. Record the result.
4. Re-read this document; if any item has drifted, update it and link
   the PR in the next on-call rotation handover.

---

## Appendix — Why we accept the cost

Backups feel like a tax until the day you need them. The minimum
sufficient setup is: PITR for fast recovery from operator error,
independent dumps for resilience against platform-wide outages, and a
restore drill so we know the chain actually works. Anything less and the
question "could you restore from 36h ago, right now?" has no defensible
answer.
