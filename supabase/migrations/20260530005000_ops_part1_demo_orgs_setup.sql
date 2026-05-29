-- ITEM 6: seeded demo scenario foundations — is_demo_data column on
-- principal tables, two demo orgs (agency + employer), demo people +
-- memberships at differentiated rbac_roles. Roles, candidates, placed
-- employees, and Team Definition runs land in 20260530005010 + 5020.
--
-- Demo discipline:
--   * Every demo row carries is_demo_data = true (verified by test 38)
--   * A persistent banner renders in the UI when in a demo org
--   * No fabricated science values — all H-stub fields remain dev_stub
--   * The agency + employer pair lets the cross-org placement demo work
--   * Two demo orgs use distinct accent colors to make org switch obvious

alter table public.organizations          add column if not exists is_demo_data boolean not null default false;
alter table public.people                 add column if not exists is_demo_data boolean not null default false;
alter table public.memberships            add column if not exists is_demo_data boolean not null default false;
alter table public.roles_catalog          add column if not exists is_demo_data boolean not null default false;
alter table public.requisitions           add column if not exists is_demo_data boolean not null default false;
alter table public.requisition_candidates add column if not exists is_demo_data boolean not null default false;
alter table public.team_definition_runs   add column if not exists is_demo_data boolean not null default false;

insert into public.organizations (id, name, type, country, locale_default, data_region, status, settings_json, is_demo_data)
values ('aa000000-0000-0000-0000-000000000001', 'Lindqvist Talent Partners AS', 'agency', 'SE', 'sv-SE', 'eu', 'active',
  jsonb_build_object('accent_color','#5b3f8a','logo_url','','legal_name','Lindqvist Talent Partners Aktiebolag'), true)
on conflict (id) do update set is_demo_data = true, name = excluded.name;

insert into public.organizations (id, name, type, country, locale_default, data_region, status, settings_json, is_demo_data)
values ('aa000000-0000-0000-0000-000000000002', 'Holst Engineering AS', 'employer', 'NO', 'nb-NO', 'eu', 'active',
  jsonb_build_object('accent_color','#2d6b53','logo_url','','legal_name','Holst Engineering Aksjeselskap'), true)
on conflict (id) do update set is_demo_data = true, name = excluded.name;

insert into public.people (id, full_name, primary_email, is_demo_data) values
  ('bb000000-0000-0000-0000-000000000001','Sara Lindqvist',    'sara.lindqvist@demo-lindqvist.test',     true),
  ('bb000000-0000-0000-0000-000000000002','Anders Karlsson',   'anders.karlsson@demo-lindqvist.test',    true),
  ('bb000000-0000-0000-0000-000000000003','Mette Olsen',       'mette.olsen@demo-lindqvist.test',        true),
  ('bb000000-0000-0000-0000-000000000004','Henrik Larsen',     'henrik.larsen@demo-lindqvist.test',      true),
  ('bb000000-0000-0000-0000-000000000010','Ingrid Holst',      'ingrid.holst@demo-holst.test',           true),
  ('bb000000-0000-0000-0000-000000000011','Magnus Berg',       'magnus.berg@demo-holst.test',            true),
  ('bb000000-0000-0000-0000-000000000012','Astrid Nilsen',     'astrid.nilsen@demo-holst.test',          true),
  ('bb000000-0000-0000-0000-000000000013','Kjell Anvik',       'kjell.anvik@demo-holst.test',            true),
  ('bb000000-0000-0000-0000-000000000020','Petter Solberg',    'petter.solberg@demo-candidate.test',     true),
  ('bb000000-0000-0000-0000-000000000021','Linnea Mård',       'linnea.mard@demo-candidate.test',        true),
  ('bb000000-0000-0000-0000-000000000022','Emil Hovland',      'emil.hovland@demo-candidate.test',       true),
  ('bb000000-0000-0000-0000-000000000023','Solveig Aas',       'solveig.aas@demo-candidate.test',        true),
  ('bb000000-0000-0000-0000-000000000030','Tobias Engan',      'tobias.engan@demo-holst.test',           true),
  ('bb000000-0000-0000-0000-000000000031','Maria Lindqvist',   'maria.lindqvist@demo-holst.test',        true)
on conflict (id) do update set is_demo_data = true, full_name = excluded.full_name;

insert into public.memberships (id, org_id, person_id, status, is_demo_data) values
  ('cc000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000001','active',  true),
  ('cc000000-0000-0000-0000-000000000002','aa000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000002','active',  true),
  ('cc000000-0000-0000-0000-000000000003','aa000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000003','active',  true),
  ('cc000000-0000-0000-0000-000000000004','aa000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000004','invited', true),
  ('cc000000-0000-0000-0000-000000000010','aa000000-0000-0000-0000-000000000002','bb000000-0000-0000-0000-000000000010','active',  true),
  ('cc000000-0000-0000-0000-000000000011','aa000000-0000-0000-0000-000000000002','bb000000-0000-0000-0000-000000000011','active',  true),
  ('cc000000-0000-0000-0000-000000000012','aa000000-0000-0000-0000-000000000002','bb000000-0000-0000-0000-000000000012','active',  true),
  ('cc000000-0000-0000-0000-000000000013','aa000000-0000-0000-0000-000000000002','bb000000-0000-0000-0000-000000000013','active',  true),
  ('cc000000-0000-0000-0000-000000000030','aa000000-0000-0000-0000-000000000002','bb000000-0000-0000-0000-000000000030','active',  true),
  ('cc000000-0000-0000-0000-000000000031','aa000000-0000-0000-0000-000000000002','bb000000-0000-0000-0000-000000000031','active',  true)
on conflict (id) do update set is_demo_data = true, status = excluded.status;

do $$
declare
  v_recruiter uuid; v_org_admin uuid; v_hiring_mgr uuid; v_people_ops uuid; v_employee uuid;
begin
  select id into v_recruiter  from public.rbac_roles where key='recruiter'        and org_id is null;
  select id into v_org_admin  from public.rbac_roles where key='org_admin'        and org_id is null;
  select id into v_hiring_mgr from public.rbac_roles where key='hiring_manager'   and org_id is null;
  select id into v_people_ops from public.rbac_roles where key='people_ops_admin' and org_id is null;
  select id into v_employee   from public.rbac_roles where key='employee'         and org_id is null;
  insert into public.membership_roles (membership_id, rbac_role_id) values
    ('cc000000-0000-0000-0000-000000000001', v_org_admin),
    ('cc000000-0000-0000-0000-000000000002', v_recruiter),
    ('cc000000-0000-0000-0000-000000000003', v_recruiter),
    ('cc000000-0000-0000-0000-000000000004', v_recruiter)
  on conflict do nothing;
  insert into public.membership_roles (membership_id, rbac_role_id) values
    ('cc000000-0000-0000-0000-000000000010', v_org_admin),
    ('cc000000-0000-0000-0000-000000000011', v_hiring_mgr),
    ('cc000000-0000-0000-0000-000000000012', v_hiring_mgr),
    ('cc000000-0000-0000-0000-000000000013', v_people_ops),
    ('cc000000-0000-0000-0000-000000000030', v_employee),
    ('cc000000-0000-0000-0000-000000000031', v_employee)
  on conflict do nothing;
end$$;
