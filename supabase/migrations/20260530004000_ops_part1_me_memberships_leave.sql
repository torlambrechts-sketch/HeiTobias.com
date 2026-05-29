-- ITEM 5: self-profile expansion — memberships list + leave-org grace flow.
-- Adds 'leaving' enum value + 4 RPCs: me_memberships, me_leave_request
-- (rationale >=20 chars, 7-day grace), me_leave_cancel, me_audit_log.
-- Background expiry of leaving → inactive after 7 days is operator
-- work (cron/scheduler) — out-of-scope for closure pass per the
-- closure-prompt operator list.

alter type public.membership_status add value if not exists 'leaving';

create or replace function public.me_memberships()
returns table (membership_id uuid, org_id uuid, org_name text, status text, roles text[]) language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_pid uuid;
begin
  if v_caller is null then raise exception 'me_memberships: not authenticated'; end if;
  select id into v_pid from public.people where auth_user_id = v_caller limit 1;
  if v_pid is null then return; end if;
  return query
    select m.id, m.org_id, o.name, m.status::text,
      coalesce(array_agg(r.key) filter (where r.key is not null), '{}'::text[])
    from public.memberships m
    join public.organizations o on o.id = m.org_id
    left join public.membership_roles mr on mr.membership_id = m.id
    left join public.rbac_roles r on r.id = mr.rbac_role_id
    where m.person_id = v_pid
    group by m.id, m.org_id, o.name, m.status;
end;
$$;
revoke execute on function public.me_memberships() from public;
grant  execute on function public.me_memberships() to authenticated, service_role;

create or replace function public.me_leave_request(p_membership_id uuid, p_rationale text)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_mem    public.memberships%rowtype;
  v_grace  timestamptz;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'me_leave_request: rationale >=20 chars required';
  end if;
  select * into v_mem from public.memberships where id = p_membership_id;
  if v_mem.person_id <> v_actor then
    raise exception 'me_leave_request: caller can only leave their own membership';
  end if;
  v_grace := now() + interval '7 days';
  update public.memberships set status = 'leaving', updated_at = now() where id = p_membership_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_mem.org_id, v_actor, 'org.user_leave_requested', 'memberships', p_membership_id,
      jsonb_build_object('grace_until', v_grace, 'rationale_excerpt', left(p_rationale, 200)));
  insert into public.admin_decisions (org_id, person_id, kind, decided_by, rationale, evidence_ref, target_entity_type, target_entity_id, overrode_recommendation)
    values (v_mem.org_id, v_actor, 'user_leave_request', v_actor, p_rationale, v_grace::text, 'memberships', p_membership_id, true);
  return jsonb_build_object('membership_id', p_membership_id, 'grace_until', v_grace);
end;
$$;
revoke execute on function public.me_leave_request(uuid, text) from public;
grant  execute on function public.me_leave_request(uuid, text) to authenticated, service_role;

create or replace function public.me_leave_cancel(p_membership_id uuid, p_rationale text)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_mem    public.memberships%rowtype;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'me_leave_cancel: rationale >=20 chars required';
  end if;
  select * into v_mem from public.memberships where id = p_membership_id;
  if v_mem.person_id <> v_actor then
    raise exception 'me_leave_cancel: caller can only cancel their own leave';
  end if;
  if v_mem.status::text <> 'leaving' then
    raise exception 'me_leave_cancel: membership is not in leaving state (current: %)', v_mem.status;
  end if;
  update public.memberships set status = 'active', updated_at = now() where id = p_membership_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_mem.org_id, v_actor, 'org.user_leave_cancelled', 'memberships', p_membership_id,
      jsonb_build_object('rationale_excerpt', left(p_rationale, 200)));
  insert into public.admin_decisions (org_id, person_id, kind, decided_by, rationale, target_entity_type, target_entity_id, overrode_recommendation)
    values (v_mem.org_id, v_actor, 'user_leave_cancel', v_actor, p_rationale, 'memberships', p_membership_id, true);
  return p_membership_id;
end;
$$;
revoke execute on function public.me_leave_cancel(uuid, text) from public;
grant  execute on function public.me_leave_cancel(uuid, text) to authenticated, service_role;

create or replace function public.me_audit_log(p_limit int default 100, p_offset int default 0)
returns table (
  id uuid, org_id uuid, action text, entity_type text, entity_id uuid, "at" timestamptz,
  before_json jsonb, after_json jsonb
) language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_pid uuid;
begin
  if v_caller is null then raise exception 'me_audit_log: not authenticated'; end if;
  select id into v_pid from public.people where auth_user_id = v_caller limit 1;
  if v_pid is null then return; end if;
  return query
    select a.id, a.org_id, a.action, a.entity_type, a.entity_id, a."at", a.before_json, a.after_json
    from public.audit_log a
    where a.actor_person_id = v_pid
    order by a."at" desc
    limit p_limit offset p_offset;
end;
$$;
revoke execute on function public.me_audit_log(int, int) from public;
grant  execute on function public.me_audit_log(int, int) to authenticated, service_role;
