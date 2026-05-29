-- Production email outbox + bounce suppression.
-- Real transport (Postmark / SendGrid EU / SES) is operator-wired and
-- reads from email_outbox. Until SMTP_PROVIDER is configured, rows
-- accumulate at status='pending' — visible in the admin Notifications
-- tab.

create table public.email_outbox (
  id                  uuid primary key default extensions.gen_random_uuid(),
  org_id              uuid not null references public.organizations(id),
  to_email            text not null,
  to_name             text,
  from_email          text not null,
  from_name           text,
  reply_to            text,
  template_key        text not null,
  locale              text not null default 'en',
  subject             text not null,
  body_text           text not null,
  body_html           text not null,
  render_data         jsonb not null default '{}'::jsonb,
  status              public.notification_status not null default 'pending',
  attempts            int not null default 0,
  last_error          text,
  provider_message_id text,
  triggered_by_action text,
  created_at          timestamptz not null default now(),
  dispatched_at       timestamptz,
  delivered_at        timestamptz,
  failed_at           timestamptz,
  is_demo_data        boolean not null default false
);
create index email_outbox_org_idx       on public.email_outbox (org_id, status);
create index email_outbox_to_email_idx  on public.email_outbox (to_email);
create trigger trg_audit_email_outbox after insert or update or delete on public.email_outbox for each row execute function public._audit_row();
alter table public.email_outbox enable row level security;
alter table public.email_outbox force  row level security;
create policy email_outbox_org_select on public.email_outbox for select to authenticated using (
  public.has_permission(org_id, 'org.manage_all')
);

create table public.email_suppressions (
  id            uuid primary key default extensions.gen_random_uuid(),
  email         text not null,
  reason        text not null,
  source_event_json jsonb not null default '{}'::jsonb,
  suppressed_at timestamptz not null default now(),
  unique (email)
);
alter table public.email_suppressions enable row level security;
alter table public.email_suppressions force  row level security;
create policy email_suppressions_admin_read on public.email_suppressions for select to authenticated using (
  exists (select 1 from public.memberships m
          join public.membership_roles mr on mr.membership_id = m.id
          join public.rbac_role_permissions rrp on rrp.role_id = mr.rbac_role_id
          join public.rbac_permissions rp on rp.id = rrp.permission_id
          where m.person_id = (select id from public.people where auth_user_id = (select auth.uid()) limit 1)
            and rp.key = 'org.manage_all')
);

create or replace function public.email_enqueue(
  p_org_id uuid, p_to_email text, p_to_name text, p_template_key text, p_locale text,
  p_subject text, p_body_text text, p_body_html text,
  p_render_data jsonb default '{}'::jsonb,
  p_triggered_by_action text default null
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_id     uuid;
  v_org    public.organizations%rowtype;
  v_from   text;
  v_from_name text;
  v_reply  text;
begin
  if v_caller is null then raise exception 'email_enqueue: not authenticated'; end if;
  if exists (select 1 from public.email_suppressions where email = lower(p_to_email)) then
    raise exception 'email_enqueue: address % is suppressed (hard bounce / complaint)', p_to_email;
  end if;
  select * into v_org from public.organizations where id = p_org_id;
  v_from := coalesce(v_org.settings_json ->> 'from_email', 'no-reply@heitobias.com');
  v_from_name := coalesce(v_org.settings_json ->> 'from_name', v_org.name);
  v_reply := coalesce(v_org.settings_json ->> 'reply_to', v_from);
  insert into public.email_outbox (org_id, to_email, to_name, from_email, from_name, reply_to,
                                    template_key, locale, subject, body_text, body_html,
                                    render_data, triggered_by_action, is_demo_data)
  values (p_org_id, lower(p_to_email), p_to_name, v_from, v_from_name, v_reply,
          p_template_key, p_locale, p_subject, p_body_text, p_body_html,
          coalesce(p_render_data, '{}'::jsonb), p_triggered_by_action,
          coalesce(v_org.is_demo_data, false))
  returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'email.enqueued', 'email_outbox', v_id,
            jsonb_build_object('template', p_template_key, 'to', p_to_email, 'locale', p_locale));
  return v_id;
end;
$$;
revoke execute on function public.email_enqueue(uuid, text, text, text, text, text, text, text, jsonb, text) from public;
grant  execute on function public.email_enqueue(uuid, text, text, text, text, text, text, text, jsonb, text) to authenticated, service_role;

create or replace function public.email_mark(p_id uuid, p_status text, p_provider_message_id text default null, p_error text default null)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_org uuid;
begin
  select org_id into v_org from public.email_outbox where id = p_id;
  if v_org is null then raise exception 'email_mark: not found'; end if;
  update public.email_outbox set
    status = p_status::public.notification_status,
    attempts = attempts + 1,
    last_error = p_error,
    provider_message_id = coalesce(p_provider_message_id, provider_message_id),
    dispatched_at = case when p_status = 'dispatched' then now() else dispatched_at end,
    delivered_at  = case when p_status = 'delivered'  then now() else delivered_at end,
    failed_at     = case when p_status = 'failed'     then now() else failed_at end
  where id = p_id;
  return p_id;
end;
$$;
revoke execute on function public.email_mark(uuid, text, text, text) from public;
grant  execute on function public.email_mark(uuid, text, text, text) to authenticated, service_role;

create or replace function public.email_record_bounce(p_email text, p_reason text, p_event jsonb)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_id uuid;
begin
  insert into public.email_suppressions (email, reason, source_event_json)
  values (lower(p_email), p_reason, coalesce(p_event, '{}'::jsonb))
  on conflict (email) do update set
    reason = excluded.reason,
    source_event_json = excluded.source_event_json,
    suppressed_at = now()
  returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (null, null, 'email.bounced', 'email_suppressions', v_id,
            jsonb_build_object('email', lower(p_email), 'reason', p_reason));
  return v_id;
end;
$$;
revoke execute on function public.email_record_bounce(text, text, jsonb) from public;
grant  execute on function public.email_record_bounce(text, text, jsonb) to service_role;
