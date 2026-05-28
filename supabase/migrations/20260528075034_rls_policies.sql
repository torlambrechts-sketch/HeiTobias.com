-- rls_policies — permissive policies on every domain table.
--
-- Every policy uses the security helpers (is_self, has_permission, in_scope,
-- consent_active) and is scoped `to authenticated` so anon callers never match
-- any policy (effective deny).
--
-- Tables with NO write policy = service_role only for that operation. This is
-- the right default for INSERT/DELETE on most tables — application code drives
-- those via RPCs or admin flows. UPDATE is opened to specific permissions where
-- users need to modify rows directly.
--
-- audit_log has only a SELECT policy; writes happen via _audit_row trigger
-- and audit_log_event RPC (both SECURITY DEFINER), and UPDATE/DELETE are blocked
-- by the immutability triggers.

-- =====================================================================
-- organizations
-- =====================================================================
create policy organizations_select on public.organizations
  for select to authenticated
  using (
    exists (
      select 1
      from public.memberships m
      join public.people p on p.id = m.person_id
      where m.org_id        = organizations.id
        and m.status        = 'active'
        and p.auth_user_id  = (select auth.uid())
    )
  );

create policy organizations_update on public.organizations
  for update to authenticated
  using      ( public.has_permission(id, 'org.manage_all') )
  with check ( public.has_permission(id, 'org.manage_all') );

-- =====================================================================
-- people  (no org_id; visibility via memberships overlap + permission)
-- =====================================================================
create policy people_select on public.people
  for select to authenticated
  using (
    public.is_self(id)
    or exists (
      select 1
      from public.memberships m
      where m.person_id = people.id
        and public.has_permission(m.org_id, 'person.read')
    )
  );

create policy people_update on public.people
  for update to authenticated
  using (
    public.is_self(id)
    or exists (
      select 1
      from public.memberships m
      where m.person_id = people.id
        and public.has_permission(m.org_id, 'person.write')
    )
  )
  with check (
    public.is_self(id)
    or exists (
      select 1
      from public.memberships m
      where m.person_id = people.id
        and public.has_permission(m.org_id, 'person.write')
    )
  );

-- =====================================================================
-- memberships
-- =====================================================================
create policy memberships_select on public.memberships
  for select to authenticated
  using (
    public.is_self(person_id)
    or public.has_permission(org_id, 'org.read')
  );

create policy memberships_insert on public.memberships
  for insert to authenticated
  with check ( public.has_permission(org_id, 'person.write') );

create policy memberships_update on public.memberships
  for update to authenticated
  using      ( public.has_permission(org_id, 'person.write') )
  with check ( public.has_permission(org_id, 'person.write') );

create policy memberships_delete on public.memberships
  for delete to authenticated
  using ( public.has_permission(org_id, 'org.manage_all') );

-- =====================================================================
-- departments
-- =====================================================================
create policy departments_select on public.departments
  for select to authenticated using ( public.has_permission(org_id, 'org.read') );

create policy departments_insert on public.departments
  for insert to authenticated with check ( public.has_permission(org_id, 'org.manage_all') );

create policy departments_update on public.departments
  for update to authenticated
  using      ( public.has_permission(org_id, 'org.manage_all') )
  with check ( public.has_permission(org_id, 'org.manage_all') );

create policy departments_delete on public.departments
  for delete to authenticated using ( public.has_permission(org_id, 'org.manage_all') );

-- =====================================================================
-- teams
-- =====================================================================
create policy teams_select on public.teams
  for select to authenticated using ( public.has_permission(org_id, 'org.read') );

create policy teams_insert on public.teams
  for insert to authenticated with check ( public.has_permission(org_id, 'org.manage_all') );

create policy teams_update on public.teams
  for update to authenticated
  using      ( public.has_permission(org_id, 'org.manage_all') )
  with check ( public.has_permission(org_id, 'org.manage_all') );

create policy teams_delete on public.teams
  for delete to authenticated using ( public.has_permission(org_id, 'org.manage_all') );

-- =====================================================================
-- team_members
-- =====================================================================
create policy team_members_select on public.team_members
  for select to authenticated using ( public.has_permission(org_id, 'org.read') );

create policy team_members_insert on public.team_members
  for insert to authenticated with check ( public.has_permission(org_id, 'person.write') );

create policy team_members_update on public.team_members
  for update to authenticated
  using      ( public.has_permission(org_id, 'person.write') )
  with check ( public.has_permission(org_id, 'person.write') );

create policy team_members_delete on public.team_members
  for delete to authenticated using ( public.has_permission(org_id, 'person.write') );

-- =====================================================================
-- roles_catalog  (globals + org instances)
-- =====================================================================
create policy roles_catalog_select on public.roles_catalog
  for select to authenticated
  using (
    org_id is null                                       -- global template, any authenticated
    or public.has_permission(org_id, 'role.read')
  );

create policy roles_catalog_insert on public.roles_catalog
  for insert to authenticated
  with check (
    org_id is not null
    and public.has_permission(org_id, 'role.create')
  );

create policy roles_catalog_update on public.roles_catalog
  for update to authenticated
  using      ( org_id is not null and public.has_permission(org_id, 'role.create') )
  with check ( org_id is not null and public.has_permission(org_id, 'role.create') );

-- =====================================================================
-- positions
-- =====================================================================
create policy positions_select on public.positions
  for select to authenticated
  using (
    public.has_permission(org_id, 'position.read')
    and (
      person_id is null                                  -- open positions: visible with permission
      or public.in_scope(org_id, person_id)
    )
  );

create policy positions_insert on public.positions
  for insert to authenticated
  with check ( public.has_permission(org_id, 'position.write') );

create policy positions_update on public.positions
  for update to authenticated
  using      ( public.has_permission(org_id, 'position.write') )
  with check ( public.has_permission(org_id, 'position.write') );

create policy positions_delete on public.positions
  for delete to authenticated
  using ( public.has_permission(org_id, 'position.write') );

-- =====================================================================
-- profiles  (CONSENT-GATED — the most sensitive read path)
-- =====================================================================
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'profile.read')
      and public.in_scope(org_id, person_id)
      and public.consent_active(consent_id)
    )
  );

create policy profiles_insert on public.profiles
  for insert to authenticated
  with check ( public.has_permission(org_id, 'profile.write') );

create policy profiles_update on public.profiles
  for update to authenticated
  using      ( public.has_permission(org_id, 'profile.write') )
  with check ( public.has_permission(org_id, 'profile.write') );

-- =====================================================================
-- assessments
-- =====================================================================
create policy assessments_select on public.assessments
  for select to authenticated
  using (
    public.is_self(person_id)
    or (
      public.has_permission(org_id, 'profile.read')
      and public.in_scope(org_id, person_id)
    )
  );

create policy assessments_insert on public.assessments
  for insert to authenticated
  with check ( public.has_permission(org_id, 'profile.write') );

create policy assessments_update on public.assessments
  for update to authenticated
  using      ( public.has_permission(org_id, 'profile.write') )
  with check ( public.has_permission(org_id, 'profile.write') );

-- =====================================================================
-- requisitions
-- =====================================================================
create policy requisitions_select on public.requisitions
  for select to authenticated
  using (
    public.has_permission(org_id, 'requisition.read')
    or (collaborating_org_id is not null
        and public.has_permission(collaborating_org_id, 'requisition.read'))
  );

create policy requisitions_insert on public.requisitions
  for insert to authenticated
  with check ( public.has_permission(org_id, 'requisition.write') );

create policy requisitions_update on public.requisitions
  for update to authenticated
  using      ( public.has_permission(org_id, 'requisition.write') )
  with check ( public.has_permission(org_id, 'requisition.write') );

-- =====================================================================
-- requisition_candidates
-- =====================================================================
create policy requisition_candidates_select on public.requisition_candidates
  for select to authenticated
  using ( public.has_permission(org_id, 'requisition.read') );

create policy requisition_candidates_insert on public.requisition_candidates
  for insert to authenticated
  with check ( public.has_permission(org_id, 'requisition.write') );

create policy requisition_candidates_update on public.requisition_candidates
  for update to authenticated
  using      ( public.has_permission(org_id, 'requisition.write') )
  with check ( public.has_permission(org_id, 'requisition.write') );

create policy requisition_candidates_delete on public.requisition_candidates
  for delete to authenticated
  using ( public.has_permission(org_id, 'requisition.write') );

-- =====================================================================
-- placements  (cross-org bridge — SELECT both sides)
-- =====================================================================
create policy placements_select on public.placements
  for select to authenticated
  using (
    public.has_permission(from_org_id, 'placement.transfer')
    or public.has_permission(from_org_id, 'org.read')
    or public.has_permission(to_org_id,   'org.read')
  );

create policy placements_insert on public.placements
  for insert to authenticated
  with check ( public.has_permission(from_org_id, 'placement.transfer') );

create policy placements_update on public.placements
  for update to authenticated
  using      ( public.has_permission(from_org_id, 'placement.transfer') )
  with check ( public.has_permission(from_org_id, 'placement.transfer') );

-- =====================================================================
-- consent_grants  (data subject owns; org with consent.read sees grants directed to them)
-- =====================================================================
create policy consent_grants_select on public.consent_grants
  for select to authenticated
  using (
    public.is_self(person_id)
    or public.has_permission(granted_to_org_id, 'consent.read')
  );

create policy consent_grants_insert on public.consent_grants
  for insert to authenticated
  with check (
    public.is_self(person_id)
    or public.has_permission(granted_to_org_id, 'consent.write')
  );

create policy consent_grants_update on public.consent_grants
  for update to authenticated
  using (
    public.is_self(person_id)
    or public.has_permission(granted_to_org_id, 'consent.write')
  )
  with check (
    public.is_self(person_id)
    or public.has_permission(granted_to_org_id, 'consent.write')
  );

-- =====================================================================
-- audit_log  (SELECT only — writes via triggers + RPC; UPDATE/DELETE blocked by trigger)
-- =====================================================================
create policy audit_log_select on public.audit_log
  for select to authenticated
  using (
    org_id is not null and public.has_permission(org_id, 'audit.read')
    or actor_person_id is not null and public.is_self(actor_person_id)
  );

-- =====================================================================
-- RBAC catalogs (rbac_permissions / rbac_roles / rbac_role_permissions)
-- Read-only to any authenticated user.
-- =====================================================================
create policy rbac_permissions_select on public.rbac_permissions
  for select to authenticated using (true);

create policy rbac_roles_select on public.rbac_roles
  for select to authenticated using (true);

create policy rbac_role_permissions_select on public.rbac_role_permissions
  for select to authenticated using (true);

-- =====================================================================
-- membership_roles
-- =====================================================================
create policy membership_roles_select on public.membership_roles
  for select to authenticated
  using (
    exists (
      select 1 from public.memberships m
      where m.id = membership_roles.membership_id
        and (
          public.is_self(m.person_id)
          or public.has_permission(m.org_id, 'org.read')
        )
    )
  );

create policy membership_roles_insert on public.membership_roles
  for insert to authenticated
  with check (
    exists (
      select 1 from public.memberships m
      where m.id = membership_roles.membership_id
        and public.has_permission(m.org_id, 'org.manage_all')
    )
  );

create policy membership_roles_delete on public.membership_roles
  for delete to authenticated
  using (
    exists (
      select 1 from public.memberships m
      where m.id = membership_roles.membership_id
        and public.has_permission(m.org_id, 'org.manage_all')
    )
  );

-- =====================================================================
-- modules / component_registry  (global catalogs; read-only to authenticated)
-- =====================================================================
create policy modules_select on public.modules
  for select to authenticated using (true);

create policy component_registry_select on public.component_registry
  for select to authenticated using (true);

-- =====================================================================
-- org_modules  (per-org config)
-- =====================================================================
create policy org_modules_select on public.org_modules
  for select to authenticated
  using ( public.has_permission(org_id, 'org.read') );

create policy org_modules_insert on public.org_modules
  for insert to authenticated
  with check ( public.has_permission(org_id, 'org.manage_all') );

create policy org_modules_update on public.org_modules
  for update to authenticated
  using      ( public.has_permission(org_id, 'org.manage_all') )
  with check ( public.has_permission(org_id, 'org.manage_all') );

create policy org_modules_delete on public.org_modules
  for delete to authenticated
  using ( public.has_permission(org_id, 'org.manage_all') );

-- =====================================================================
-- templates  (globals visible to authenticated; org-scoped via org.read)
-- =====================================================================
create policy templates_select on public.templates
  for select to authenticated
  using (
    org_id is null                                       -- global
    or public.has_permission(org_id, 'org.read')
  );

create policy templates_insert on public.templates
  for insert to authenticated
  with check (
    org_id is not null
    and public.has_permission(org_id, 'org.manage_all')
  );

create policy templates_update on public.templates
  for update to authenticated
  using      ( org_id is not null and public.has_permission(org_id, 'org.manage_all') )
  with check ( org_id is not null and public.has_permission(org_id, 'org.manage_all') );

create policy templates_delete on public.templates
  for delete to authenticated
  using ( org_id is not null and public.has_permission(org_id, 'org.manage_all') );
