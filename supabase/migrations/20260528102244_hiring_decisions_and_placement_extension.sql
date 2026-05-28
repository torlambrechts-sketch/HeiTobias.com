-- hiring_decisions_and_placement_extension — Phase 1 Step 6.
--
-- The hiring_decisions table itself was added in Phase 1 Step 1 (it lives in
-- the candidate_experience_tables migration). Its shape: time-series rows
-- keyed by (requisition_candidate_id, decided_at), rationale NOT NULL,
-- decided_by NOT NULL. This migration adds the BEHAVIOR on top:
--
--   1. hiring_decision_record(...) — atomic INSERT of a new decision row,
--      with caller-attribution from auth.uid() and a structured audit event.
--      AuthZ: hiring.decide.
--   2. placement_execute extension — same signature; now requires the LATEST
--      hiring_decisions row for (req, person) to be decision='hire', and
--      atomically advances the FROM-side lifecycle (membership=removed,
--      requisition_candidates.stage=placed, requisitions.status=placed).

create or replace function public.hiring_decision_record(
  p_requisition_id          uuid,
  p_person_id               uuid,
  p_decision                public.hiring_decision,
  p_rationale               text,
  p_overrode_recommendation boolean default false,
  p_recommendation_summary  text default null
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller          uuid := (select auth.uid());
  v_actor_id        uuid;
  v_req             public.requisitions%rowtype;
  v_req_cand_id     uuid;
  v_fit_id          uuid;
  v_id              uuid;
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

  -- requisition_candidates row must exist for the pair (compute_fit creates one).
  -- For Phase 1, if missing (rare — pre-screening decisions), create it.
  select id into v_req_cand_id from public.requisition_candidates
    where requisition_id = p_requisition_id and person_id = p_person_id;
  if v_req_cand_id is null then
    insert into public.requisition_candidates (org_id, requisition_id, person_id, stage)
      values (v_req.org_id, p_requisition_id, p_person_id, 'screening')
      returning id into v_req_cand_id;
  end if;

  -- Snapshot the latest fit_result the decision relates to (nullable).
  select id into v_fit_id from public.fit_results
    where requisition_id = p_requisition_id and person_id = p_person_id
    order by computed_at desc limit 1;

  -- Time-series INSERT (the table uniques on requisition_candidate_id + decided_at,
  -- and per the policy, decided_by must be the caller — bypassed by SECURITY DEFINER
  -- but we set it correctly anyway).
  insert into public.hiring_decisions (
    org_id, requisition_candidate_id, fit_result_id,
    decision, rationale, overrode_recommendation, recommendation_summary,
    decided_by, decided_at
  ) values (
    v_req.org_id, v_req_cand_id, v_fit_id,
    p_decision, p_rationale, coalesce(p_overrode_recommendation, false), p_recommendation_summary,
    v_actor_id, now()
  )
  returning id into v_id;

  -- Mirror the decision onto requisition_candidates for read ergonomics.
  update public.requisition_candidates
     set decision   = p_decision,
         updated_at = now()
   where id = v_req_cand_id;

  -- Structured audit event in addition to the _audit_row trigger.
  perform public.audit_log_event(
    v_req.org_id, 'hiring.decision', 'hiring_decisions', v_id,
    null,
    jsonb_build_object(
      'requisition_id',          p_requisition_id,
      'requisition_candidate_id', v_req_cand_id,
      'person_id',               p_person_id,
      'decision',                p_decision,
      'rationale',               p_rationale,
      'overrode_recommendation', coalesce(p_overrode_recommendation, false),
      'fit_result_id',           v_fit_id
    ),
    null
  );

  return v_id;
end;
$$;

revoke execute on function public.hiring_decision_record(uuid, uuid, public.hiring_decision, text, boolean, text) from public;
grant  execute on function public.hiring_decision_record(uuid, uuid, public.hiring_decision, text, boolean, text) to authenticated, service_role;
comment on function public.hiring_decision_record(uuid, uuid, public.hiring_decision, text, boolean, text) is
  'Records the human hiring decision (time-series). Caller-attributed via auth.uid(). Required rationale. Mirrors to requisition_candidates.decision. Structured audit event. AuthZ: hiring.decide.';

-- ============== placement_execute extension ==============
create or replace function public.placement_execute(
  p_requisition_id uuid,
  p_person_id      uuid,
  p_to_org_id      uuid,
  p_consent_id     uuid
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller       uuid := (select auth.uid());
  v_req          public.requisitions%rowtype;
  v_consent      public.consent_grants%rowtype;
  v_req_cand_id  uuid;
  v_latest_dec   public.hiring_decision;
  v_src_profile  public.profiles%rowtype;
  v_placement_id uuid;
  v_role_id_to   uuid;
  v_position_id  uuid;
  v_profile_id   uuid;
  v_role_title   text;
  v_role_family  text;
  v_role_def     jsonb;
begin
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then raise exception 'placement_execute: requisition not found (id=%)', p_requisition_id; end if;

  if v_caller is not null then
    if not public.has_permission(v_req.org_id, 'placement.transfer') then
      raise exception 'placement_execute: caller lacks placement.transfer in from_org_id';
    end if;
  end if;

  if v_req.org_id = p_to_org_id then
    raise exception 'placement_execute: from_org_id and to_org_id must differ';
  end if;

  -- PHASE 1 §3.1: require the LATEST hiring decision to be 'hire'.
  select id into v_req_cand_id from public.requisition_candidates
    where requisition_id = p_requisition_id and person_id = p_person_id;
  if v_req_cand_id is null then
    raise exception 'placement_execute: no requisition_candidates row for (req=%, person=%)',
      p_requisition_id, p_person_id;
  end if;
  select decision into v_latest_dec from public.hiring_decisions
    where requisition_candidate_id = v_req_cand_id
    order by decided_at desc limit 1;
  if v_latest_dec is null then
    raise exception 'placement_execute: no hiring decision recorded; call hiring_decision_record first';
  end if;
  if v_latest_dec <> 'hire' then
    raise exception 'placement_execute: latest hiring decision is %, requires hire', v_latest_dec;
  end if;

  -- Consent validation (unchanged).
  select * into v_consent from public.consent_grants where id = p_consent_id;
  if not found then raise exception 'placement_execute: consent grant not found (id=%)', p_consent_id; end if;
  if v_consent.person_id <> p_person_id then raise exception 'placement_execute: consent_id does not belong to p_person_id'; end if;
  if v_consent.granted_to_org_id <> p_to_org_id then raise exception 'placement_execute: consent_id was not granted to p_to_org_id'; end if;
  if v_consent.purpose <> 'profile_portability' then
    raise exception 'placement_execute: consent purpose is %, requires profile_portability', v_consent.purpose;
  end if;
  if not public.consent_active(p_consent_id) then
    raise exception 'placement_execute: consent is not active (revoked/expired/missing)';
  end if;

  insert into public.placements (
    requisition_id, person_id, from_org_id, to_org_id, status, consent_id, transferred_at
  ) values (
    p_requisition_id, p_person_id, v_req.org_id, p_to_org_id, 'transferred', p_consent_id, now()
  )
  returning id into v_placement_id;

  -- Mirror the role into to_org (unchanged from Phase 0).
  select title, family, definition_json into v_role_title, v_role_family, v_role_def
    from public.roles_catalog where id = v_req.role_id;
  select id into v_role_id_to
    from public.roles_catalog
    where org_id = p_to_org_id and title = v_role_title and status = 'active' and is_template = false
    order by version desc limit 1;
  if v_role_id_to is null then
    insert into public.roles_catalog (org_id, title, family, is_template, definition_json, status)
      values (p_to_org_id, v_role_title, v_role_family, false, v_role_def, 'active')
      returning id into v_role_id_to;
  end if;

  -- Copy profile (unchanged).
  select * into v_src_profile from public.profiles
    where person_id = p_person_id and org_id = v_req.org_id
    order by valid_from desc nulls last limit 1;
  if found then
    insert into public.profiles (
      org_id, person_id, source, traits_json, cognitive_json, values_json, derived_json, consent_id
    ) values (
      p_to_org_id, p_person_id, 'import', v_src_profile.traits_json, v_src_profile.cognitive_json,
      v_src_profile.values_json, v_src_profile.derived_json, p_consent_id
    ) returning id into v_profile_id;
  else
    insert into public.profiles (org_id, person_id, source, consent_id)
      values (p_to_org_id, p_person_id, 'import', p_consent_id)
      returning id into v_profile_id;
  end if;

  insert into public.positions (org_id, role_id, person_id, status, start_date)
    values (p_to_org_id, v_role_id_to, p_person_id, 'filled', current_date)
    returning id into v_position_id;

  -- PHASE 1 §3.1: post-placement lifecycle on the FROM side, atomic with above.
  update public.memberships
     set status = 'removed', updated_at = now()
   where org_id = v_req.org_id and person_id = p_person_id and status <> 'removed';

  update public.requisition_candidates
     set stage = 'placed', decision = 'hire', updated_at = now()
   where id = v_req_cand_id;

  update public.requisitions set status = 'placed', updated_at = now() where id = p_requisition_id;

  return v_placement_id;
end;
$$;

comment on function public.placement_execute(uuid, uuid, uuid, uuid) is
  'Phase 1: extended placement RPC. Requires the latest hiring_decisions to be decision=hire. Sets agency-pipeline membership=removed, candidate stage=placed, requisition.status=placed, all atomic with the transfer.';
