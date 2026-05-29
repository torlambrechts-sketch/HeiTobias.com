-- ITEM 4: audit-log explorer extras — actor list, compliance view, export.
-- Adds three SECDEF helpers:
--   * admin_audit_actors        — autocomplete for the actor filter
--   * admin_audit_compliance_view — pre-filtered subset for AI Act Art. 12
--                                   + GDPR Art. 30 review
--   * admin_audit_log_export    — JSON/CSV export that writes its own
--                                  'audit_log_exported_by' audit row

create or replace function public.admin_audit_actors(p_org_id uuid)
returns table (person_id uuid, full_name text, primary_email text) language plpgsql set search_path = '' security definer as $$
begin
  if (select auth.uid()) is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'admin_audit_actors: requires org.manage_all';
  end if;
  return query
    select p.id, p.full_name, p.primary_email
    from public.people p
    join public.memberships m on m.person_id = p.id and m.org_id = p_org_id
    order by p.full_name;
end;
$$;
revoke execute on function public.admin_audit_actors(uuid) from public;
grant  execute on function public.admin_audit_actors(uuid) to authenticated, service_role;

create or replace function public.admin_audit_compliance_view(
  p_org_id uuid,
  p_since timestamptz default null,
  p_until timestamptz default null,
  p_limit int default 200,
  p_offset int default 0
)
returns table (
  id uuid, action text, entity_type text, entity_id uuid, actor_person_id uuid,
  actor_name text, "at" timestamptz, before_json jsonb, after_json jsonb
) language plpgsql set search_path = '' security definer as $$
begin
  if (select auth.uid()) is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'admin_audit_compliance_view: requires org.manage_all';
  end if;
  return query
    select a.id, a.action, a.entity_type, a.entity_id, a.actor_person_id,
           p.full_name as actor_name, a."at", a.before_json, a.after_json
    from public.audit_log a
    left join public.people p on p.id = a.actor_person_id
    where a.org_id = p_org_id
      and (p_since is null or a."at" >= p_since)
      and (p_until is null or a."at" <= p_until)
      and (
        a.action like 'consent.%' or
        a.action like 'org.role_%' or
        a.action like 'org.module_%' or
        a.action like 'org.settings_%' or
        a.action like 'org.user_%' or
        a.action = 'placement.executed' or
        a.action = 'role.signed_off' or
        a.action = 'team_def.signed_off' or
        a.action like 'audit_log_exported_%'
      )
    order by a."at" desc
    limit p_limit offset p_offset;
end;
$$;
revoke execute on function public.admin_audit_compliance_view(uuid, timestamptz, timestamptz, int, int) from public;
grant  execute on function public.admin_audit_compliance_view(uuid, timestamptz, timestamptz, int, int) to authenticated, service_role;

create or replace function public.admin_audit_log_export(
  p_org_id uuid,
  p_action_like text default null,
  p_actor_id uuid default null,
  p_entity_type text default null,
  p_since timestamptz default null,
  p_until timestamptz default null,
  p_format text default 'json',
  p_limit int default 5000
)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_rows   jsonb;
  v_count  int;
begin
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'admin_audit_log_export: requires org.manage_all';
  end if;
  if p_format not in ('json','csv') then
    raise exception 'admin_audit_log_export: format must be json or csv';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'action', a.action, 'entity_type', a.entity_type, 'entity_id', a.entity_id,
           'actor_person_id', a.actor_person_id, 'actor_name', p.full_name, 'at', a."at",
           'before_json', a.before_json, 'after_json', a.after_json) order by a."at" desc), '[]'::jsonb),
         count(*) into v_rows, v_count
  from public.audit_log a
  left join public.people p on p.id = a.actor_person_id
  where a.org_id = p_org_id
    and (p_action_like is null or a.action like p_action_like)
    and (p_actor_id   is null or a.actor_person_id = p_actor_id)
    and (p_entity_type is null or a.entity_type = p_entity_type)
    and (p_since is null or a."at" >= p_since)
    and (p_until is null or a."at" <= p_until);
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'audit_log_exported_by', 'audit_log', null,
      jsonb_build_object('format', p_format, 'row_count', v_count,
                         'filters', jsonb_strip_nulls(jsonb_build_object(
                           'action_like', p_action_like, 'actor_id', p_actor_id,
                           'entity_type', p_entity_type, 'since', p_since, 'until', p_until))));
  return jsonb_build_object('format', p_format, 'count', v_count, 'rows', v_rows);
end;
$$;
revoke execute on function public.admin_audit_log_export(uuid, text, uuid, text, timestamptz, timestamptz, text, int) from public;
grant  execute on function public.admin_audit_log_export(uuid, text, uuid, text, timestamptz, timestamptz, text, int) to authenticated, service_role;
