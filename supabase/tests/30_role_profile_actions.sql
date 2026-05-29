-- 30_role_profile_actions — CHECKPOINT 6.
-- Verifies the three RPCs the page action buttons route through:
--   rpc_use_role_for_requisition  — writes audit; requires requisition.write
--   rpc_role_sign_off             — only on version_status='under_review';
--                                   requires role.signoff; audited;
--                                   transitions JSON-level version_status
--                                   to signed_off + table-level status
--                                   from draft to active.
--   rpc_role_export_assemble      — wraps compliance_artifact_assemble;
--                                   carries role_id in scope_json;
--                                   sign_off_status='draft',
--                                   self_attestation=null.

begin;
select plan(16);

-- Setup: an org-owned role at version_status='under_review' for FjordTech.
do $$
declare v_role uuid; v_req uuid;
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);  -- Linnea
  -- Create a draft role in FjordTech
  insert into public.roles_catalog (org_id, title, family, is_template, status, version, definition_json)
    values ('a1000000-0000-0000-0000-000000000002'::uuid, 'Test Sign-off Role '||gen_random_uuid()::text, 'engineering', false, 'draft', 1,
      jsonb_build_object(
        'identity_and_governance', jsonb_build_object('version_status','under_review','validation_status','dev_stub','_dev_stub',true),
        'competencies', jsonb_build_array(jsonb_build_object('key','c1','weight',1.0,'criticality','critical')),
        'trait_targets', jsonb_build_array(jsonb_build_object('trait','x','direction','linear','weight',1.0,'_dev_stub',true))
      )::jsonb)
    returning id into v_role;
  -- Create a requisition that doesn't yet point at any role
  insert into public.requisitions (org_id, role_id, status)
    values ('a1000000-0000-0000-0000-000000000002'::uuid,
            (select id from public.roles_catalog where org_id='a1000000-0000-0000-0000-000000000002'::uuid limit 1),
            'open') returning id into v_req;
  perform set_config('t.role', v_role::text, true);
  perform set_config('t.req',  v_req::text, true);
end$$;

-- ============ [A] rpc_use_role_for_requisition ============
-- A1: requires rationale >= 20 chars
select throws_ok(
  format($$select public.rpc_use_role_for_requisition(%L::uuid, %L::uuid, 'short')$$, current_setting('t.role'), current_setting('t.req')),
  'P0001', NULL::text,
  '[A1] rpc_use_role_for_requisition refuses rationale <20 chars'
);

-- A2: happy path attaches role + writes audit
do $$ begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  perform public.rpc_use_role_for_requisition(current_setting('t.role')::uuid, current_setting('t.req')::uuid,
    'CP6 test fixture — attaching this role to the requisition for the engineering hire');
end$$;
select is(
  (select role_id from public.requisitions where id = current_setting('t.req')::uuid),
  current_setting('t.role')::uuid,
  '[A2] requisitions.role_id now points at the chosen role'
);
select ok(
  (select count(*) from public.audit_log where action='role.used_for_requisition' and entity_id = current_setting('t.req')::uuid) >= 1,
  '[A3] role.used_for_requisition audit event written'
);

-- A4: non-permitted caller refused (Magnus has requisition.write in Nordic Recruit, not FjordTech)
reset role;
do $$ begin perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true); end$$;
select throws_ok(
  format($$select public.rpc_use_role_for_requisition(%L::uuid, %L::uuid, 'CP6 cross-org attempt — should be refused by RBAC')$$, current_setting('t.role'), current_setting('t.req')),
  'P0001', NULL::text,
  '[A4] cross-org caller refused on rpc_use_role_for_requisition'
);

-- ============ [B] rpc_role_sign_off ============
-- B1: requires rationale >=20 chars
reset role;
do $$ begin perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true); end$$;
select throws_ok(
  format($$select public.rpc_role_sign_off(%L::uuid, 'too short')$$, current_setting('t.role')),
  'P0001', NULL::text,
  '[B1] rpc_role_sign_off refuses rationale <20 chars'
);

-- B2: happy path transitions both version_status and table status
do $$ begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  perform public.rpc_role_sign_off(current_setting('t.role')::uuid,
    'CP6 test fixture — signing off after I/O-psychologist review of bands and competencies');
end$$;
select is(
  (select definition_json -> 'identity_and_governance' ->> 'version_status' from public.roles_catalog where id = current_setting('t.role')::uuid),
  'signed_off',
  '[B2] version_status transitioned to signed_off'
);
select is(
  (select status::text from public.roles_catalog where id = current_setting('t.role')::uuid),
  'active',
  '[B3] table-level status promoted from draft to active'
);
select isnt(
  (select signed_off_by::text from public.roles_catalog where id = current_setting('t.role')::uuid),
  null::text,
  '[B4] signed_off_by stamped'
);
select ok(
  (select count(*) from public.audit_log where action='role.signed_off' and entity_id = current_setting('t.role')::uuid) >= 1,
  '[B5] role.signed_off audit event written'
);

-- B6: cannot re-sign-off (current state is signed_off, not under_review)
select throws_ok(
  format($$select public.rpc_role_sign_off(%L::uuid, 'CP6 re-attempt should be refused — already signed off')$$, current_setting('t.role')),
  'P0001', NULL::text,
  '[B6] re-signing off (state != under_review) refused'
);

-- B7: non-permitted user refused — Magnus (Nordic Recruit recruiter, no role.signoff anywhere)
reset role;
do $$ begin perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000002"}', true); end$$;
select throws_ok(
  format($$select public.rpc_role_sign_off(%L::uuid, 'CP6 hostile attempt with no role.signoff permission')$$, current_setting('t.role')),
  'P0001', NULL::text,
  '[B7] non-permitted user refused on rpc_role_sign_off'
);

-- ============ [C] rpc_role_export_assemble ============
reset role;
do $$
declare v_artifact uuid;
begin
  perform set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
  v_artifact := public.rpc_role_export_assemble(current_setting('t.role')::uuid, 'annex_iv_technical_doc');
  perform set_config('t.artifact', v_artifact::text, true);
end$$;
select ok(
  current_setting('t.artifact', true) is not null and current_setting('t.artifact', true) <> '',
  '[C1] rpc_role_export_assemble returns artifact uuid'
);
select is(
  (select sign_off_status from public.compliance_artifacts where id = current_setting('t.artifact')::uuid),
  'draft',
  '[C2] artifact lands with sign_off_status=draft (system never auto-signs)'
);
select ok(
  (select payload_json -> 'self_attestation' = 'null'::jsonb from public.compliance_artifacts where id = current_setting('t.artifact')::uuid),
  '[C3] artifact payload.self_attestation is null (system never auto-attests)'
);
select ok(
  (select scope_json ->> 'role_id' = current_setting('t.role') from public.compliance_artifacts where id = current_setting('t.artifact')::uuid),
  '[C4] artifact scope_json carries the role_id (lineage)'
);
select ok(
  (select count(*) from public.audit_log where action='role.export_assembled' and entity_id = current_setting('t.role')::uuid) >= 1,
  '[C5] role.export_assembled audit event written'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
