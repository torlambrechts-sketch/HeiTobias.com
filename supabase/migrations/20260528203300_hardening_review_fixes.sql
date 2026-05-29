-- hardening_review_fixes — senior-review pass on the §A–§E work:
--
-- 1. org_invite_user regressed an ACTIVE user back to 'invited' when an
--    admin re-invited them. Fix: only set 'invited' when no membership
--    exists or the existing one is 'removed'. Active/suspended/already-
--    invited are left untouched (idempotent role-attach).
-- 2. _validate_role_trait_targets RAISE used '%s' instead of '%' — PL/pgSQL
--    raise uses '%' as the placeholder, '%s' would emit a literal "s"
--    glued to the substituted value (cosmetic but ugly). Replaced.
-- 3. Composite hot-path indexes for admin_overview:
--      audit_log              (org_id, at desc)
--      data_export_requests   (org_id, requested_at desc)

create or replace function public.org_invite_user(
  p_org_id uuid, p_email text, p_rbac_role_key text, p_full_name text default null
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare v_caller uuid := (select auth.uid()); v_actor uuid := (select id from public.people where auth_user_id = v_caller limit 1);
        v_person uuid; v_membership uuid; v_role uuid; v_existing_status public.membership_status;
begin
  if v_caller is null or not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'org_invite_user: requires org.manage_all';
  end if;
  if p_email is null or position('@' in p_email) < 2 then
    raise exception 'org_invite_user: invalid email';
  end if;
  select id into v_role from public.rbac_roles where org_id is null and key = p_rbac_role_key;
  if v_role is null then raise exception 'org_invite_user: unknown rbac role key %', p_rbac_role_key; end if;
  select id into v_person from public.people where primary_email = lower(p_email) limit 1;
  if v_person is null then
    insert into public.people (full_name, primary_email) values (coalesce(p_full_name, split_part(p_email,'@',1)), lower(p_email)) returning id into v_person;
  end if;
  select id, status into v_membership, v_existing_status from public.memberships where org_id = p_org_id and person_id = v_person limit 1;
  if v_membership is null then
    insert into public.memberships (org_id, person_id, status) values (p_org_id, v_person, 'invited') returning id into v_membership;
  elsif v_existing_status = 'removed' then
    update public.memberships set status = 'invited' where id = v_membership;
  end if;
  insert into public.membership_roles (membership_id, rbac_role_id) values (v_membership, v_role) on conflict do nothing;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (p_org_id, v_actor, 'org.user_invited', 'memberships', v_membership,
      jsonb_build_object('email', p_email, 'role', p_rbac_role_key, 'person_id', v_person,
                         'prior_status', v_existing_status, 'created_new_membership', (v_existing_status is null)));
  return v_membership;
end;
$$;

create or replace function public._validate_role_trait_targets() returns trigger
language plpgsql set search_path = '' as $$
declare target jsonb;
begin
  if new.definition_json -> 'trait_targets' is null then return new; end if;
  for target in select * from jsonb_array_elements(new.definition_json -> 'trait_targets') loop
    if target ? 'direction' then
      if (target ->> 'direction') = 'optimum' then
        if not (target ? 'centre' and target ? 'lower' and target ? 'upper') then
          raise exception 'trait_target with direction=optimum requires centre+lower+upper band (SCIENCE-SPEC §2 — Le 2011, Pierce & Aguinis 2013): %', target;
        end if;
      end if;
      if (target ->> 'direction') in ('maximum_threshold','minimum_threshold') then
        if not (target ? 'justification') or length(coalesce(target ->> 'justification', '')) < 10 then
          raise exception 'trait_target with direction=% requires non-empty justification (>=10 chars; SCIENCE-SPEC §2): % %', target ->> 'direction', '— item:', target;
        end if;
      end if;
    end if;
  end loop;
  return new;
end;
$$;

create index if not exists audit_log_org_at_idx on public.audit_log (org_id, at desc);
create index if not exists data_export_requests_org_requested_idx
  on public.data_export_requests (org_id, requested_at desc);
