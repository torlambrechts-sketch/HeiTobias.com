-- Gap-closure step 2: HRIS / external-system integration registry.
create type public.integration_kind as enum
  ('hibob','personio','workday','slack','teams','google_calendar','outlook_calendar','generic_webhook');
create type public.integration_status as enum
  ('not_configured','configured','active','error','disabled');

create table public.integration_connectors (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  kind            public.integration_kind not null,
  status          public.integration_status not null default 'not_configured',
  display_name    text not null,
  config_json     jsonb not null default '{}'::jsonb,
  last_sync_at    timestamptz,
  last_error      text,
  created_by      uuid references public.people(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (org_id, kind)
);
create index integration_connectors_org_idx on public.integration_connectors (org_id);
create trigger trg_touch_integration_connectors before update on public.integration_connectors for each row execute function public.set_updated_at();
create trigger trg_audit_integration_connectors after insert or update or delete on public.integration_connectors for each row execute function public._audit_row();
alter table public.integration_connectors enable row level security;
alter table public.integration_connectors force  row level security;
create policy integration_connectors_select on public.integration_connectors for select to authenticated using (
  public.has_permission(org_id, 'org.manage_all')
);

create table public.integration_sync_runs (
  id           uuid primary key default extensions.gen_random_uuid(),
  connector_id uuid not null references public.integration_connectors(id) on delete cascade,
  started_at   timestamptz not null default now(),
  completed_at timestamptz,
  status       text not null default 'running',
  rows_synced  int,
  error_text   text,
  payload_summary jsonb not null default '{}'::jsonb
);
create index integration_sync_runs_connector_idx on public.integration_sync_runs (connector_id);
alter table public.integration_sync_runs enable row level security;
alter table public.integration_sync_runs force  row level security;
create policy integration_sync_runs_select on public.integration_sync_runs for select to authenticated using (
  exists (select 1 from public.integration_connectors c where c.id = connector_id and public.has_permission(c.org_id, 'org.manage_all'))
);

create or replace function public.integration_connector_upsert(
  p_org_id uuid, p_kind text, p_display_name text, p_status text, p_config jsonb,
  p_rationale text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_id     uuid;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'integration_connector_upsert: rationale >=20 chars';
  end if;
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'integration_connector_upsert: requires org.manage_all';
  end if;
  insert into public.integration_connectors (org_id, kind, status, display_name, config_json, created_by)
    values (p_org_id, p_kind::public.integration_kind, p_status::public.integration_status, p_display_name, coalesce(p_config,'{}'::jsonb), v_actor)
  on conflict (org_id, kind) do update set
    status = excluded.status,
    display_name = excluded.display_name,
    config_json = excluded.config_json,
    updated_at = now()
  returning id into v_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'integration.connector_upserted', 'integration_connectors', v_id,
            jsonb_build_object('kind', p_kind, 'status', p_status, 'rationale_excerpt', left(p_rationale, 200)));
  insert into public.admin_decisions (org_id, kind, decided_by, rationale, target_entity_type, target_entity_id, overrode_recommendation)
    values (p_org_id, 'integration_connector_change', v_actor, p_rationale, 'integration_connectors', v_id, true);
  return v_id;
end;
$$;
revoke execute on function public.integration_connector_upsert(uuid, text, text, text, jsonb, text) from public;
grant  execute on function public.integration_connector_upsert(uuid, text, text, text, jsonb, text) to authenticated, service_role;

create or replace function public.integration_connectors_for_org(p_org_id uuid)
returns table (
  id uuid, kind text, status text, display_name text, last_sync_at timestamptz, last_error text, created_at timestamptz
) language plpgsql set search_path = '' security definer as $$
begin
  if (select auth.uid()) is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'integration_connectors_for_org: requires org.manage_all';
  end if;
  return query
    select c.id, c.kind::text, c.status::text, c.display_name, c.last_sync_at, c.last_error, c.created_at
    from public.integration_connectors c
    where c.org_id = p_org_id
    order by c.kind;
end;
$$;
revoke execute on function public.integration_connectors_for_org(uuid) from public;
grant  execute on function public.integration_connectors_for_org(uuid) to authenticated, service_role;
