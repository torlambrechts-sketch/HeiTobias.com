-- hiring_decisions has UNIQUE (requisition_candidate_id, decided_at).
-- Two calls in the same transaction must yield distinct timestamps;
-- now() returns transaction-start time. Use clock_timestamp() for
-- wall-clock distinctness so consecutive decisions don't collide.

create or replace function public.hiring_decision_record(
  p_requisition_id uuid,
  p_person_id uuid,
  p_decision public.hiring_decision,
  p_rationale text,
  p_overrode_recommendation boolean default false,
  p_recommendation_summary text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor_id uuid;
  v_req public.requisitions%rowtype;
  v_req_cand_id uuid;
  v_fit_id uuid;
  v_id uuid;
begin
  if p_rationale is null or length(btrim(p_rationale)) = 0 then
    raise exception 'hiring_decision_record: rationale is required (text, non-empty)';
  end if;
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then raise exception 'hiring_decision_record: requisition not found'; end if;
  if v_caller is not null and not public.has_permission(v_req.org_id, 'hiring.decide') then
    raise exception 'hiring_decision_record: caller lacks hiring.decide';
  end if;
  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;
  if v_actor_id is null then
    raise exception 'hiring_decision_record: caller has no people row (cannot attribute decision)';
  end if;
  select id into v_req_cand_id from public.requisition_candidates
    where requisition_id = p_requisition_id and person_id = p_person_id;
  if v_req_cand_id is null then
    insert into public.requisition_candidates (org_id, requisition_id, person_id, stage)
      values (v_req.org_id, p_requisition_id, p_person_id, 'screening')
      returning id into v_req_cand_id;
  end if;
  select id into v_fit_id from public.fit_results
    where requisition_id = p_requisition_id and person_id = p_person_id
    order by computed_at desc limit 1;
  insert into public.hiring_decisions (
    org_id, requisition_candidate_id, fit_result_id,
    decision, rationale, overrode_recommendation, recommendation_summary,
    decided_by, decided_at
  ) values (
    v_req.org_id, v_req_cand_id, v_fit_id,
    p_decision, p_rationale, coalesce(p_overrode_recommendation, false), p_recommendation_summary,
    v_actor_id, clock_timestamp()
  )
  returning id into v_id;
  update public.requisition_candidates
     set decision = (p_decision::text)::public.requisition_candidate_decision,
         updated_at = now()
   where id = v_req_cand_id;
  perform public.audit_log_event(
    v_req.org_id, 'hiring.decision', 'hiring_decisions', v_id, null,
    jsonb_build_object(
      'requisition_id', p_requisition_id,
      'requisition_candidate_id', v_req_cand_id,
      'person_id', p_person_id,
      'decision', p_decision,
      'rationale', p_rationale,
      'overrode_recommendation', coalesce(p_overrode_recommendation, false),
      'fit_result_id', v_fit_id
    ),
    null
  );
  return v_id;
end;
$$;
