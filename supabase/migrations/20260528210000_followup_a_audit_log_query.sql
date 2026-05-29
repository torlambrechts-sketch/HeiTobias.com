-- Step A — paginated, filterable audit-log viewer for the §E
-- Compliance tab. Read-only, gated by org.manage_all. Filters:
-- action prefix, actor person_id, entity_type, since/until.
-- Returns total + page so the UI can render "1–50 of N".

create or replace function public.admin_audit_log_query(
  p_org_id        uuid,
  p_action_like   text default null,
  p_actor_id      uuid default null,
  p_entity_type   text default null,
  p_since         timestamptz default null,
  p_until         timestamptz default null,
  p_limit         int default 50,
  p_offset        int default 0
)
returns jsonb language plpgsql set search_path = '' stable security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_rows jsonb; v_total bigint; v_limit int; v_offset int;
begin
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'admin_audit_log_query: requires org.manage_all';
  end if;
  v_limit  := least(coalesce(p_limit, 50), 200);
  v_offset := greatest(coalesce(p_offset, 0), 0);

  select count(*) into v_total from public.audit_log a
    where a.org_id = p_org_id
      and (p_action_like is null or a.action like p_action_like)
      and (p_actor_id    is null or a.actor_person_id = p_actor_id)
      and (p_entity_type is null or a.entity_type = p_entity_type)
      and (p_since       is null or a.at >= p_since)
      and (p_until       is null or a.at <= p_until);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'at', a.at, 'action', a.action,
    'entity_type', a.entity_type, 'entity_id', a.entity_id,
    'actor_person_id', a.actor_person_id,
    'actor_name', p.full_name,
    'after_excerpt', case when jsonb_typeof(a.after_json) = 'object' then a.after_json else null end)
    order by a.at desc), '[]'::jsonb)
  into v_rows
  from (
    select * from public.audit_log a
      where a.org_id = p_org_id
        and (p_action_like is null or a.action like p_action_like)
        and (p_actor_id    is null or a.actor_person_id = p_actor_id)
        and (p_entity_type is null or a.entity_type = p_entity_type)
        and (p_since       is null or a.at >= p_since)
        and (p_until       is null or a.at <= p_until)
      order by a.at desc
      limit v_limit offset v_offset
  ) a
  left join public.people p on p.id = a.actor_person_id;

  return jsonb_build_object(
    'rows', v_rows, 'total', v_total, 'limit', v_limit, 'offset', v_offset,
    'filters', jsonb_build_object('action_like', p_action_like, 'actor_id', p_actor_id, 'entity_type', p_entity_type, 'since', p_since, 'until', p_until));
end;
$$;
revoke execute on function public.admin_audit_log_query(uuid, text, uuid, text, timestamptz, timestamptz, int, int) from public;
grant  execute on function public.admin_audit_log_query(uuid, text, uuid, text, timestamptz, timestamptz, int, int) to authenticated, service_role;
