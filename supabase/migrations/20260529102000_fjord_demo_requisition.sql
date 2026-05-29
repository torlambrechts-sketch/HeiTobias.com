-- Seed gap fix-up: FjordTech employer had no demo requisition.
--
-- The original seed only inserted one requisition in Nordic Recruit AB
-- (the agency). With ITEM 4 landing the "Use for requisition" picker
-- triggered from a role profile, FjordTech-employer users (Linnea,
-- Erik, Sara, …) opened the dialog and saw an empty list (RLS hid
-- the agency requisition). And the Shell's hardcoded
-- /requisitions/a3000000-…001 link returned "Requisition not visible
-- at your RLS scope" for the same reason.
--
-- This adds a FjordTech demo requisition so the picker + the requisition
-- page both work end-to-end on the employer side too.
--
-- Idempotent + defensive: the Platform Team's team_id is non-deterministic
-- across reseeds (uses gen_random_uuid in seed.sql), so we LOOK IT UP
-- by org + name. If neither the team nor the role exists yet (e.g. on
-- a partial seed) we skip silently — a re-run after the seed completes
-- picks it up.

do $$
declare
  v_org   constant uuid := 'a1000000-0000-0000-0000-000000000002';  -- FjordTech AS
  v_role  uuid;
  v_team  uuid;
begin
  select id into v_team from public.teams         where org_id = v_org and name = 'Platform Team' limit 1;
  select id into v_role from public.roles_catalog where org_id = v_org and title = 'Software Engineer' and is_template = false limit 1;
  if v_team is null or v_role is null then
    raise notice 'fjord_demo_requisition: skipping — Platform Team or Software Engineer role not yet seeded';
    return;
  end if;
  insert into public.requisitions (id, org_id, role_id, team_id, status, created_by)
  values (
    'a3000000-0000-0000-0000-000000000002',
    v_org,
    v_role,
    v_team,
    'open',
    'b1000000-0000-0000-0000-000000000003'   -- Linnea (people_ops_admin)
  )
  on conflict (id) do nothing;
end$$;
