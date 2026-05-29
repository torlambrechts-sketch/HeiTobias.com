-- ITEM 1 fix-up: org_invite_accept_v2 was setting accepted_by to the
-- auth.users.id (auth.uid()) but invite_tokens.accepted_by FKs to
-- people.id. The accepter must be the people.id; bind auth_user_id
-- to people on first accept if not yet bound.

create or replace function public.org_invite_accept_v2(
  p_token text,
  p_display_name text default null,
  p_locale text default 'en'
)
returns jsonb language plpgsql set search_path = '' security definer as $$
declare
  v_caller   uuid := (select auth.uid());
  v_actor    uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_tok      public.invite_tokens%rowtype;
  v_accepter uuid;
begin
  select * into v_tok from public.invite_tokens where token = p_token for update;
  if not found then raise exception 'org_invite_accept_v2: invite not found'; end if;
  if v_tok.accepted_at is not null then raise exception 'org_invite_accept_v2: invite already accepted'; end if;
  if v_tok.revoked_at is not null then raise exception 'org_invite_accept_v2: invite revoked'; end if;
  if v_tok.expires_at < now() then raise exception 'org_invite_accept_v2: invite expired'; end if;
  if v_caller is not null and v_actor is null then
    update public.people set auth_user_id = v_caller where id = v_tok.person_id;
    v_actor := v_tok.person_id;
  end if;
  v_accepter := coalesce(v_actor, v_tok.person_id);
  update public.invite_tokens set accepted_at = now(), accepted_by = v_accepter where id = v_tok.id;
  update public.memberships set status = 'active', updated_at = now() where id = v_tok.membership_id;
  if p_display_name is not null and length(trim(p_display_name)) > 0 then
    update public.people set full_name = trim(p_display_name) where id = v_tok.person_id;
  end if;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_tok.org_id, v_accepter, 'org.invite_accepted', 'invite_tokens', v_tok.id,
      jsonb_build_object('membership_id', v_tok.membership_id, 'locale_at_accept', p_locale));
  return jsonb_build_object(
    'membership_id', v_tok.membership_id,
    'person_id', v_tok.person_id,
    'org_id', v_tok.org_id,
    'locale', p_locale
  );
end;
$$;
revoke execute on function public.org_invite_accept_v2(text, text, text) from public;
grant  execute on function public.org_invite_accept_v2(text, text, text) to authenticated, anon, service_role;
