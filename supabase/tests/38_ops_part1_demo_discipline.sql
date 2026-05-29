-- 38_ops_part1_demo_discipline — demo seed labelling discipline.
-- T1   Both demo orgs are flagged is_demo_data = true
-- T2   Every demo person is flagged is_demo_data = true
-- T3   Demo memberships flagged
-- T4   Demo roles_catalog rows flagged
-- T5   Demo requisitions + candidates flagged
-- T6   No demo row anywhere has validity_status = 'validated' (the
--      load-bearing guard from CLAUDE.md §5 — demo must never look
--      like validated science)

begin;
select plan(6);

select is(
  (select count(*)::int from public.organizations
   where id in ('aa000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000002')
     and is_demo_data = true),
  2, '[T1] both demo orgs flagged is_demo_data');

select ok(
  (select bool_and(is_demo_data) from public.people where primary_email like '%demo-%'),
  '[T2] every demo person carries is_demo_data = true');

select is(
  (select count(*)::int from public.memberships m
   where m.org_id in ('aa000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000002')
     and m.is_demo_data = true),
  10, '[T3] 10 demo memberships flagged');

select is(
  (select count(*)::int from public.roles_catalog where org_id in
    ('aa000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000002')
     and is_demo_data = true),
  2, '[T4] 2 demo role instances flagged');

select ok(
  (select count(*) from public.requisitions where is_demo_data) >= 1
  and (select count(*) from public.requisition_candidates where is_demo_data) >= 4,
  '[T5] demo requisition + 4 candidates flagged');

-- The CLAUDE.md §5 guard: no demo row passes for validated science.
-- Walks every table that has both is_demo_data and validity_status columns.
select ok(
  not exists (
    select 1 from public.team_definition_thresholds where validity_status = 'validated'
  )
  and not exists (
    select 1 from public.assessment_instruments where validity_status = 'validated'
  ),
  '[T6] No row carries validity_status = ''validated'' in the demo seed (CLAUDE.md §5 guard)');

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
