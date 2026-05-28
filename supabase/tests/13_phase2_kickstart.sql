-- 13_phase2_kickstart — PHASE2 Step 6: frameworks library + 90-day kickstart.
-- Generation rule: every plan item must cite a framework_id (grounded);
-- no freeform output about a named person; frameworks themselves are
-- labeled DEV-STUB content.

begin;
select plan(11);

-- Setup: place a candidate, activate at employer (captures ongoing_management).
do $$
declare
  agency_a constant uuid := 'a1000000-0000-0000-0000-000000000001';
  employer_a constant uuid := 'a1000000-0000-0000-0000-000000000002';
  agency_req constant uuid := 'a3000000-0000-0000-0000-000000000001';
  astrid constant uuid := 'b1000000-0000-0000-0000-000000000001';
  linnea constant uuid := 'b1000000-0000-0000-0000-000000000003';
  cand uuid; inv jsonb; tok text; cap_consent uuid; ct_token text; it record;
  port_grant uuid; placement_id uuid; activate_result jsonb;
begin
  insert into public.people (full_name, primary_email) values ('Kickstart Cand', 'ks_'||gen_random_uuid()||'@p2.test') returning id into cand;
  insert into public.memberships (org_id, person_id, status) values (agency_a, cand, 'invited');
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  inv := public.assessment_invite_create(agency_a, cand,'sample_personality_v0','personality',14);
  tok := inv->>'token';
  perform set_config('request.jwt.claims','{}', true);
  cap_consent := public.assessment_capture_consent(tok);
  for it in select i.id from public.assessment_items i join public.assessment_instruments ai on ai.id=i.instrument_id where ai.key='sample_personality_v0' loop
    perform public.assessment_submit_response(tok, it.id, '{"value":4}'::jsonb);
  end loop;
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  perform public.assessment_run_scoring((inv->>'assessment_id')::uuid);
  perform public.compute_fit_for_candidate(agency_req, cand);
  perform public.hiring_decision_record(agency_req, cand,'hire','fixture');
  select token into ct_token from public.consent_tokens where person_id=cand and revoked_at is null limit 1;
  perform set_config('request.jwt.claims','{}', true);
  port_grant := public.portability_grant(ct_token, employer_a);
  perform set_config('request.jwt.claims', json_build_object('sub',astrid)::text, true);
  placement_id := public.placement_execute(agency_req, cand, employer_a, port_grant);
  perform set_config('t.cand', cand::text, true);
  perform set_config('t.placement', placement_id::text, true);
end$$;

-- [A] BEFORE activation: kickstart_generate rejects (no ongoing_management).
do $$ begin perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true); end$$;
select throws_ok(
  format($$select public.kickstart_generate(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid)$$, current_setting('t.cand')),
  'P0001', NULL::text,
  '[A1] kickstart_generate rejected without active ongoing_management consent'
);

-- Activate (captures ongoing_management).
do $$ declare r jsonb; begin r := public.placement_activate(current_setting('t.placement')::uuid); end$$;

-- [B] Generate succeeds; plan row carries validity_status=dev_stub.
do $$
declare plan_id uuid;
begin
  perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  plan_id := public.kickstart_generate(current_setting('t.cand')::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid);
  perform set_config('t.plan', plan_id::text, true);
end$$;

select ok(current_setting('t.plan')::uuid is not null, '[B1] kickstart_generate returns a plan id');
select is(
  (select validity_status::text from public.kickstart_plans where id=current_setting('t.plan')::uuid),
  'dev_stub',
  '[B2] plan row carries validity_status=dev_stub'
);
select ok(
  (select _dev_stub from public.kickstart_plans where id=current_setting('t.plan')::uuid),
  '[B3] plan row has _dev_stub=true'
);

-- [C] Every milestone in plan_json has a framework_id (grounded, not freeform).
select ok(
  (select bool_and((m->>'framework_id') is not null)
    from public.kickstart_plans p, lateral jsonb_array_elements(p.plan_json->'milestones') m
    where p.id = current_setting('t.plan')::uuid),
  '[C1] every milestone cites a framework_id'
);

-- [C2] Every tailored prompt has a framework_id too.
select ok(
  (select bool_and((m->>'framework_id') is not null)
    from public.kickstart_plans p, lateral jsonb_array_elements(p.plan_json->'tailored_prompts') m
    where p.id = current_setting('t.plan')::uuid),
  '[C2] every tailored manager_prompt cites a framework_id'
);

-- [C3] frameworks_used array is populated (audit trail of what fed the generation).
select ok(
  (select array_length(frameworks_used, 1) from public.kickstart_plans where id=current_setting('t.plan')::uuid) >= 4,
  '[C3] frameworks_used has >= 4 entries (4 milestones + prompts)'
);

-- [D] Audit row written.
select ok(
  (select count(*) from public.audit_log
    where action='kickstart.generated' and entity_id=current_setting('t.plan')::uuid) >= 1,
  '[D1] kickstart.generated audited'
);

-- [E] No frameworks in seed/library have validity_status='validated'.
select is(
  (select count(*) from public.frameworks where validity_status='validated'),
  0::bigint,
  '[E1] zero validated frameworks in seed (DEV-STUB seam guard)'
);

-- [F] Revoking ongoing_management blocks future generation.
reset role;
do $$
declare consent_id uuid;
begin
  select id into consent_id from public.consent_grants
    where person_id=current_setting('t.cand')::uuid
      and granted_to_org_id='a1000000-0000-0000-0000-000000000002'::uuid
      and purpose='ongoing_management' and status='active' limit 1;
  update public.consent_grants set status='revoked', revoked_at=now() where id=consent_id;
end$$;
do $$ begin perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003"}', true); end$$;
select throws_ok(
  format($$select public.kickstart_generate(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid)$$, current_setting('t.cand')),
  'P0001', NULL::text,
  '[F1] revoke ongoing_management -> future generation blocked'
);

-- [G] Authz: no-perm caller rejected.
do $$ begin perform set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002"}', true); end$$;
select throws_ok(
  format($$select public.kickstart_generate(%L::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid)$$, current_setting('t.cand')),
  'P0001', NULL::text,
  '[G1] caller without org.manage_all rejected'
);

select * from finish();
rollback;
