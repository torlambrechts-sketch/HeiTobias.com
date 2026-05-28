-- rbac_seed — Phase 0 system RBAC: 6 roles, 16 permissions, baseline mappings.
--
-- Idempotent: each insert is guarded by ON CONFLICT or a NOT EXISTS predicate.
-- A future migration can extend the catalog without rewriting these rows.

-- ---- system roles --------------------------------------------------------
insert into public.rbac_roles (org_id, key, name) values
  (null, 'org_admin',         'Org Admin'),
  (null, 'people_ops_admin',  'People Ops Admin'),
  (null, 'manager',           'Manager'),
  (null, 'recruiter',         'Recruiter'),
  (null, 'hiring_manager',    'Hiring Manager'),
  (null, 'employee',          'Employee')
on conflict do nothing;

-- ---- permissions (Phase 0 minimal set, 16 keys) --------------------------
insert into public.rbac_permissions (key, description) values
  ('org.manage_all',     'Full admin scope inside the org. Bypasses manager-chain scoping.'),
  ('org.read',           'Read basic info about the caller''s own org.'),
  ('person.read',        'Read people in scope.'),
  ('person.write',       'Create / update people in scope.'),
  ('profile.read',       'Read person profiles in scope (consent-gated).'),
  ('profile.write',      'Create / update person profiles in scope (consent-gated).'),
  ('role.read',          'Read role profiles in org.'),
  ('role.create',        'Create / version role profiles in org.'),
  ('position.read',      'Read positions in scope.'),
  ('position.write',     'Create / update positions in scope.'),
  ('requisition.read',   'Read requisitions in org.'),
  ('requisition.write',  'Create / update requisitions in org.'),
  ('placement.transfer', 'Execute the consent-gated cross-org placement hand-off.'),
  ('consent.read',       'Read consent grants relevant to scope.'),
  ('consent.write',      'Issue / revoke consent grants on behalf of the data subject.'),
  ('audit.read',         'Read audit_log entries scoped to the caller''s org.')
on conflict (key) do nothing;

-- ---- mappings ------------------------------------------------------------

-- org_admin: every permission.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id
from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null and r.key = 'org_admin'
on conflict do nothing;

-- people_ops_admin: everything except placement.transfer.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id
from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null and r.key = 'people_ops_admin'
  and p.key in (
    'org.manage_all','org.read',
    'person.read','person.write',
    'profile.read','profile.write',
    'role.read','role.create',
    'position.read','position.write',
    'requisition.read','requisition.write',
    'consent.read','consent.write',
    'audit.read'
  )
on conflict do nothing;

-- manager: read in scope; person.write inside own team (RLS narrows scope further).
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id
from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null and r.key = 'manager'
  and p.key in (
    'org.read',
    'person.read','person.write',
    'profile.read',
    'role.read',
    'position.read'
  )
on conflict do nothing;

-- recruiter (agency-side): drives requisitions and the hand-off.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id
from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null and r.key = 'recruiter'
  and p.key in (
    'org.read',
    'person.read','person.write',
    'profile.read','profile.write',
    'role.read',
    'requisition.read','requisition.write',
    'placement.transfer',
    'consent.read','consent.write'
  )
on conflict do nothing;

-- hiring_manager (employer-side): owns own requisitions.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id
from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null and r.key = 'hiring_manager'
  and p.key in (
    'org.read',
    'person.read',
    'profile.read',
    'role.read',
    'position.read',
    'requisition.read','requisition.write'
  )
on conflict do nothing;

-- employee: see own org metadata and own consent dashboard.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id
from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null and r.key = 'employee'
  and p.key in (
    'org.read',
    'consent.read'
  )
on conflict do nothing;
