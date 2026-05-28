-- supabase/seed.sql — Phase 0 development fixtures.
--
-- Two orgs (agency + employer) and a small cast of people configured to exercise:
--   - cross-org tenant isolation
--   - manager-chain scope (Erik -> Sara -> Jonas, three-deep)
--   - consent gate on profiles
--   - the placement hand-off (Petra has profile_portability for FjordTech)
--
-- Idempotent: every INSERT uses ON CONFLICT DO NOTHING against a stable key
-- (id, email, or a partial unique). Re-running this file is a no-op.
--
-- Fixed UUIDs make it possible to reference fixtures by name from test SQL.

-- ============================== auth.users ===============================
insert into auth.users (id, email) values
  ('b1000000-0000-0000-0000-000000000001', 'astrid.berg@nordic-recruit.test'),
  ('b1000000-0000-0000-0000-000000000002', 'magnus.holm@nordic-recruit.test'),
  ('b1000000-0000-0000-0000-000000000003', 'linnea.strand@fjordtech.test'),
  ('b1000000-0000-0000-0000-000000000004', 'erik.lund@fjordtech.test'),
  ('b1000000-0000-0000-0000-000000000005', 'sara.vik@fjordtech.test'),
  ('b1000000-0000-0000-0000-000000000006', 'jonas.dahl@fjordtech.test'),
  ('b1000000-0000-0000-0000-000000000007', 'petra.nilsson@candidate.test'),
  ('b1000000-0000-0000-0000-000000000008', 'henrik.ek@candidate.test')
on conflict (id) do nothing;

-- ============================ organizations ==============================
insert into public.organizations (id, name, type, country, locale_default, data_region)
values
  ('a1000000-0000-0000-0000-000000000001', 'Nordic Recruit AB', 'agency',   'SE', 'sv-SE', 'us'),
  ('a1000000-0000-0000-0000-000000000002', 'FjordTech AS',      'employer', 'NO', 'nb-NO', 'us')
on conflict (id) do nothing;

-- ================================ people =================================
-- Each person's id matches their auth.users.id for deterministic look-ups.
insert into public.people (id, primary_email, full_name, given_name, family_name, auth_user_id)
values
  ('b1000000-0000-0000-0000-000000000001', 'astrid.berg@nordic-recruit.test',   'Astrid Berg',    'Astrid',  'Berg',    'b1000000-0000-0000-0000-000000000001'),
  ('b1000000-0000-0000-0000-000000000002', 'magnus.holm@nordic-recruit.test',   'Magnus Holm',    'Magnus',  'Holm',    'b1000000-0000-0000-0000-000000000002'),
  ('b1000000-0000-0000-0000-000000000003', 'linnea.strand@fjordtech.test',      'Linnea Strand',  'Linnea',  'Strand',  'b1000000-0000-0000-0000-000000000003'),
  ('b1000000-0000-0000-0000-000000000004', 'erik.lund@fjordtech.test',          'Erik Lund',      'Erik',    'Lund',    'b1000000-0000-0000-0000-000000000004'),
  ('b1000000-0000-0000-0000-000000000005', 'sara.vik@fjordtech.test',           'Sara Vik',       'Sara',    'Vik',     'b1000000-0000-0000-0000-000000000005'),
  ('b1000000-0000-0000-0000-000000000006', 'jonas.dahl@fjordtech.test',         'Jonas Dahl',     'Jonas',   'Dahl',    'b1000000-0000-0000-0000-000000000006'),
  ('b1000000-0000-0000-0000-000000000007', 'petra.nilsson@candidate.test',      'Petra Nilsson',  'Petra',   'Nilsson', 'b1000000-0000-0000-0000-000000000007'),
  ('b1000000-0000-0000-0000-000000000008', 'henrik.ek@candidate.test',          'Henrik Ek',      'Henrik',  'Ek',      'b1000000-0000-0000-0000-000000000008')
on conflict (id) do nothing;

-- ============================ memberships ================================
insert into public.memberships (id, org_id, person_id, status, joined_at) values
  ('c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'active', now()),
  ('c1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 'active', now()),
  ('c1000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000003', 'active', now()),
  ('c1000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000004', 'active', now()),
  ('c1000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000005', 'active', now()),
  ('c1000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000006', 'active', now())
on conflict (id) do nothing;

-- ====================== membership_roles (RBAC) ==========================
-- Attach the system roles to each membership.
insert into public.membership_roles (membership_id, rbac_role_id)
select c.mem, r.id
from (values
  ('c1000000-0000-0000-0000-000000000001'::uuid, 'org_admin'),         -- Astrid
  ('c1000000-0000-0000-0000-000000000002'::uuid, 'recruiter'),         -- Magnus
  ('c1000000-0000-0000-0000-000000000003'::uuid, 'people_ops_admin'),  -- Linnea
  ('c1000000-0000-0000-0000-000000000004'::uuid, 'hiring_manager'),    -- Erik
  ('c1000000-0000-0000-0000-000000000005'::uuid, 'manager'),           -- Sara
  ('c1000000-0000-0000-0000-000000000006'::uuid, 'employee')           -- Jonas
) as c(mem, role_key)
join public.rbac_roles r on r.org_id is null and r.key = c.role_key
on conflict do nothing;

-- ============================ roles_catalog ==============================
-- Agency role (will be referenced by the requisition).
insert into public.roles_catalog (id, org_id, title, family, is_template, status, version, definition_json)
values (
  'd1000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001',
  'Senior Backend Engineer', 'engineering', false, 'active', 1,
  '{"competencies":[{"key":"systems","weight":0.4},{"key":"code_craft","weight":0.3},{"key":"collaboration","weight":0.3}],"trait_targets":{"openness":[0.5,0.9]},"cognitive_demand":null}'::jsonb
)
on conflict (id) do nothing;

-- Employer roles (each a non-template instance).
insert into public.roles_catalog (id, org_id, title, family, is_template, status, version, definition_json)
values
  ('d1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'Engineering Manager',     'engineering', false, 'active', 1, '{}'::jsonb),
  ('d1000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000002', 'Software Engineering Lead','engineering', false, 'active', 1, '{}'::jsonb),
  ('d1000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000002', 'Software Engineer',       'engineering', false, 'active', 1, '{}'::jsonb)
on conflict (id) do nothing;

-- ============================== positions ================================
-- Three-deep manager chain in the employer org: Erik (top) <- Sara <- Jonas.
insert into public.positions (id, org_id, role_id, person_id, status, start_date)
values
  -- Erik (top of chain — no manager_position_id)
  ('e1000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000002',
   'd1000000-0000-0000-0000-000000000002',  -- Engineering Manager
   'b1000000-0000-0000-0000-000000000004',  -- Erik
   'filled', current_date)
on conflict (id) do nothing;

insert into public.positions (id, org_id, role_id, person_id, manager_position_id, status, start_date)
values
  -- Sara (reports to Erik)
  ('e1000000-0000-0000-0000-000000000002',
   'a1000000-0000-0000-0000-000000000002',
   'd1000000-0000-0000-0000-000000000003',  -- Software Engineering Lead
   'b1000000-0000-0000-0000-000000000005',  -- Sara
   'e1000000-0000-0000-0000-000000000001',  -- under Erik
   'filled', current_date),
  -- Jonas (reports to Sara)
  ('e1000000-0000-0000-0000-000000000003',
   'a1000000-0000-0000-0000-000000000002',
   'd1000000-0000-0000-0000-000000000004',  -- Software Engineer
   'b1000000-0000-0000-0000-000000000006',  -- Jonas
   'e1000000-0000-0000-0000-000000000002',  -- under Sara
   'filled', current_date)
on conflict (id) do nothing;

-- ========================== consent_grants ===============================
-- Petra: profile_portability granted to FjordTech (for the placement hand-off).
-- Petra: hiring_decision granted to Nordic Recruit (so they can use her profile).
insert into public.consent_grants (id, person_id, granted_to_org_id, purpose, status)
values
  ('f1000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000007',  -- Petra
   'a1000000-0000-0000-0000-000000000001',  -- Nordic Recruit
   'hiring_decision', 'active'),
  ('f1000000-0000-0000-0000-000000000002',
   'b1000000-0000-0000-0000-000000000007',  -- Petra
   'a1000000-0000-0000-0000-000000000002',  -- FjordTech
   'profile_portability', 'active')
on conflict (id) do nothing;

-- ============================== profiles =================================
-- Petra has a profile in the agency, bound to her hiring_decision consent.
insert into public.profiles (id, org_id, person_id, source, consent_id, traits_json, cognitive_json, values_json, derived_json)
values (
  'a2000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001',  -- Nordic Recruit (agency)
  'b1000000-0000-0000-0000-000000000007',  -- Petra
  'assessment',
  'f1000000-0000-0000-0000-000000000001',  -- her hiring_decision consent
  '{"openness":0.78,"conscientiousness":0.82,"extraversion":0.55}'::jsonb,
  '{"reasoning":0.71}'::jsonb,
  '{"autonomy":0.6,"impact":0.7}'::jsonb,
  '{"strengths":["systems thinking"],"friction":[]}'::jsonb
)
on conflict (id) do nothing;

-- ============================ requisition ================================
insert into public.requisitions (id, org_id, role_id, status, created_by)
values (
  'a3000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001',  -- agency-owned
  'd1000000-0000-0000-0000-000000000001',  -- Senior Backend Engineer
  'shortlisting',
  'b1000000-0000-0000-0000-000000000002'   -- Magnus (the recruiter)
)
on conflict (id) do nothing;

-- ======================= requisition_candidates ==========================
insert into public.requisition_candidates (id, org_id, requisition_id, person_id, stage)
values
  ('a4000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001',
   'a3000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000007',  -- Petra
   'interview'),
  ('a4000000-0000-0000-0000-000000000002',
   'a1000000-0000-0000-0000-000000000001',
   'a3000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000008',  -- Henrik
   'screening')
on conflict (id) do nothing;

-- ============================ PHASE 2 demo state =========================
-- Idempotent append that walks ONE candidate (Sigrid) through the entire
-- Phase 1 + Phase 2 lifecycle so the employer-activations + kickstart
-- surfaces have something to show on a fresh seed:
--   1. Sigrid is a candidate sourced through Nordic Recruit.
--   2. Assessment invited, consent captured, 5 items answered, scored.
--   3. Fit computed; "hire" decision recorded.
--   4. Sigrid grants portability to FjordTech via her consent dashboard.
--   5. placement_execute transfers profile + position to FjordTech;
--      Sigrid's agency membership atomically flips to "removed".
--   6. placement_activate captures ongoing_management consent at FjordTech
--      (legal_basis = contract).
--   7. kickstart_generate produces a 90-day plan grounded in the seeded
--      DEV-STUB frameworks.
-- Petra remains in her shortlisting state so the recruiter desk has an
-- interactive candidate to walk through end-to-end.

insert into auth.users (id, email) values
  ('b1000000-0000-0000-0000-000000000009', 'sigrid.lund@candidate.test')
on conflict (id) do nothing;

insert into public.people (id, full_name, primary_email, auth_user_id)
values ('b1100000-0000-0000-0000-000000000009', 'Sigrid Lund',
        'sigrid.lund@candidate.test', 'b1000000-0000-0000-0000-000000000009')
on conflict (id) do nothing;

insert into public.memberships (id, org_id, person_id, status)
values ('b2100000-0000-0000-0000-000000000009',
        'a1000000-0000-0000-0000-000000000001',  -- Nordic Recruit
        'b1100000-0000-0000-0000-000000000009',
        'invited')
on conflict (id) do nothing;

do $seed_phase2$
declare
  agency_a   constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  sigrid     constant uuid := 'b1100000-0000-0000-0000-000000000009';
  v_existing_placement uuid;
  inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid;
begin
  -- Skip the whole demo bootstrap if Sigrid has already been placed once
  -- (re-running the seed is then a no-op).
  select id into v_existing_placement from public.placements
    where person_id = sigrid and to_org_id = employer_a limit 1;
  if v_existing_placement is not null then return; end if;

  -- Phase 1 pipeline: invite → consent → take → score → fit → decide.
  inv := public.assessment_invite_create(agency_a, sigrid, 'sample_personality_v0', 'personality', 14);
  tok := inv->>'token';
  cap_consent := public.assessment_capture_consent(tok);
  for it in
    select i.id from public.assessment_items i
    join public.assessment_instruments ai on ai.id = i.instrument_id
    where ai.key = 'sample_personality_v0'
  loop
    perform public.assessment_submit_response(tok, it.id, jsonb_build_object('value', 4));
  end loop;
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);
  perform public.compute_fit_for_candidate(agency_req, sigrid);
  perform public.hiring_decision_record(agency_req, sigrid, 'hire',
    'DEMO STATE: confirming hire so Phase 2 surfaces have a placed candidate.');

  -- Phase 2: candidate dashboard grants portability.
  select token into ct_token from public.consent_tokens
    where person_id = sigrid and revoked_at is null limit 1;
  port_grant := public.portability_grant(ct_token, employer_a);

  -- Placement transfer.
  placement_id := public.placement_execute(agency_req, sigrid, employer_a, port_grant);

  -- Employer activation: captures ongoing_management.
  perform public.placement_activate(placement_id);

  -- 90-day kickstart plan.
  perform public.kickstart_generate(sigrid, employer_a);
end$seed_phase2$;

-- ============================ PHASE 3 demo state =========================
-- Continues the Sigrid story into the lifecycle layer so the manager
-- workspace + employee self-view have data on a fresh seed:
--   8. Sigrid joins a FjordTech Platform team.
--   9. Sigrid submits 2 pulse check-ins.
--  10. Linnea computes signals + 2 re-fit evaluations + grounded guidance.
--  11. Linnea records an action on the first guidance item.
-- Re-running the seed is a no-op once Sigrid has at least one pulse.

do $seed_phase3$
declare
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  sigrid     constant uuid := 'b1100000-0000-0000-0000-000000000009';
  sigrid_uid constant uuid := 'b1000000-0000-0000-0000-000000000009';
  linnea_uid constant uuid := 'b1000000-0000-0000-0000-000000000003';
  v_dept uuid; v_team uuid; v_template uuid; v_consent uuid; v_g_id uuid;
begin
  -- Idempotency: if Sigrid already has a pulse, skip everything.
  if exists (select 1 from public.pulse_checkins where person_id = sigrid) then
    return;
  end if;

  -- Sigrid's ongoing_management consent (created at activation in the Phase 2 demo block).
  select id into v_consent from public.consent_grants
    where person_id = sigrid and granted_to_org_id = employer_a
      and purpose = 'ongoing_management' and status = 'active' limit 1;
  if v_consent is null then return; end if;

  -- Team membership.
  insert into public.departments (org_id, name)
    values (employer_a, 'Platform') returning id into v_dept;
  insert into public.teams (org_id, department_id, name)
    values (employer_a, v_dept, 'Platform Team') returning id into v_team;
  insert into public.team_members (org_id, team_id, person_id, role_in_team)
    values (employer_a, v_team, sigrid, 'engineer');

  select id into v_template from public.frameworks where key = 'pulse_v0_quarterly' limit 1;

  -- Sigrid submits two pulses.
  perform set_config('request.jwt.claims', json_build_object('sub', sigrid_uid)::text, true);
  perform public.pulse_submit(v_consent, v_template,
    jsonb_build_object('answers', jsonb_build_array(
      jsonb_build_object('key','energy','value',4),
      jsonb_build_object('key','clarity','value',3),
      jsonb_build_object('key','support','value',5))));
  perform public.pulse_submit(v_consent, v_template,
    jsonb_build_object('answers', jsonb_build_array(
      jsonb_build_object('key','energy','value',5),
      jsonb_build_object('key','clarity','value',4),
      jsonb_build_object('key','support','value',5))));

  -- Linnea computes signals + two re-fit evaluations + guidance.
  perform set_config('request.jwt.claims', json_build_object('sub', linnea_uid)::text, true);
  perform public.signal_compute(sigrid, employer_a, 4);
  perform public.refit_compute(sigrid, employer_a);
  perform public.refit_compute(sigrid, employer_a);
  v_g_id := public.guidance_compose(sigrid, employer_a, 'one_on_one_prep'::public.guidance_kind, '{"demo":true}'::jsonb);
  perform public.guidance_record_action(v_g_id, 'acted_on'::public.guidance_action, 'Discussed in this week''s 1:1');
end$seed_phase3$;
