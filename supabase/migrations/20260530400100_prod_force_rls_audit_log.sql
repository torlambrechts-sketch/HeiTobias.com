-- Production hardening: close the FORCE RLS gap on public.audit_log.
--
-- The original audit_log migration enabled RLS but did not FORCE it. Without
-- FORCE, a session running as the table owner (e.g. a misconfigured
-- service-role context) silently bypasses the policy. Audit logs are
-- privileged but not unreadable — read access is policy-driven, so RLS must
-- apply to all sessions including the owner.
--
-- This is idempotent: re-FORCing an already-FORCED table is a no-op.

alter table public.audit_log force row level security;
