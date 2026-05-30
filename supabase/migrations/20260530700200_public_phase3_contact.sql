-- Public Surfaces Phase 3 — contact / demo requests.
--
-- The marketing contact form + the design-partner signup application
-- both write here. platform_admin reviews from the platform-admin
-- surface. Anon can INSERT (rate-limited at the edge + honeypot in the
-- form) via a SECDEF RPC; nobody anon can SELECT.

create table if not exists public.contact_requests (
  id            uuid primary key default extensions.gen_random_uuid(),
  kind          text not null default 'demo'
                  check (kind in ('demo', 'design_partner_signup', 'commercial_signup', 'press', 'other')),
  name          text not null,
  email         text not null,
  organization  text,
  role          text,
  interest      text,                 -- agency | employer | academic | press | other
  message       text,
  payload_json  jsonb not null default '{}'::jsonb,  -- signup carries org basics here
  status        text not null default 'new'
                  check (status in ('new', 'reviewing', 'approved', 'declined', 'responded')),
  created_at    timestamptz not null default now(),
  handled_by    uuid references public.people(id) on delete set null,
  handled_at    timestamptz
);
create index if not exists contact_requests_status_idx on public.contact_requests (status, created_at desc);
create index if not exists contact_requests_email_idx  on public.contact_requests (lower(email));

alter table public.contact_requests enable row level security;
alter table public.contact_requests force  row level security;

-- Only platform_admin reads. No anon/authenticated SELECT.
drop policy if exists contact_requests_admin_read on public.contact_requests;
create policy contact_requests_admin_read on public.contact_requests
  for select to authenticated using (public.is_platform_admin());

-- ─── RPC: submit (anon) ─────────────────────────────────────────────
-- Honeypot: p_hp must be empty (bots fill hidden fields). Light dedupe:
-- collapse repeated identical submissions from the same email within
-- 60 seconds.
create or replace function public.contact_request_submit(
  p_kind    text,
  p_name    text,
  p_email   text,
  p_organization text default null,
  p_role    text default null,
  p_interest text default null,
  p_message text default null,
  p_payload jsonb default '{}'::jsonb,
  p_hp      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_recent int;
begin
  -- Honeypot: silently succeed without recording (don't tell the bot).
  if coalesce(p_hp, '') <> '' then
    return jsonb_build_object('ok', true);
  end if;
  if p_name is null or char_length(p_name) < 1 then raise exception 'name_required'; end if;
  if p_email is null or p_email !~ '^[^@]+@[^@]+\.[^@]+$' then raise exception 'invalid_email'; end if;
  if p_kind not in ('demo', 'design_partner_signup', 'commercial_signup', 'press', 'other') then
    raise exception 'invalid_kind';
  end if;

  -- Light rate-limit / dedupe.
  select count(*) into v_recent from public.contact_requests
   where lower(email) = lower(p_email) and created_at > now() - interval '60 seconds';
  if v_recent >= 3 then
    raise exception 'rate_limited';
  end if;

  insert into public.contact_requests (kind, name, email, organization, role, interest, message, payload_json)
  values (p_kind, p_name, lower(p_email), p_organization, p_role, p_interest, p_message, coalesce(p_payload, '{}'::jsonb))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;
revoke execute on function public.contact_request_submit(text, text, text, text, text, text, text, jsonb, text) from public;
grant  execute on function public.contact_request_submit(text, text, text, text, text, text, text, jsonb, text) to anon, authenticated;

-- ─── RPC: list (platform_admin) ─────────────────────────────────────
create or replace function public.contact_requests_list(p_status text default null)
returns setof public.contact_requests
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.contact_requests
   where public.is_platform_admin()
     and (p_status is null or status = p_status)
   order by created_at desc
   limit 200;
$$;
revoke execute on function public.contact_requests_list(text) from public;
grant  execute on function public.contact_requests_list(text) to authenticated;

-- ─── RPC: set status (platform_admin) ───────────────────────────────
create or replace function public.contact_request_set_status(p_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_actor uuid := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
begin
  if not public.is_platform_admin() then raise exception 'forbidden'; end if;
  if p_status not in ('new', 'reviewing', 'approved', 'declined', 'responded') then
    raise exception 'invalid_status';
  end if;
  update public.contact_requests set status = p_status, handled_by = v_actor, handled_at = now() where id = p_id;
  insert into public.platform_admin_investigation_log (actor_person_id, action, target_org_id, payload_json)
  values (v_actor, 'contact_request.set_status', null, jsonb_build_object('id', p_id, 'status', p_status));
end;
$$;
revoke execute on function public.contact_request_set_status(uuid, text) from public;
grant  execute on function public.contact_request_set_status(uuid, text) to authenticated;
