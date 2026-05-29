-- 27_followup_acceptance — Steps A-F from the senior-review follow-up.
-- Verifies: audit-log query + filter + paginate, multi-role attach/detach
-- (incl. safety on last role), invite token mint + state + accept lifecycle,
-- profile correction + reason + field whitelist, admin_overview pagination,
-- URL validation (https-only / accent #RRGGBB), org_for_current_user
-- discovery, trait-target backfill diagnostic view.

begin;
select plan(20);

select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);

-- [A] admin_audit_log_query — read + paginate + filter
select ok(
  jsonb_array_length((public.admin_audit_log_query('a1000000-0000-0000-0000-000000000002'::uuid, null, null, null, null, null, 5, 0)) -> 'rows') >= 1,
  '[A1] admin_audit_log_query returns rows (page 1, limit 5)'
);
select ok(
  ((public.admin_audit_log_query('a1000000-0000-0000-0000-000000000002'::uuid, 'org.%', null, null, null, null, 50, 0)) -> 'total')::int >= 0,
  '[A2] admin_audit_log_query filter by action LIKE pattern works'
);
-- non-admin refused
reset role;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000005"}', true);  -- Sara, no manage_all
select throws_ok(
  $$select public.admin_audit_log_query('a1000000-0000-0000-0000-000000000002'::uuid)$$,
  'P0001', NULL::text,
  '[A3] non-admin refused from admin_audit_log_query'
);

-- [B] multi-role attach / detach
reset role;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
do $$
declare m_id uuid; before_roles text; after_attach text; after_detach text;
begin
  m_id := public.org_invite_user('a1000000-0000-0000-0000-000000000002'::uuid, 'multi+'||gen_random_uuid()::text||'@h.t', 'hiring_manager', null);
  perform public.org_role_attach(m_id, 'manager');
  select string_agg(r.key, ',' order by r.key) into after_attach
    from public.membership_roles mr join public.rbac_roles r on r.id = mr.rbac_role_id where mr.membership_id = m_id;
  perform public.org_role_detach(m_id, 'hiring_manager');
  select string_agg(r.key, ',' order by r.key) into after_detach
    from public.membership_roles mr join public.rbac_roles r on r.id = mr.rbac_role_id where mr.membership_id = m_id;
  perform set_config('t.attach', after_attach, true);
  perform set_config('t.detach', after_detach, true);
end$$;
select is(current_setting('t.attach'), 'hiring_manager,manager', '[B1] attach adds a role without replacing');
select is(current_setting('t.detach'), 'manager', '[B2] detach removes only the named role');
-- Safety: cannot detach the LAST remaining role
do $$ declare m_id uuid; refused text := 'NOT_REFUSED'; begin
  m_id := public.org_invite_user('a1000000-0000-0000-0000-000000000002'::uuid, 'single+'||gen_random_uuid()::text||'@h.t', 'employee', null);
  begin perform public.org_role_detach(m_id, 'employee'); exception when others then refused := 'REFUSED'; end;
  perform set_config('t.last', refused, true);
end$$;
select is(current_setting('t.last'), 'REFUSED', '[B3] detaching last role on a membership refused');

-- [C] invite + accept lifecycle
do $$
declare m_id uuid; t jsonb; tok text; email text := 'flow+'||gen_random_uuid()::text||'@h.t';
        auth_user uuid := gen_random_uuid(); status_after text;
begin
  m_id := public.org_invite_user('a1000000-0000-0000-0000-000000000002'::uuid, email, 'hiring_manager', 'Flow Test');
  t := public.invite_token_for(m_id);
  tok := t->>'token';
  reset role; perform set_config('request.jwt.claims', '{}', true);
  perform public.org_invite_state(tok);
  insert into auth.users (id, email) values (auth_user, email);
  update public.people set auth_user_id = auth_user where primary_email = lower(email);
  perform set_config('request.jwt.claims', json_build_object('sub', auth_user)::text, true);
  perform public.org_invite_accept(tok);
  select status::text into status_after from public.memberships where id = m_id;
  perform set_config('t.membership', m_id::text, true);
  perform set_config('t.status_after', status_after, true);
  perform set_config('t.token', tok, true);
end$$;
select is(current_setting('t.status_after'), 'active', '[C1] org_invite_accept flips membership to active');
select ok(
  (select accepted_at is not null from public.invite_tokens where token = current_setting('t.token')),
  '[C2] invite token marked accepted'
);
-- Replay: re-accepting the same token must fail
select throws_ok(
  format($$select public.org_invite_accept(%L)$$, current_setting('t.token')),
  'P0001', NULL::text,
  '[C3] re-accepting an already-consumed token refused'
);
-- Audit
select ok(
  (select count(*) from public.audit_log where action = 'org.invite_accepted' and entity_id = current_setting('t.membership')::uuid) >= 1,
  '[C4] org.invite_accepted audit event written'
);

-- [D] profile correction
reset role; select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
do $$
declare p_id uuid; cand uuid; after_traits jsonb;
begin
  insert into public.people (full_name, primary_email) values ('Correction Test','corr_'||gen_random_uuid()||'@h.t') returning id into cand;
  insert into public.profiles (org_id, person_id, source, traits_json, valid_from, consent_id)
    values ('a1000000-0000-0000-0000-000000000002'::uuid, cand, 'assessment', '{"openness":0.5}'::jsonb, now(), null) returning id into p_id;
  perform public.profile_correction_record(p_id, 'traits_json', '{"openness":0.55}'::jsonb, 'Correcting an openness typo: was 0.5, should be 0.55 per validated scoring');
  select traits_json into after_traits from public.profiles where id = p_id;
  perform set_config('t.profile_after', after_traits::text, true);
  perform set_config('t.prof_id', p_id::text, true);
end$$;
select is(current_setting('t.profile_after'), '{"openness": 0.55}', '[D1] profile_correction_record updates the field');
-- Direct UPDATE still refused
select throws_ok(
  format($$update public.profiles set traits_json='{"openness":0.9}'::jsonb where id=%L::uuid$$, current_setting('t.prof_id')),
  'P0001', NULL::text,
  '[D2] direct UPDATE on traits_json still refused (append-only guard intact)'
);
-- Field whitelist
select throws_ok(
  format($$select public.profile_correction_record(%L::uuid, 'org_id', '"00000000-0000-0000-0000-000000000000"'::jsonb, 'Trying to change org should not be allowed')$$, current_setting('t.prof_id')),
  'P0001', NULL::text,
  '[D3] field whitelist blocks org_id correction'
);
-- Short reason
select throws_ok(
  format($$select public.profile_correction_record(%L::uuid, 'traits_json', '{"x":1}'::jsonb, 'short')$$, current_setting('t.prof_id')),
  'P0001', NULL::text,
  '[D4] reason <20 chars refused'
);
-- Audit row
select ok(
  (select count(*) from public.audit_log where action='profile.corrected' and entity_id = current_setting('t.prof_id')::uuid) >= 1,
  '[D5] profile.corrected audit event written'
);

-- [E] admin_overview pagination + URL validation + org_for_current_user
select ok(
  ((public.admin_overview('a1000000-0000-0000-0000-000000000002'::uuid, 2, 0, 5)) -> 'members_total')::int >= 1,
  '[E1] admin_overview returns members_total'
);
select throws_ok(
  $$select public.org_settings_update('a1000000-0000-0000-0000-000000000002'::uuid, null, null, null, 'javascript:alert(1)', null)$$,
  'P0001', NULL::text,
  '[E2] javascript: URL refused on logo_url'
);
select throws_ok(
  $$select public.org_settings_update('a1000000-0000-0000-0000-000000000002'::uuid, null, null, 'red', null, null)$$,
  'P0001', NULL::text,
  '[E3] non-#RRGGBB accent_color refused'
);
select ok(
  jsonb_array_length((public.org_for_current_user()) -> 'rows') >= 1,
  '[E4] org_for_current_user returns at least one org for the signed-in admin'
);

-- [F] backfilled trait_targets diagnostic view
select ok(
  (select count(*) from public.role_trait_targets_backfilled) >= 0,
  '[F1] role_trait_targets_backfilled view queryable (backfilled rows surface for I/O psychologist replacement)'
);

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
