# Operator Runbook

> Day-to-day operations of the HeiTobias production instance. Read once
> end-to-end before going on call; refer back when an incident hits.
>
> Related docs:
> - `docs/BACKUPS.md` — backup configuration + restore drill cadence
> - `docs/RETENTION.md` — data retention policy + scheduler
> - `docs/MONITORING.md` — alerts, Sentry, uptime monitor
> - `docs/AUTH-HARDENING.md` — Supabase auth settings the operator owns
> - `PRODUCTION-LAUNCH-CHECKLIST.md` — pre-launch gates

---

## 1 — On-call rotation

### What the on-call owns
- **Page response** within 15 minutes for P0/P1 alerts (see §3).
- **DSR fulfilment** within 30 days of request (GDPR Art. 12 hard limit;
  internal target is 7 days for export, 21 days for erase).
- **Health-check feed**. `/api/health` and `/api/ready` should be green
  on the public domain; the uptime monitor pages on red.

### Handover at rotation boundary
- Last week's incidents reviewed (any unresolved → carry forward).
- Outstanding DSRs reviewed (look at `pending` rows in
  `data_subject_requests` older than 7 days).
- Backup drill scheduled if quarterly due.

---

## 2 — Reading the audit log

The `audit_log` table is the system of record for every consequential
action. It's insert-only by trigger + RLS. The audit explorer in
`/admin → Audit` is the operator UI; for ad-hoc queries, use psql with
the service-role connection.

### Common queries

```sql
-- Anything a specific person did in the last 7 days.
select at, action, entity_type, entity_id, after_json
  from public.audit_log
 where actor_person_id = '<uuid>'
   and at > now() - interval '7 days'
 order by at desc;

-- Every consent grant / revoke in the last 30 days.
select at, action, actor_person_id, entity_id, after_json
  from public.audit_log
 where action in ('consent.grant', 'consent.revoke')
   and at > now() - interval '30 days'
 order by at desc;

-- Cross-org placements (should match placement_execute calls).
select at, actor_person_id, after_json
  from public.audit_log
 where action = 'placement.execute'
 order by at desc
 limit 50;
```

### Anomalies to watch for
- `read_during_seal` actions with `before_json != null` — Stage 2 of
  team-definition is supposed to seal; any read during the sealed
  window is a science-defensibility incident. Monitor + alert per
  `docs/MONITORING.md`.
- `dsr.fulfil` rows where the time gap from `dsr.open` to `dsr.fulfil`
  exceeds 30 days — overdue DSRs.

---

## 3 — Incidents

### P0 — production down or data leak
**Examples:** `/api/health` returns 503 sustained; cross-org RLS leak
suspected; a user reports seeing another tenant's data.

**Response:**
1. Acknowledge the page within 15 min.
2. Confirm scope via the Sentry feed + Vercel logs + Supabase logs.
3. If RLS leak suspected: rotate the service-role key immediately;
   triage which rows were exposed; prepare GDPR Art. 33 notification
   (72-hour clock).
4. If platform down: check `/api/ready` (DB reachability); check Vercel
   deployment status; consider rollback (`vercel alias set` to the
   previous deployment).
5. Status-page update.

### P1 — feature broken for many users
**Examples:** sign-in broken; take-flow returns 500; placement_execute
RPC throwing.

**Response:**
1. Acknowledge in 30 min.
2. Identify the regression — usually the most recent deploy. Roll back
   via Vercel if confirmed.
3. Open an incident-recovery PR; do not hotfix on `main` without the
   normal CI / approval flow unless it's a security fix.

### P2 — DSR overdue, backup missed, retention not run
**Response:** address within 1 business day. Document in
`docs/INCIDENTS.md` (created on first incident).

### Standing alert: `read_during_seal_count > 0`
This metric counts reads against `team_definition_runs` rows while
they're in the `seal` window (Stage 2). A non-zero value means
science-defensibility is at risk. Escalate to the I/O psychology
advisor; do not silently dismiss.

---

## 4 — DSR fulfilment

### Export request (Art. 15)
The data subject (or an org admin acting on their behalf) opens via
the My Profile UI, which calls `dsr_open('export', org_id)`. The
on-call operator:

1. Pulls the request from `select * from data_subject_requests where
   status = 'pending' and kind = 'export' order by opened_at`.
2. Runs `select public.dsr_export_my_data()` while impersonating the
   subject (or, for an admin-initiated request, runs a parametrized
   export against the subject's `person_id`).
3. Uploads the JSON to the secure evidence S3 bucket; takes the
   pre-signed URL (24-hour expiry).
4. Calls `dsr_fulfil(request_id, 'fulfilled', evidence_ref =>
   '<presigned URL>')` and emails the URL to the subject's verified
   address.

### Erase request (Art. 17)
1. Pull pending request.
2. **First**: check Art. 17(3) refusal grounds (active placement,
   statutory retention, pending dispute — see `docs/RETENTION.md` §3).
   If any apply, call `dsr_fulfil(..., 'refused', refusal_reason =>
   '<text>')` and inform the subject.
3. If erase is permissible: walk the personal-data tables
   (people, memberships, consent_grants, profiles,
   assessment_sessions, requisition_candidates, plus storage
   objects), set `deleted_at = now()` where soft-delete supported;
   issue `DELETE` against the rest in a single transaction; record
   the row counts in `dsr_fulfil(... notes => {...})`.
4. The `audit_log` row stays (immutable; retention table excludes
   it — see `docs/RETENTION.md`).

---

## 5 — Backups & restore

See `docs/BACKUPS.md` for configuration. Quarterly drill:

1. Pick a backup ≥ 24 hours old.
2. Restore into a throwaway Supabase project.
3. Run canary queries (`select count(*) from people /
   organizations / audit_log`).
4. Record RTO + RPO in `docs/INCIDENTS.md`.

If a drill fails: that IS the incident. Treat as P1.

---

## 6 — Retention sweep activation

The `retention_sweep()` function is `noop` until H-6 sign-off (see
`docs/RETENTION.md` §2.2). To activate:

1. Confirm DPO has signed off the retention table.
2. Switch the function body to `applied = false` (dry-run) for ≥ 7
   nights via a migration.
3. Inspect `retention_runs.detail` for each policy key; verify the
   row counts look right and no surprise deletes.
4. Switch to `applied = true` via a migration.
5. Subscribe the on-call to a daily "retention summary" report.

---

## 7 — Common Supabase Dashboard tasks

### Rotate the service-role key
1. Supabase Dashboard → Settings → API → Reset Service Role Key.
2. Update the secret in Vercel (`SUPABASE_SERVICE_ROLE_KEY`) — both
   production and staging.
3. Redeploy. The next deployment uses the new key.

### Add a magic-link redirect URL
Settings → Authentication → URL Configuration → Redirect URLs. Only
add URLs under the verified production domain; never localhost in
production.

### Check FORCE RLS on a table
```sql
select relname, relrowsecurity as rls_enabled, relforcerowsecurity as rls_forced
  from pg_class where relkind = 'r' and relnamespace = 'public'::regnamespace
 order by relname;
```
Every row in this report should be `(true, true)`. INVARIANT-3 enforces
this at CI; the query is the post-deploy verification.

---

## 8 — When to escalate

- **DPO**: any GDPR-relevant incident (data leak, DSR > 30 days overdue,
  retention refusal needs review).
- **Legal advisor**: any AI Act-relevant question (hiring decision
  appeal, fairness verdict challenge, EU AI Act registration update).
- **I/O psychology advisor**: any science-defensibility incident
  (`read_during_seal_count > 0`, fairness metric outside acceptable
  band per H-3 sign-off, norm-update due).
- **Eng lead**: P0/P1 incidents past 30 minutes without progress.

Phone numbers + PagerDuty escalation policies in the internal ops
wiki (not in this repo).
