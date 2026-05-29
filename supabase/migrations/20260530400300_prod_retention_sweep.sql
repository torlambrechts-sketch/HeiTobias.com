-- Production hardening: scheduled retention sweep.
--
-- This migration installs `public.retention_sweep()` — the function that
-- pg_cron will call nightly. It is intentionally a NO-OP today: it writes
-- one `retention_runs` row per policy key with `status='noop'` and returns.
--
-- Why no-op:
--   * H-6 sign-off has not happened (see docs/RETENTION.md §2.2).
--   * Deletion is asymmetric: a retention bug that fails to delete is
--     recoverable from PITR; a bug that over-deletes is not.
--   * Until the dry-run period passes, we want the scheduler ALIVE (so we
--     can verify it runs) but INERT (so it does not delete anything).
--
-- When H-6 sign-off lands, a follow-up migration will replace the body
-- with the actual sweep predicates; the retention_runs ledger schema and
-- scheduling do not change.

create or replace function public.retention_sweep()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_policies text[] := array[
    'employment_data_24mo',
    'candidate_rejected_6mo',
    'candidate_withdrawn_immediate',
    'email_outbox_sent_90d',
    'email_outbox_failed_180d',
    'email_suppressions_24mo'
  ];
  v_key text;
begin
  foreach v_key in array v_policies loop
    insert into public.retention_runs (policy_key, status, detail)
    values (
      v_key,
      'noop',
      jsonb_build_object(
        'reason', 'retention sweep is no-op until H-6 sign-off',
        'doc_ref', 'docs/RETENTION.md §2.2'
      )
    );
  end loop;
end;
$$;

revoke all on function public.retention_sweep() from public;
grant execute on function public.retention_sweep() to service_role;

comment on function public.retention_sweep() is
  'Nightly retention sweep. NO-OP until H-6 sign-off. Replace body in a follow-up migration once dry-run period completes.';

-- ─── pg_cron schedule ──────────────────────────────────────────────
-- Best-effort: pg_cron may not be enabled on every environment. If it
-- is, schedule the sweep nightly at 03:00 UTC. The DO block swallows
-- the "extension not available" error so this migration does not block
-- on a project that has not opted into pg_cron yet — the operator can
-- run `select cron.schedule(...)` manually after enabling.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Unschedule any prior version of the same job so re-running this
    -- migration during development is idempotent.
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'retention_sweep_nightly';

    perform cron.schedule(
      'retention_sweep_nightly',
      '0 3 * * *',
      $cron$select public.retention_sweep();$cron$
    );
  end if;
exception when others then
  -- Non-fatal: log via NOTICE and let the migration succeed. The
  -- operator can wire up cron manually after enabling pg_cron.
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;
