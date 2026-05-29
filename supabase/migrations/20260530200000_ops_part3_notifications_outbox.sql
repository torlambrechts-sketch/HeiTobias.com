-- Gap-closure step 1: notification dispatch outbox.
create type public.notification_channel as enum
  ('in_app','email','slack','teams','calendar');
create type public.notification_status as enum
  ('pending','dispatched','delivered','failed','suppressed');

create table public.notifications (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id),
  recipient_person_id uuid not null references public.people(id),
  channel             public.notification_channel not null,
  subject             text not null,
  body                text not null,
  payload_json        jsonb not null default '{}'::jsonb,
  status              public.notification_status not null default 'pending',
  attempts            int not null default 0,
  last_error          text,
  created_at          timestamptz not null default now(),
  dispatched_at       timestamptz,
  delivered_at        timestamptz,
  failed_at           timestamptz,
  is_demo_data        boolean not null default false
);
create index notifications_org_idx       on public.notifications (org_id, status);
create index notifications_recipient_idx on public.notifications (recipient_person_id);
create trigger trg_audit_notifications after insert or update or delete on public.notifications for each row execute function public._audit_row();
alter table public.notifications enable row level security;
alter table public.notifications force  row level security;
create policy notifications_select on public.notifications for select to authenticated using (
  public.is_self(recipient_person_id)
  or public.has_permission(org_id, 'org.manage_all')
);

create or replace function public.notifications_enqueue(
  p_org_id uuid, p_recipient_id uuid, p_channel text,
  p_subject text, p_body text, p_payload jsonb default '{}'::jsonb
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_id     uuid;
begin
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'notifications_enqueue: requires org.manage_all';
  end if;
  insert into public.notifications (org_id, recipient_person_id, channel, subject, body, payload_json, is_demo_data)
    values (p_org_id, p_recipient_id, p_channel::public.notification_channel, p_subject, p_body, coalesce(p_payload,'{}'::jsonb),
            coalesce((select is_demo_data from public.organizations where id = p_org_id), false))
    returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'notification.enqueued', 'notifications', v_id,
            jsonb_build_object('channel', p_channel, 'recipient_id', p_recipient_id));
  return v_id;
end;
$$;
revoke execute on function public.notifications_enqueue(uuid, uuid, text, text, text, jsonb) from public;
grant  execute on function public.notifications_enqueue(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function public.notifications_mark(p_id uuid, p_status text, p_error text default null)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_org uuid;
begin
  select org_id into v_org from public.notifications where id = p_id;
  if v_org is null then raise exception 'notifications_mark: not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'notifications_mark: requires org.manage_all';
  end if;
  update public.notifications set
    status = p_status::public.notification_status,
    attempts = attempts + 1,
    last_error = p_error,
    dispatched_at = case when p_status = 'dispatched' then now() else dispatched_at end,
    delivered_at  = case when p_status = 'delivered'  then now() else delivered_at end,
    failed_at     = case when p_status = 'failed'     then now() else failed_at end
  where id = p_id;
  return p_id;
end;
$$;
revoke execute on function public.notifications_mark(uuid, text, text) from public;
grant  execute on function public.notifications_mark(uuid, text, text) to authenticated, service_role;

create or replace function public.notifications_list_for_org(
  p_org_id uuid, p_limit int default 100, p_offset int default 0
)
returns table (
  id uuid, recipient_person_id uuid, recipient_name text, channel text,
  subject text, status text, attempts int, last_error text,
  created_at timestamptz, delivered_at timestamptz
) language plpgsql set search_path = '' security definer as $$
begin
  if (select auth.uid()) is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'notifications_list_for_org: requires org.manage_all';
  end if;
  return query
    select n.id, n.recipient_person_id, p.full_name::text, n.channel::text,
           n.subject, n.status::text, n.attempts, n.last_error,
           n.created_at, n.delivered_at
    from public.notifications n
    join public.people p on p.id = n.recipient_person_id
    where n.org_id = p_org_id
    order by n.created_at desc
    limit p_limit offset p_offset;
end;
$$;
revoke execute on function public.notifications_list_for_org(uuid, int, int) from public;
grant  execute on function public.notifications_list_for_org(uuid, int, int) to authenticated, service_role;
