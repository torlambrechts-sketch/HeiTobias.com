-- atomic_rpcs — the two transactional flows that must be policy-checked and
-- atomic (PHASE0-SPEC: prefer RPCs for multi-step writes).
--
--   role_version_create(role_id, new_definition, new_authored_by)
--       → creates a new roles_catalog row with version+1 and supersedes_id pointing
--         at the input. Old row is retained.
--
--   placement_execute(requisition_id, person_id, to_org_id, consent_id)
--       → the consent-gated cross-org hand-off:
--         placements row + role snapshot + profile copy + filled position.
--
-- Both are SECURITY DEFINER, search_path = '', revoked from PUBLIC, granted to
-- authenticated + service_role. Both rely on the audit triggers from Step 4 to
-- write audit_log rows automatically.

-- =====================================================================
-- role_version_create
-- =====================================================================
create or replace function public.role_version_create(
  p_role_id         uuid,
  p_new_definition  jsonb,
  p_new_authored_by jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_old    public.roles_catalog%rowtype;
  v_new_id uuid;
  v_caller uuid := (select auth.uid());
begin
  select * into v_old from public.roles_catalog where id = p_role_id;
  if not found then
    raise exception 'role_version_create: role not found (id=%)', p_role_id;
  end if;

  if v_old.is_template then
    raise exception 'role_version_create: templates cannot be versioned via this RPC; instantiate the template first';
  end if;

  -- AuthZ when invoked from a user JWT; service role (no auth.uid()) skips.
  if v_caller is not null then
    if not public.has_permission(v_old.org_id, 'role.create') then
      raise exception 'role_version_create: caller lacks role.create in role''s org';
    end if;
  end if;

  insert into public.roles_catalog (
    org_id, title, family,
    is_template, template_source_id,
    version, status,
    definition_json, authored_by_json,
    supersedes_id
  ) values (
    v_old.org_id, v_old.title, v_old.family,
    false, v_old.template_source_id,
    v_old.version + 1, 'draft',
    p_new_definition, p_new_authored_by,
    v_old.id
  )
  returning id into v_new_id;

  return v_new_id;
end;
$$;
comment on function public.role_version_create(uuid, jsonb, jsonb) is
  'Creates a new draft version of a roles_catalog row; the old version is retained (FK restrict on supersedes_id).';

revoke execute on function public.role_version_create(uuid, jsonb, jsonb) from public;
grant  execute on function public.role_version_create(uuid, jsonb, jsonb) to authenticated, service_role;

-- =====================================================================
-- placement_execute
-- =====================================================================
create or replace function public.placement_execute(
  p_requisition_id  uuid,
  p_person_id       uuid,
  p_to_org_id       uuid,
  p_consent_id      uuid
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller        uuid := (select auth.uid());
  v_req           public.requisitions%rowtype;
  v_consent       public.consent_grants%rowtype;
  v_src_profile   public.profiles%rowtype;
  v_placement_id  uuid;
  v_role_id_to    uuid;
  v_position_id   uuid;
  v_profile_id    uuid;
  v_role_title    text;
  v_role_family   text;
  v_role_def      jsonb;
begin
  -- 1. Load the requisition.
  select * into v_req from public.requisitions where id = p_requisition_id;
  if not found then
    raise exception 'placement_execute: requisition not found (id=%)', p_requisition_id;
  end if;

  -- 2. AuthZ: placement.transfer in the requisition's org (the from_org side).
  if v_caller is not null then
    if not public.has_permission(v_req.org_id, 'placement.transfer') then
      raise exception 'placement_execute: caller lacks placement.transfer in from_org_id';
    end if;
  end if;

  -- 3. Cross-org sanity.
  if v_req.org_id = p_to_org_id then
    raise exception 'placement_execute: from_org_id and to_org_id must differ';
  end if;

  -- 4. Validate the consent grant.
  select * into v_consent from public.consent_grants where id = p_consent_id;
  if not found then
    raise exception 'placement_execute: consent grant not found (id=%)', p_consent_id;
  end if;
  if v_consent.person_id <> p_person_id then
    raise exception 'placement_execute: consent_id does not belong to p_person_id';
  end if;
  if v_consent.granted_to_org_id <> p_to_org_id then
    raise exception 'placement_execute: consent_id was not granted to p_to_org_id';
  end if;
  if v_consent.purpose <> 'profile_portability' then
    raise exception 'placement_execute: consent purpose is %, requires profile_portability', v_consent.purpose;
  end if;
  if not public.consent_active(p_consent_id) then
    raise exception 'placement_execute: consent is not active (revoked/expired/missing)';
  end if;

  -- 5. Create the placement row (status=transferred, transferred_at=now()).
  insert into public.placements (
    requisition_id, person_id, from_org_id, to_org_id,
    status, consent_id, transferred_at
  ) values (
    p_requisition_id, p_person_id, v_req.org_id, p_to_org_id,
    'transferred', p_consent_id, now()
  )
  returning id into v_placement_id;

  -- 6. Snapshot the role into the employer org. Reuse the most-recent active role
  --    with the same title if one exists; otherwise insert a new active row.
  select title, family, definition_json
    into v_role_title, v_role_family, v_role_def
    from public.roles_catalog where id = v_req.role_id;

  select id into v_role_id_to
    from public.roles_catalog
    where org_id = p_to_org_id
      and title  = v_role_title
      and status = 'active'
      and is_template = false
    order by version desc
    limit 1;

  if v_role_id_to is null then
    insert into public.roles_catalog (
      org_id, title, family, is_template, definition_json, status
    ) values (
      p_to_org_id, v_role_title, v_role_family, false, v_role_def, 'active'
    ) returning id into v_role_id_to;
  end if;

  -- 7. Copy the person's most recent profile from the agency into the employer org,
  --    bound to the same consent grant. If none exists, create an empty import row.
  select * into v_src_profile
    from public.profiles
    where person_id = p_person_id and org_id = v_req.org_id
    order by valid_from desc nulls last
    limit 1;

  if found then
    insert into public.profiles (
      org_id, person_id, source,
      traits_json, cognitive_json, values_json, derived_json,
      consent_id
    ) values (
      p_to_org_id, p_person_id, 'import',
      v_src_profile.traits_json, v_src_profile.cognitive_json,
      v_src_profile.values_json, v_src_profile.derived_json,
      p_consent_id
    ) returning id into v_profile_id;
  else
    insert into public.profiles (org_id, person_id, source, consent_id)
      values (p_to_org_id, p_person_id, 'import', p_consent_id)
      returning id into v_profile_id;
  end if;

  -- 8. Create a filled position in the employer org for this role/person.
  insert into public.positions (org_id, role_id, person_id, status, start_date)
    values (p_to_org_id, v_role_id_to, p_person_id, 'filled', current_date)
    returning id into v_position_id;

  -- _audit_row triggers fired for placements, roles_catalog (if created),
  -- profiles, positions — the full hand-off is in audit_log automatically.

  return v_placement_id;
end;
$$;
comment on function public.placement_execute(uuid, uuid, uuid, uuid) is
  'Consent-gated cross-org placement hand-off. Validates active profile_portability consent, copies role + profile, creates a filled position in the target org. Atomic.';

revoke execute on function public.placement_execute(uuid, uuid, uuid, uuid) from public;
grant  execute on function public.placement_execute(uuid, uuid, uuid, uuid) to authenticated, service_role;
