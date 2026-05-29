-- Phase B module reconciliation: three modules previously marked
-- `requires_part2` are now built and shipping. Flip them to
-- `available` so org admins can actually enable / disable them via the
-- WorkspaceAdmin Modules tab without hitting the
-- `_check_org_modules_availability()` refusal.
--
-- What landed since each was marked `requires_part2`:
--   * candidate_experience — unified /take/<token> session (4 sections)
--                            via 20260530300000_unified_session_schema.sql
--                            and friends.
--   * requisitions         — /req list + per-id deep page + candidate
--                            roster (Ops Layer Part 2, plus the
--                            Create-requisition wizard from Phase A).
--   * manager_workspace    — /team + /employees/:id surfaces + refit +
--                            signals + guidance composer (Ops Layer
--                            Part 2).
--
-- Stays `requires_expert_signoff` (correct, by design):
--   * modeling_admin       — gated on H-8 modeling.signoff GRANT.
--   * fairness_audit       — gated on H-3 fairness interpretation
--                            rationale.
--
-- Idempotent: re-running this migration on a project that already has
-- these statuses is a no-op.

update public.modules set
  availability = 'available',
  availability_note = 'Live. Candidate /take/<token> unified 4-section session.'
where key = 'candidate_experience';

update public.modules set
  availability = 'available',
  availability_note = 'Live. /req list + deep page + create-requisition wizard.'
where key = 'requisitions';

update public.modules set
  availability = 'available',
  availability_note = 'Live. /team list + /employees/:id + refit + signals + guidance.'
where key = 'manager_workspace';
