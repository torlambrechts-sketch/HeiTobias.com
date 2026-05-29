-- Recruiter-side view of the unified session.
-- rpc_candidate_session_summary(p_rc_id) returns the most recent
-- session for the candidate, including demo_mode flag and per-section
-- completion. UI surfaces "DEMO MODE" prominently so a recruiter never
-- mistakes a demo session for production.

create or replace function public.rpc_candidate_session_summary(p_rc_id uuid)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_rc public.requisition_candidates%rowtype;
  v_session public.assessment_sessions%rowtype;
  v_prep_count int;
begin
  select * into v_rc from public.requisition_candidates where id = p_rc_id;
  if v_rc.org_id is null then return jsonb_build_object('error', 'candidate not found'); end if;
  if (select auth.uid()) is null or not public.has_permission(v_rc.org_id, 'requisition.read') then
    raise exception 'rpc_candidate_session_summary: requires requisition.read';
  end if;
  select * into v_session from public.assessment_sessions
    where person_id = v_rc.person_id and org_id = v_rc.org_id
    order by started_at desc limit 1;
  if v_session.id is null then
    return jsonb_build_object(
      'requisition_candidate_id', p_rc_id,
      'session_present', false
    );
  end if;
  select count(*) into v_prep_count from public.assessment_prep_responses
    where session_id = v_session.id and answered_at is not null;
  return jsonb_build_object(
    'requisition_candidate_id', p_rc_id,
    'session_present', true,
    'session_id', v_session.id,
    'demo_mode', v_session.demo_mode,
    'status', v_session.status::text,
    'started_at', v_session.started_at,
    'completed_at', v_session.completed_at,
    'sections', v_session.sections_json,
    'structured_prep_responses', v_prep_count,
    'dev_stub_label', 'All four sections render dev_stub items pending H-1 / H-2 sign-off.'
  );
end;
$$;
revoke execute on function public.rpc_candidate_session_summary(uuid) from public;
grant  execute on function public.rpc_candidate_session_summary(uuid) to authenticated, service_role;
