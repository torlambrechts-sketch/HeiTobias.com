-- The original rde_select policy referenced public.role_definition_evaluations
-- from within its own USING clause (to check whether the CALLER had also
-- submitted at least one evaluation row for the same requisition). RLS
-- recursively re-evaluated the policy for the subquery, hitting
-- "infinite recursion detected in policy".
--
-- Fix: extract the self-reference into a SECURITY DEFINER helper that
-- bypasses RLS for the inner lookup. The semantics of the policy are
-- unchanged; only the implementation moves out of the policy body.

create or replace function public._caller_has_submitted_evaluation(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.role_definition_evaluations rde
    join public.people p on p.id = rde.evaluator_id
    where rde.requisition_id = p_requisition_id
      and p.auth_user_id    = (select auth.uid())
      and rde.submitted_at is not null
  );
$$;
revoke execute on function public._caller_has_submitted_evaluation(uuid) from public;
grant  execute on function public._caller_has_submitted_evaluation(uuid) to authenticated, service_role;
comment on function public._caller_has_submitted_evaluation(uuid) is
  'RLS helper: true iff the caller has submitted at least one evaluation row for the given requisition. SECURITY DEFINER to avoid recursive RLS on role_definition_evaluations.';

drop policy rde_select on public.role_definition_evaluations;

create policy rde_select on public.role_definition_evaluations
  for select to authenticated
  using (
    public.is_self(evaluator_id)
    or (
      submitted_at is not null
      and (
        public.has_permission(org_id, 'team_definition.reconcile')
        or public._caller_has_submitted_evaluation(requisition_id)
      )
    )
  );
