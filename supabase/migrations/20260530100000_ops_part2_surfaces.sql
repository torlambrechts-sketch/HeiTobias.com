-- Operations Part 2: SECDEF helpers for the four surface families.
--   rpc_req_add_candidate    — agency adds a candidate; mints take-token
--   rpc_req_candidates       — list candidates on a requisition
--   rpc_my_team              — manager workspace (direct reports proxy)
--   rpc_me_self_view         — employee self-view per Phase 3 transparency
-- All rationales >=20 chars; admin_decisions written on consequential ones.

create or replace function public.rpc_req_add_candidate(
  p_requisition_id uuid,
  p_email text,
  p_full_name text,
  p_rationale text
)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_caller  uuid := (select auth.uid());
  v_actor   uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_req     public.requisitions%rowtype;
  v_person  uuid;
  v_rc      uuid;
  v_invite  jsonb;
  v_token   text;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'rpc_req_add_candidate: rationale >=20 chars';
  end if;
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then raise exception 'rpc_req_add_candidate: requisition not found'; end if;
  if v_caller is null or not public.has_permission(v_req.org_id, 'requisition.write') then
    raise exception 'rpc_req_add_candidate: requires requisition.write';
  end if;
  if p_email is null or position('@' in p_email) < 2 then
    raise exception 'rpc_req_add_candidate: invalid email';
  end if;
  select id into v_person from public.people where primary_email = lower(p_email) limit 1;
  if v_person is null then
    insert into public.people (full_name, primary_email, is_demo_data)
      values (coalesce(p_full_name, split_part(p_email,'@',1)), lower(p_email), v_req.is_demo_data)
      returning id into v_person;
  end if;
  insert into public.requisition_candidates (org_id, requisition_id, person_id, stage, is_demo_data)
    values (v_req.org_id, p_requisition_id, v_person, 'sourced', v_req.is_demo_data)
    returning id into v_rc;
  v_invite := public.assessment_invite_create(
    v_req.org_id, v_person, 'sample_personality_v0', 'personality', 14);
  v_token := (v_invite->>'token')::text;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_req.org_id, v_actor, 'requisition.candidate_added', 'requisition_candidates', v_rc,
      jsonb_build_object('person_id', v_person, 'email', lower(p_email),
                         'take_token', v_token, 'rationale_excerpt', left(p_rationale, 200)));
  insert into public.admin_decisions (org_id, person_id, kind, decided_by, rationale, target_entity_type, target_entity_id, overrode_recommendation)
    values (v_req.org_id, v_person, 'requisition_candidate_added', v_actor, p_rationale, 'requisition_candidates', v_rc, true);
  return jsonb_build_object(
    'requisition_candidate_id', v_rc,
    'person_id', v_person,
    'take_token', v_token,
    'take_url', '/take/' || v_token
  );
end;
$$;
revoke execute on function public.rpc_req_add_candidate(uuid, text, text, text) from public;
grant  execute on function public.rpc_req_add_candidate(uuid, text, text, text) to authenticated, service_role;

create or replace function public.rpc_req_candidates(p_requisition_id uuid)
returns table (
  id uuid, person_id uuid, full_name text, primary_email text, stage text,
  created_at timestamptz
) language plpgsql set search_path = '' security definer as $$
declare v_org uuid;
begin
  select org_id into v_org from public.requisitions where id = p_requisition_id;
  if v_org is null then raise exception 'rpc_req_candidates: requisition not found'; end if;
  if (select auth.uid()) is null or not public.has_permission(v_org, 'requisition.read') then
    raise exception 'rpc_req_candidates: requires requisition.read';
  end if;
  return query
    select rc.id, rc.person_id, p.full_name, p.primary_email, rc.stage::text, rc.created_at
    from public.requisition_candidates rc
    join public.people p on p.id = rc.person_id
    where rc.requisition_id = p_requisition_id
    order by rc.created_at desc;
end;
$$;
revoke execute on function public.rpc_req_candidates(uuid) from public;
grant  execute on function public.rpc_req_candidates(uuid) to authenticated, service_role;

create or replace function public.rpc_my_team()
returns table (
  person_id uuid, full_name text, primary_email text, org_id uuid, org_name text
) language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_pid uuid;
begin
  if v_caller is null then return; end if;
  select id into v_pid from public.people where auth_user_id = v_caller limit 1;
  if v_pid is null then return; end if;
  return query
    select p.id, p.full_name, p.primary_email, m.org_id, o.name
    from public.memberships my_m
    join public.memberships m on m.org_id = my_m.org_id and m.status = 'active' and m.person_id <> v_pid
    join public.people p on p.id = m.person_id
    join public.organizations o on o.id = m.org_id
    where my_m.person_id = v_pid and my_m.status = 'active'
    order by p.full_name;
end;
$$;
revoke execute on function public.rpc_my_team() from public;
grant  execute on function public.rpc_my_team() to authenticated, service_role;

create or replace function public.rpc_me_self_view()
returns jsonb language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_pid uuid;
begin
  if v_caller is null then raise exception 'rpc_me_self_view: not authenticated'; end if;
  select id into v_pid from public.people where auth_user_id = v_caller limit 1;
  if v_pid is null then raise exception 'rpc_me_self_view: no person bound to auth.uid()'; end if;
  return jsonb_build_object(
    'person', (select jsonb_build_object('id', id, 'full_name', full_name, 'primary_email', primary_email)
                from public.people where id = v_pid),
    'memberships', (select coalesce(jsonb_agg(jsonb_build_object('org_id', m.org_id, 'org_name', o.name, 'status', m.status::text)), '[]'::jsonb)
                    from public.memberships m join public.organizations o on o.id = m.org_id
                    where m.person_id = v_pid),
    'consents', (select coalesce(jsonb_agg(jsonb_build_object('purpose', cg.purpose, 'granted_to_org_id', cg.granted_to_org_id, 'active', cg.revoked_at is null)), '[]'::jsonb)
                 from public.consent_grants cg where cg.person_id = v_pid),
    'recent_activity', (select coalesce(jsonb_agg(jsonb_build_object('action', a.action, 'at', a."at", 'actor_person_id', a.actor_person_id) order by a."at" desc), '[]'::jsonb)
                        from public.audit_log a
                        where (a.entity_id = v_pid or a.actor_person_id = v_pid)
                        limit 25)
  );
end;
$$;
revoke execute on function public.rpc_me_self_view() from public;
grant  execute on function public.rpc_me_self_view() to authenticated, service_role;
