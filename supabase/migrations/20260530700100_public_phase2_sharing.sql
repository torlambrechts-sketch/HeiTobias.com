-- Public Surfaces Phase 2 — token-scoped public sharing of role profiles
-- and placement reports.
--
-- A recruiter shares a SPECIFIC role version or placement report with a
-- stakeholder who isn't in the platform. The public view is field-
-- stripped, watermarked, expiring, revocable, and access-logged.
--
-- Tables:
--   share_tokens         — one row per shared artefact + token
--   share_token_accesses — append-only access log (IP, UA, at)
--
-- The public read goes through SECDEF RPCs that return ONLY the
-- public-summary fields. The raw tables are never exposed to anon.

create type public.share_entity_kind as enum ('role_profile', 'placement_report');

create table if not exists public.share_tokens (
  id              uuid primary key default extensions.gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  entity_kind     public.share_entity_kind not null,
  entity_id       uuid not null,          -- roles_catalog.id OR placement_reports.id
  token           text not null unique,
  created_by      uuid references public.people(id) on delete set null,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null default (now() + interval '30 days'),
  revoked_at      timestamptz,
  access_count    int not null default 0,
  -- For placement reports: candidate can revoke (it's their data). We
  -- store the subject person_id so the /me/privacy surface can find and
  -- revoke it.
  subject_person_id uuid references public.people(id) on delete set null,
  -- Naming the artefact at share time keeps the public view stable even
  -- if the underlying row label changes.
  display_label   text
);
create index if not exists share_tokens_entity_idx on public.share_tokens (entity_kind, entity_id);
create index if not exists share_tokens_token_idx  on public.share_tokens (token);
create index if not exists share_tokens_subject_idx on public.share_tokens (subject_person_id);

create table if not exists public.share_token_accesses (
  id            uuid primary key default extensions.gen_random_uuid(),
  share_token_id uuid not null references public.share_tokens(id) on delete cascade,
  accessed_at   timestamptz not null default now(),
  ip            text,
  user_agent    text
);
create index if not exists share_token_accesses_idx on public.share_token_accesses (share_token_id, accessed_at desc);

alter table public.share_tokens enable row level security;
alter table public.share_tokens force  row level security;
alter table public.share_token_accesses enable row level security;
alter table public.share_token_accesses force  row level security;

-- Org members with role.read (for role profiles) / fit.read (for reports)
-- can see the share tokens for their org. The subject person can see
-- tokens about their own data.
drop policy if exists share_tokens_org_read on public.share_tokens;
create policy share_tokens_org_read on public.share_tokens
  for select to authenticated using (
    public.has_permission(org_id, 'role.read')
    or public.has_permission(org_id, 'fit.read')
    or public.is_self(subject_person_id)
  );

drop policy if exists share_token_accesses_org_read on public.share_token_accesses;
create policy share_token_accesses_org_read on public.share_token_accesses
  for select to authenticated using (
    exists (select 1 from public.share_tokens st
            where st.id = share_token_id
              and (public.has_permission(st.org_id, 'role.read')
                   or public.has_permission(st.org_id, 'fit.read')))
  );

-- ─── RPC: create a share token ──────────────────────────────────────
create or replace function public.share_token_create(
  p_entity_kind text,
  p_entity_id   uuid,
  p_expiry_days int default 30
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor   uuid := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
  v_org     uuid;
  v_token   text;
  v_subject uuid;
  v_label   text;
  v_id      uuid;
begin
  if v_actor is null then raise exception 'unauthenticated'; end if;
  if p_entity_kind not in ('role_profile', 'placement_report') then
    raise exception 'invalid entity_kind';
  end if;
  if p_expiry_days < 1 or p_expiry_days > 90 then
    raise exception 'expiry_days must be 1..90';
  end if;

  if p_entity_kind = 'role_profile' then
    select rc.org_id, rc.title into v_org, v_label
      from public.roles_catalog rc where rc.id = p_entity_id;
    if v_org is null then raise exception 'role not found'; end if;
    if not public.has_permission(v_org, 'role.read') then raise exception 'forbidden'; end if;
  else
    select pr.org_id, pr.person_id into v_org, v_subject
      from public.placement_reports pr where pr.id = p_entity_id;
    if v_org is null then raise exception 'placement report not found'; end if;
    if not public.has_permission(v_org, 'fit.read') then raise exception 'forbidden'; end if;
    v_label := 'Placement report';
  end if;

  v_token := replace(extensions.gen_random_uuid()::text, '-', '')
          || replace(extensions.gen_random_uuid()::text, '-', '');

  insert into public.share_tokens (org_id, entity_kind, entity_id, token, created_by, expires_at, subject_person_id, display_label)
  values (v_org, p_entity_kind::public.share_entity_kind, p_entity_id, v_token, v_actor,
          now() + make_interval(days => p_expiry_days), v_subject, v_label)
  returning id into v_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
  values (v_org, v_actor, 'share_token.create', p_entity_kind, p_entity_id,
          jsonb_build_object('share_token_id', v_id, 'expiry_days', p_expiry_days));

  return jsonb_build_object('ok', true, 'id', v_id, 'token', v_token);
end;
$$;
revoke execute on function public.share_token_create(text, uuid, int) from public;
grant  execute on function public.share_token_create(text, uuid, int) to authenticated;

-- ─── RPC: revoke a share token ──────────────────────────────────────
create or replace function public.share_token_revoke(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
  v_org   uuid;
  v_subject uuid;
begin
  if v_actor is null then raise exception 'unauthenticated'; end if;
  select org_id, subject_person_id into v_org, v_subject from public.share_tokens where id = p_id;
  if v_org is null then raise exception 'share token not found'; end if;
  -- Either an org member with the right permission, OR the data subject
  -- (a candidate revoking a placement report about themselves).
  if not (public.has_permission(v_org, 'role.read')
          or public.has_permission(v_org, 'fit.read')
          or public.is_self(v_subject)) then
    raise exception 'forbidden';
  end if;

  update public.share_tokens set revoked_at = now() where id = p_id and revoked_at is null;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
  values (v_org, v_actor, 'share_token.revoke', 'share_tokens', p_id, '{}'::jsonb);
end;
$$;
revoke execute on function public.share_token_revoke(uuid) from public;
grant  execute on function public.share_token_revoke(uuid) to authenticated;

-- ─── RPC: list share tokens for an entity ───────────────────────────
create or replace function public.share_tokens_for_entity(
  p_entity_kind text,
  p_entity_id   uuid
)
returns table (
  id uuid, token text, created_at timestamptz, expires_at timestamptz,
  revoked_at timestamptz, access_count int, created_by uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select st.id, st.token, st.created_at, st.expires_at, st.revoked_at, st.access_count, st.created_by
    from public.share_tokens st
   where st.entity_kind = p_entity_kind::public.share_entity_kind
     and st.entity_id = p_entity_id
     and (public.has_permission(st.org_id, 'role.read') or public.has_permission(st.org_id, 'fit.read'))
   order by st.created_at desc;
$$;
revoke execute on function public.share_tokens_for_entity(text, uuid) from public;
grant  execute on function public.share_tokens_for_entity(text, uuid) to authenticated;

-- ─── RPC: public read (anon) — role profile ─────────────────────────
-- Returns ONLY the public-summary fields. Strips recruiter notes,
-- provenance audit detail, and individual evaluator attributions.
-- Increments access_count + logs access. Honours expiry + revocation.
create or replace function public.public_role_view(
  p_token text,
  p_ip    text default null,
  p_ua    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_st   public.share_tokens%rowtype;
  v_role public.roles_catalog%rowtype;
  v_org_name text;
  v_def  jsonb;
begin
  select * into v_st from public.share_tokens
   where token = p_token and entity_kind = 'role_profile';
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if v_st.revoked_at is not null then return jsonb_build_object('ok', false, 'reason', 'revoked'); end if;
  if v_st.expires_at < now() then return jsonb_build_object('ok', false, 'reason', 'expired'); end if;

  select * into v_role from public.roles_catalog where id = v_st.entity_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'gone'); end if;

  select name into v_org_name from public.organizations where id = v_st.org_id;

  -- Field-strip the definition. We allow the public-summary sections but
  -- remove anything attributing individual evaluators or carrying raw
  -- provenance detail.
  v_def := coalesce(v_role.definition_json, '{}'::jsonb)
           - 'validation_and_defensibility_metadata';  -- strip raw provenance; summary added below

  -- Log access + bump counter.
  update public.share_tokens set access_count = access_count + 1 where id = v_st.id;
  insert into public.share_token_accesses (share_token_id, ip, user_agent) values (v_st.id, p_ip, p_ua);
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
  values (v_st.org_id, null, 'public_role_view.access', 'roles_catalog', v_role.id,
          jsonb_build_object('share_token_id', v_st.id));

  return jsonb_build_object(
    'ok', true,
    'shared_by_org', v_org_name,
    'shared_at', v_st.created_at,
    'title', v_role.title,
    'family', v_role.family,
    'version', v_role.version,
    'status', v_role.status,
    'definition', v_def,
    -- A summary of provenance WITHOUT individual attributions:
    'defensibility_summary', jsonb_build_object(
      'has_signoff', (v_role.signed_off_at is not null),
      'signed_off_at', v_role.signed_off_at
    )
  );
end;
$$;
revoke execute on function public.public_role_view(text, text, text) from public;
grant  execute on function public.public_role_view(text, text, text) to anon, authenticated;

-- ─── RPC: public read (anon) — placement report ─────────────────────
-- placement_reports stores report_html + a fit_result_id. Rather than
-- parse/strip HTML, the public view is rebuilt from explicitly-whitelisted
-- fields joined off the report: the role title, an anonymised candidate
-- label, and the fit_results.fit_json (which is the structured, dev_stub-
-- labelled multi-axis fit). Recruiter free-text notes are never selected,
-- so the strip is by construction — we only return what's whitelisted.
create or replace function public.public_placement_report_view(
  p_token text,
  p_ip    text default null,
  p_ua    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_st       public.share_tokens%rowtype;
  v_rep      public.placement_reports%rowtype;
  v_org_name text;
  v_fit_json jsonb;
  v_vs       text;
  v_stub     boolean;
  v_role_title text;
  v_cand_name  text;
begin
  select * into v_st from public.share_tokens
   where token = p_token and entity_kind = 'placement_report';
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if v_st.revoked_at is not null then return jsonb_build_object('ok', false, 'reason', 'revoked'); end if;
  if v_st.expires_at < now() then return jsonb_build_object('ok', false, 'reason', 'expired'); end if;

  select * into v_rep from public.placement_reports where id = v_st.entity_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'gone'); end if;

  select name into v_org_name from public.organizations where id = v_st.org_id;

  select fr.fit_json, fr.validity_status::text, fr._dev_stub
    into v_fit_json, v_vs, v_stub
    from public.fit_results fr where fr.id = v_rep.fit_result_id;

  select rc.title into v_role_title
    from public.requisitions rq join public.roles_catalog rc on rc.id = rq.role_id
   where rq.id = v_rep.requisition_id;

  -- Candidate is anonymised by default in the public view.
  select 'Candidate ' || substr(p.id::text, 1, 8) into v_cand_name
    from public.people p where p.id = v_rep.person_id;

  update public.share_tokens set access_count = access_count + 1 where id = v_st.id;
  insert into public.share_token_accesses (share_token_id, ip, user_agent) values (v_st.id, p_ip, p_ua);
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
  values (v_st.org_id, null, 'public_placement_report_view.access', 'placement_reports', v_rep.id,
          jsonb_build_object('share_token_id', v_st.id));

  return jsonb_build_object(
    'ok', true,
    'shared_by_org', v_org_name,
    'shared_at', v_st.created_at,
    'validity_status', v_vs,
    'dev_stub', coalesce(v_stub, false),
    'generated_at', v_rep.generated_at,
    'report', jsonb_build_object(
      'candidate', jsonb_build_object('name', v_cand_name, 'anonymized', true),
      'role', jsonb_build_object('title', v_role_title),
      'fit_summary', coalesce(v_fit_json, '{}'::jsonb)
    )
  );
end;
$$;
revoke execute on function public.public_placement_report_view(text, text, text) from public;
grant  execute on function public.public_placement_report_view(text, text, text) to anon, authenticated;

-- ─── RPC: subject's view of shares about their data ─────────────────
-- Used by /me/privacy so a candidate can see + revoke placement-report
-- shares concerning them.
create or replace function public.my_shared_artefacts()
returns table (
  id uuid, entity_kind public.share_entity_kind, display_label text,
  created_at timestamptz, expires_at timestamptz, revoked_at timestamptz, access_count int
)
language sql
stable
security definer
set search_path = ''
as $$
  select st.id, st.entity_kind, st.display_label, st.created_at, st.expires_at, st.revoked_at, st.access_count
    from public.share_tokens st
   where public.is_self(st.subject_person_id)
   order by st.created_at desc;
$$;
revoke execute on function public.my_shared_artefacts() from public;
grant  execute on function public.my_shared_artefacts() to authenticated;
