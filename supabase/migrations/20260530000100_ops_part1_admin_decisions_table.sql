-- Operations Layer Part 1 — admin_decisions table + view extension.
--
-- decision_artefacts is a VIEW unioning hiring_decisions +
-- lifecycle_decisions. Admin actions (rbac_role_change, user_deactivation,
-- module_toggle, org_settings_change, …) don't fit either source — they
-- need their own table. This migration:
--   * adds admin_decisions with the same shape constraints
--   * extends the decision_artefacts view to UNION the new source
--   * rewrites the three admin RPCs from 20260530000000 to INSERT
--     into admin_decisions (the prior version tried to INSERT into the
--     view directly, which fails for UNION views)
-- The RLS on admin_decisions is select-only for org admins; inserts
-- come exclusively from SECURITY DEFINER RPCs.

create table public.admin_decisions (
  id                          uuid primary key default extensions.gen_random_uuid(),
  org_id                      uuid not null references public.organizations(id),
  person_id                   uuid references public.people(id),
  kind                        text not null,
  decided_by                  uuid references public.people(id),
  decided_at                  timestamptz not null default now(),
  rationale                   text not null,
  evidence_ref                text,
  overrode_recommendation     boolean not null default false,
  recommendation_summary      text,
  target_entity_type          text,
  target_entity_id            uuid,
  created_at                  timestamptz not null default now(),
  constraint chk_admin_decisions_rationale_min check (length(rationale) >= 20)
);
create index admin_decisions_org_idx     on public.admin_decisions (org_id);
create index admin_decisions_person_idx  on public.admin_decisions (person_id);
create index admin_decisions_kind_idx    on public.admin_decisions (org_id, kind);
create trigger trg_audit_admin_decisions after insert or update or delete on public.admin_decisions for each row execute function public._audit_row();
alter table public.admin_decisions enable row level security;
alter table public.admin_decisions force  row level security;
create policy admin_decisions_select on public.admin_decisions for select to authenticated using (
  public.has_permission(org_id, 'org.manage_all')
);

create or replace view public.decision_artefacts as
  select hd.id, hd.org_id, rc.person_id, hd.decision::text as decision_type,
    hd.decided_by, hd.decided_at, hd.rationale as justification_text,
    array_remove(array[(hd.fit_result_id)::text], null::text) as evidence_refs,
    hd.overrode_recommendation as human_override, hd.recommendation_summary as override_justification,
    'hiring_decisions'::text as source_table, hd.created_at
  from public.hiring_decisions hd
  left join public.requisition_candidates rc on rc.id = hd.requisition_candidate_id
union all
  select ld.id, ld.org_id, ld.person_id, ld.kind::text as decision_type,
    ld.decided_by, ld.decided_at, ld.rationale as justification_text,
    array_remove(array[(ld.refit_evaluation_id)::text, (ld.guidance_item_id)::text], null::text) as evidence_refs,
    ld.overrode_recommendation as human_override, ld.recommendation_summary as override_justification,
    'lifecycle_decisions'::text as source_table, ld.created_at
  from public.lifecycle_decisions ld
union all
  select ad.id, ad.org_id, ad.person_id, ad.kind, ad.decided_by, ad.decided_at, ad.rationale as justification_text,
    array_remove(array[ad.evidence_ref], null::text) as evidence_refs,
    ad.overrode_recommendation as human_override, ad.recommendation_summary as override_justification,
    'admin_decisions'::text as source_table, ad.created_at
  from public.admin_decisions ad;
grant select on public.decision_artefacts to authenticated, service_role;

-- Rewrite the three admin RPCs to use admin_decisions.
create or replace function public.org_change_role(
  p_membership_id uuid,
  p_new_rbac_role_key text,
  p_rationale text default null
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_org    uuid;
  v_pid    uuid;
  v_role   uuid;
  v_old    text;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'org_change_role: rationale >=20 chars required (audit-grade attribution)';
  end if;
  select org_id, person_id into v_org, v_pid from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_change_role: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_change_role: requires org.manage_all';
  end if;
  select id into v_role from public.rbac_roles where org_id is null and key = p_new_rbac_role_key;
  if v_role is null then raise exception 'org_change_role: unknown rbac role key %', p_new_rbac_role_key; end if;
  select string_agg(r.key, ',') into v_old
    from public.membership_roles mr join public.rbac_roles r on r.id = mr.rbac_role_id
    where mr.membership_id = p_membership_id;
  delete from public.membership_roles where membership_id = p_membership_id;
  insert into public.membership_roles (membership_id, rbac_role_id) values (p_membership_id, v_role);
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, before_json, after_json)
    values (v_org, v_actor, 'org.role_changed', 'memberships', p_membership_id,
      jsonb_build_object('old_role', v_old),
      jsonb_build_object('new_role', p_new_rbac_role_key, 'rationale_excerpt', left(p_rationale, 200)));
  insert into public.admin_decisions (org_id, person_id, kind, decided_by, rationale, target_entity_type, target_entity_id, overrode_recommendation)
    values (v_org, v_pid, 'rbac_role_change', v_actor, p_rationale, 'memberships', p_membership_id, true);
  return p_membership_id;
end;
$$;

create or replace function public.org_deactivate_user(
  p_membership_id uuid,
  p_rationale text default null
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_org    uuid;
  v_pid    uuid;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'org_deactivate_user: rationale >=20 chars required';
  end if;
  select org_id, person_id into v_org, v_pid from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_deactivate_user: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_deactivate_user: requires org.manage_all';
  end if;
  update public.memberships set status = 'suspended', updated_at = now() where id = p_membership_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.user_deactivated', 'memberships', p_membership_id,
      jsonb_build_object('rationale_excerpt', left(p_rationale, 200)));
  insert into public.admin_decisions (org_id, person_id, kind, decided_by, rationale, target_entity_type, target_entity_id, overrode_recommendation)
    values (v_org, v_pid, 'user_deactivation', v_actor, p_rationale, 'memberships', p_membership_id, true);
  return p_membership_id;
end;
$$;

create or replace function public.org_reactivate_user(
  p_membership_id uuid,
  p_rationale text
)
returns uuid language plpgsql set search_path = '' security definer as $$
declare
  v_caller uuid := (select auth.uid());
  v_actor  uuid := (select id from public.people where auth_user_id = v_caller limit 1);
  v_org    uuid;
  v_pid    uuid;
begin
  if p_rationale is null or length(p_rationale) < 20 then
    raise exception 'org_reactivate_user: rationale >=20 chars required';
  end if;
  select org_id, person_id into v_org, v_pid from public.memberships where id = p_membership_id;
  if v_org is null then raise exception 'org_reactivate_user: membership not found'; end if;
  if v_caller is null or not public.has_permission(v_org, 'org.manage_all') then
    raise exception 'org_reactivate_user: requires org.manage_all';
  end if;
  update public.memberships set status = 'active', updated_at = now() where id = p_membership_id;
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_org, v_actor, 'org.user_reactivated', 'memberships', p_membership_id,
      jsonb_build_object('rationale_excerpt', left(p_rationale, 200)));
  insert into public.admin_decisions (org_id, person_id, kind, decided_by, rationale, target_entity_type, target_entity_id, overrode_recommendation)
    values (v_org, v_pid, 'user_reactivation', v_actor, p_rationale, 'memberships', p_membership_id, true);
  return p_membership_id;
end;
$$;
