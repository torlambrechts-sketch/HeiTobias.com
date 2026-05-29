-- ITEM 6 continued: demo roles + requisition + 4 candidates at
-- differentiated pipeline stages + one signed-off team-def run.
-- All rows carry is_demo_data = true.
--
-- Note: pre-populating Team Definition evaluator/evaluation rows would
-- be fragile (signatures across runs). The demo value is that a user
-- can RUN the live team-def flow on top of this seed.

insert into public.roles_catalog (id, org_id, title, family, is_template, template_source_id, version, status, definition_json, is_demo_data)
select 'dd000000-0000-0000-0000-000000000001'::uuid,
       'aa000000-0000-0000-0000-000000000001'::uuid,
       'Senior Backend Engineer (demo)',
       'engineering', false,
       'ea3ded9e-5ec4-4c40-ac79-fc3eba0a46a3'::uuid, 1, 'active',
       definition_json, true
from public.roles_catalog where id = 'ea3ded9e-5ec4-4c40-ac79-fc3eba0a46a3'
on conflict (id) do nothing;

insert into public.roles_catalog (id, org_id, title, family, is_template, template_source_id, version, status, definition_json, is_demo_data)
select 'dd000000-0000-0000-0000-000000000002'::uuid,
       'aa000000-0000-0000-0000-000000000002'::uuid,
       'Senior Backend Engineer',
       'engineering', false,
       'ea3ded9e-5ec4-4c40-ac79-fc3eba0a46a3'::uuid, 1, 'active',
       definition_json, true
from public.roles_catalog where id = 'ea3ded9e-5ec4-4c40-ac79-fc3eba0a46a3'
on conflict (id) do nothing;

insert into public.requisitions (id, org_id, role_id, status, created_by, is_demo_data)
values ('ee000000-0000-0000-0000-000000000001',
        'aa000000-0000-0000-0000-000000000001',
        'dd000000-0000-0000-0000-000000000001',
        'open',
        'bb000000-0000-0000-0000-000000000002',
        true)
on conflict (id) do update set is_demo_data = true;

insert into public.requisition_candidates (id, org_id, requisition_id, person_id, stage, is_demo_data) values
  ('ee100000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','ee000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000020','sourced',   true),
  ('ee100000-0000-0000-0000-000000000002','aa000000-0000-0000-0000-000000000001','ee000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000021','screening', true),
  ('ee100000-0000-0000-0000-000000000003','aa000000-0000-0000-0000-000000000001','ee000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000022','interview', true),
  ('ee100000-0000-0000-0000-000000000004','aa000000-0000-0000-0000-000000000001','ee000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000023','placed',    true)
on conflict (id) do update set is_demo_data = true, stage = excluded.stage;

insert into public.team_definition_runs (id, org_id, role_family, role_template_id, purpose, owner_user_id,
                                          deadline_at, stage, starts_at, completed_at, target_role_version_id, is_demo_data)
values ('ff000000-0000-0000-0000-000000000001',
        'aa000000-0000-0000-0000-000000000001',
        'engineering',
        'ea3ded9e-5ec4-4c40-ac79-fc3eba0a46a3',
        'initial_definition',
        'bb000000-0000-0000-0000-000000000001',
        now() - interval '2 weeks',
        'signed_off',
        now() - interval '5 weeks',
        now() - interval '3 weeks',
        'dd000000-0000-0000-0000-000000000001',
        true)
on conflict (id) do update set is_demo_data = true, stage = excluded.stage;
