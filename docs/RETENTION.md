# Data Retention Policy

> **Status:** policy + scheduler scaffold. The scheduled job table
> (`retention_runs`) is wired up; the actual sweep jobs run as **no-ops
> until H-6 sign-off** because deleting personal data is the kind of
> decision that needs a human ack the first time, every time.

The retention policy below is what we tell customers and regulators.
The scheduler enforces it. The audit log proves it.

---

## 1 — Categories & retention windows

| Category | Retention window | Trigger to delete | Legal basis |
|---|---|---|---|
| **Active employment data** (profiles, assessments, position history) | While employment is active + 24 months after | `placement.status = 'ended'` + 24mo | GDPR Art. 5(1)(e) — kept while needed for the lifecycle relationship |
| **Candidate data — unsuccessful** | 6 months after rejection | `requisition_candidate.status = 'rejected'` + 6mo | Legitimate interest for re-application + appeal window |
| **Candidate data — withdrawn** | Immediate (next scheduler run) | `requisition_candidate.status = 'withdrawn'` | Subject withdrawal = consent revocation |
| **Consent ledger** | 7 years from grant date | none — kept beyond data deletion | Demonstrating compliance per Art. 5(2) |
| **Audit log** | 7 years from event date | none — immutable | Demonstrating compliance per Art. 5(2) |
| **Assessment items + scoring weights** | indefinite (instrument data) | none | Not personal data |
| **Email outbox (sent)** | 90 days | `status = 'sent'` + 90d | Operational; not needed after delivery confirmed |
| **Email outbox (failed)** | 180 days | `status = 'failed'` + 180d | Diagnostic |
| **Email suppressions (bounces)** | 24 months | bounce age + 24mo | Reputational / deliverability |
| **DSR ledger** | 7 years from request date | none | Demonstrating compliance |

---

## 2 — Enforcement (the scheduler)

### 2.1 Where it runs
A scheduled Postgres function `public.retention_sweep()` runs **nightly
at 03:00 UTC** via Supabase scheduled functions (pg_cron). One row is
inserted into `public.retention_runs` for every policy key processed in
the run, with `status = 'noop' | 'applied' | 'failed'`.

### 2.2 Why it's a no-op today
Before the first real deletion happens in production:

1. **H-6 sign-off** from the DPO confirming the policy table is
   accurate and the customer-facing data-handling notice reflects it.
2. **A canary org** exists in production marked
   `is_demo_data = true` so we can verify the sweep on a row we
   *expect* to delete before we let it touch real customer rows.
3. **A dry-run mode** in the sweep function emits an
   `applied = false` retention_runs row showing what *would* be deleted.
   We run the dry-run for at least 7 nights, review the output, and
   only then flip the policy to `applied = true`.

Until those three gates pass, `retention_sweep()` returns immediately
with `status = 'noop'` and writes a one-row ledger entry. This is the
right default — a retention bug that fails to delete is recoverable; a
retention bug that over-deletes is not.

### 2.3 Subject-initiated erasure
A subject-initiated erasure (via DSR `kind = 'erase'`) bypasses the
scheduler. The operator who fulfils the DSR runs:

```sql
select public.dsr_fulfil(
  p_request_id    => :id,
  p_status        => 'fulfilled',
  p_evidence_ref  => 'erasure receipt s3://...',
  p_refusal_reason=> null,
  p_notes         => '{}'::jsonb
);
```

…and is expected to have actually performed the erasure (today: a
checklist-driven manual sweep across the personal-data tables). The
audit_log row + the receipt in the evidence S3 bucket are the proof.

Why manual today: the universe of "tables that hold personal data" is
small enough (people, memberships, consent_grants, profiles,
assessment_sessions, requisition_candidates, plus storage objects) to
walk by hand once a quarter. Automation here would itself need
sign-off, and we do not yet have a backlog of erasure requests that
makes manual untenable.

---

## 3 — Refusing erasure

GDPR Art. 17(3) lists the bases on which erasure may be refused. The
operator records the refusal via `dsr_fulfil(..., p_status =
'refused', p_refusal_reason = '<text>')`. The audit_log row is the
defensible record.

Common refusal reasons in this product:

* **Active placement underway** — the subject is currently in the
  hand-off window. Erasure waits until the placement transitions to
  `ended`.
* **Statutory retention obligation** — the consent ledger and audit log
  carry their own 7-year retention; we do not delete from those even on
  request.
* **Pending dispute** — a legal hold blocks erasure for the duration.

Refusal is communicated to the subject via the
`dsr_refusal_response` email template (see `src/lib/email.ts`).

---

## 4 — Verification (run monthly)

* [ ] `retention_runs` has at least 28 `status = 'noop'` rows from the
      past 30 days (proof the scheduler is alive even when nothing
      qualifies for sweep).
* [ ] No DSR rows in `pending` status older than **30 days** — overdue
      DSRs are an incident.
* [ ] `select count(*) from people where deleted_at is not null` is
      monotonically increasing month over month (people *do* leave).
