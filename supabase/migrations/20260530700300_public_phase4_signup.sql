-- Public Surfaces Phase 4 — self-serve signup + external notification
-- preferences.
--
-- Signup does NOT auto-provision an org. It records a
-- contact_requests row (kind='design_partner_signup' or
-- 'commercial_signup') carrying the org basics in payload_json + creates
-- the Supabase auth user (client-side via supabase.auth.signUp). A
-- platform_admin reviews and, on approval, provisions the org via the
-- existing platform_org_create (A9). This is deliberate for the
-- design-partner stage.
--
-- This migration adds:
--   1. signup_submit(...) — anon RPC recording the pending application
--      (reuses contact_requests).
--   2. notif_prefs_by_token surfaces for external users — a token-keyed
--      view + update of notification_preferences, so candidates / SMEs /
--      pre-claim employees can manage email categories without an account.
--      The token is an opaque per-person value stored on a new
--      notification_pref_tokens table.

-- ─── 1. signup_submit ───────────────────────────────────────────────
create or replace function public.signup_submit(
  p_email     text,
  p_name      text,
  p_org_name  text,
  p_org_type  text,
  p_country   text default 'NO',
  p_locale    text default 'nb-NO',
  p_size      text default null,
  p_commercial boolean default false,
  p_hp        text default null
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
  if coalesce(p_hp, '') <> '' then
    return jsonb_build_object('ok', true);   -- honeypot: silently drop
  end if;
  if p_email is null or p_email !~ '^[^@]+@[^@]+\.[^@]+$' then raise exception 'invalid_email'; end if;
  if char_length(coalesce(p_name, '')) < 1 then raise exception 'name_required'; end if;
  if char_length(coalesce(p_org_name, '')) < 2 then raise exception 'org_name_required'; end if;
  if p_org_type not in ('agency', 'employer', 'hybrid') then raise exception 'invalid_org_type'; end if;

  select count(*) into v_recent from public.contact_requests
   where lower(email) = lower(p_email) and created_at > now() - interval '60 seconds';
  if v_recent >= 3 then raise exception 'rate_limited'; end if;

  insert into public.contact_requests (kind, name, email, organization, interest, payload_json)
  values (
    case when p_commercial then 'commercial_signup' else 'design_partner_signup' end,
    p_name, lower(p_email), p_org_name, p_org_type,
    jsonb_build_object('org_type', p_org_type, 'country', p_country, 'locale', p_locale, 'size', p_size)
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;
revoke execute on function public.signup_submit(text, text, text, text, text, text, text, boolean, text) from public;
grant  execute on function public.signup_submit(text, text, text, text, text, text, text, boolean, text) to anon, authenticated;

-- ─── 2. external notification preference tokens ─────────────────────
create table if not exists public.notification_pref_tokens (
  token       text primary key,
  person_id   uuid not null references public.people(id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index if not exists notif_pref_tokens_person_idx on public.notification_pref_tokens (person_id);

alter table public.notification_pref_tokens enable row level security;
alter table public.notification_pref_tokens force  row level security;
-- No anon/authenticated table policy; access is via SECDEF RPCs by token.

-- Mint (or fetch) a stable preferences token for a person. Called when a
-- transactional email is composed (so the unsubscribe link can be built).
-- SECDEF, callable by service_role / authenticated org admins who send.
create or replace function public.notif_pref_token_for(p_person_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare v_token text;
begin
  select token into v_token from public.notification_pref_tokens where person_id = p_person_id limit 1;
  if v_token is not null then return v_token; end if;
  v_token := replace(extensions.gen_random_uuid()::text, '-', '')
          || replace(extensions.gen_random_uuid()::text, '-', '');
  insert into public.notification_pref_tokens (token, person_id) values (v_token, p_person_id);
  return v_token;
end;
$$;
revoke execute on function public.notif_pref_token_for(uuid) from public;
grant  execute on function public.notif_pref_token_for(uuid) to authenticated, service_role;

-- Read a person's notification categories by token (anon — the token is
-- the proof). Returns the known categories + whether each is enabled +
-- whether it's mandatory (transactional).
create or replace function public.notif_prefs_by_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pid uuid;
  v_prefs jsonb;
begin
  select person_id into v_pid from public.notification_pref_tokens where token = p_token;
  if v_pid is null then return jsonb_build_object('ok', false, 'reason', 'invalid_token'); end if;

  -- Known categories. 'consent_confirmations' is mandatory (transactional);
  -- the rest are opt-out-able. We read current per-category state from
  -- notification_preferences (in_app channel rows double as the email
  -- category switches here for simplicity).
  v_prefs := jsonb_build_object(
    'consent_confirmations', jsonb_build_object('enabled', true, 'mandatory', true),
    'status_updates', jsonb_build_object(
      'enabled', coalesce((select enabled from public.notification_preferences
                            where person_id = v_pid and kind = 'status_updates' limit 1), true),
      'mandatory', false),
    'reminders', jsonb_build_object(
      'enabled', coalesce((select enabled from public.notification_preferences
                           where person_id = v_pid and kind = 'reminders' limit 1), true),
      'mandatory', false)
  );
  return jsonb_build_object('ok', true, 'categories', v_prefs);
end;
$$;
revoke execute on function public.notif_prefs_by_token(text) from public;
grant  execute on function public.notif_prefs_by_token(text) to anon, authenticated;

-- Set a category on/off by token. Refuses to disable mandatory categories.
create or replace function public.notif_prefs_set_by_token(
  p_token text, p_kind text, p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_pid uuid;
begin
  select person_id into v_pid from public.notification_pref_tokens where token = p_token;
  if v_pid is null then return jsonb_build_object('ok', false, 'reason', 'invalid_token'); end if;
  if p_kind = 'consent_confirmations' then
    return jsonb_build_object('ok', false, 'reason', 'mandatory_category',
      'message', 'Consent confirmations are transactional and cannot be turned off. To stop them, revoke the underlying relationship.');
  end if;
  if p_kind not in ('status_updates', 'reminders') then
    return jsonb_build_object('ok', false, 'reason', 'unknown_category');
  end if;

  insert into public.notification_preferences (person_id, channel, kind, enabled)
  values (v_pid, 'email', p_kind, p_enabled)
  on conflict (person_id, channel, kind) do update set enabled = excluded.enabled, updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function public.notif_prefs_set_by_token(text, text, boolean) from public;
grant  execute on function public.notif_prefs_set_by_token(text, text, boolean) to anon, authenticated;
