-- 28_external_review_closure — closures from the external senior +
-- design review:
--   * org_invite_accept rejects when the person row is linked to a
--     different auth account (hijack prevention).
--   * org_invite_revoke flips revoked_at + writes audit + future
--     accept attempts fail.
--   * Expired tokens cannot be accepted.
--   * org_invite_state refuses expired/revoked tokens.

begin;
select plan(8);

select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);

-- [A] hijack-prevent
do $$
declare m uuid; t jsonb; tok text; email text := 'h+'||gen_random_uuid()::text||'@h.t';
        owner_auth uuid := gen_random_uuid(); other_auth uuid := gen_random_uuid(); refused text := 'NOT_REFUSED';
begin
  m := public.org_invite_user('a1000000-0000-0000-0000-000000000002'::uuid, email, 'hiring_manager', null);
  t := public.invite_token_for(m); tok := t->>'token';
  -- Pretend an earlier flow linked the person to a different auth account
  insert into auth.users (id, email) values (owner_auth, email);
  update public.people set auth_user_id = owner_auth where primary_email = lower(email);
  -- A second auth user with the (impossible but simulated) same address tries to accept
  insert into auth.users (id, email) values (other_auth, 'second_'||email);
  -- Force the people row's email to mismatch first to get past the email check, then put it back
  update public.people set primary_email = 'second_'||email where primary_email = lower(email);
  reset role; perform set_config('request.jwt.claims', json_build_object('sub', other_auth)::text, true);
  begin perform public.org_invite_accept(tok);
  exception when others then refused := 'REFUSED';
  end;
  perform set_config('t.hijack', refused, true);
end$$;
select is(current_setting('t.hijack'), 'REFUSED', '[A1] hijack: person.auth_user_id mismatch refuses accept');

-- [B] revoke flow
reset role; select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
do $$
declare m uuid; t jsonb; tok text; tid uuid; refused text := 'NOT_REFUSED';
        email text := 'rv+'||gen_random_uuid()::text||'@h.t'; auth_user uuid := gen_random_uuid();
begin
  m := public.org_invite_user('a1000000-0000-0000-0000-000000000002'::uuid, email, 'hiring_manager', null);
  t := public.invite_token_for(m); tok := t->>'token'; tid := (t->>'id')::uuid;
  perform public.org_invite_revoke(tid);
  -- Now an invitee tries to accept
  insert into auth.users (id, email) values (auth_user, email);
  update public.people set auth_user_id = auth_user where primary_email = lower(email);
  reset role; perform set_config('request.jwt.claims', json_build_object('sub', auth_user)::text, true);
  begin perform public.org_invite_accept(tok);
  exception when others then refused := 'REFUSED';
  end;
  perform set_config('t.revoked_accept', refused, true);
  perform set_config('t.tid', tid::text, true);
end$$;
select is(current_setting('t.revoked_accept'), 'REFUSED', '[B1] revoked token cannot be accepted');
select ok(
  (select revoked_at is not null from public.invite_tokens where id = current_setting('t.tid')::uuid),
  '[B2] revoked_at stamped'
);
select ok(
  (select count(*) from public.audit_log where action = 'org.invite_revoked' and entity_id = current_setting('t.tid')::uuid) >= 1,
  '[B3] org.invite_revoked audit event written'
);

-- [C] expired token
reset role; select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
do $$
declare m uuid; t jsonb; tok text; tid uuid; refused text := 'NOT_REFUSED';
        email text := 'ex+'||gen_random_uuid()::text||'@h.t'; auth_user uuid := gen_random_uuid();
begin
  m := public.org_invite_user('a1000000-0000-0000-0000-000000000002'::uuid, email, 'hiring_manager', null);
  t := public.invite_token_for(m); tok := t->>'token'; tid := (t->>'id')::uuid;
  reset role; update public.invite_tokens set expires_at = now() - interval '1 hour' where id = tid;
  insert into auth.users (id, email) values (auth_user, email);
  update public.people set auth_user_id = auth_user where primary_email = lower(email);
  perform set_config('request.jwt.claims', json_build_object('sub', auth_user)::text, true);
  begin perform public.org_invite_accept(tok);
  exception when others then refused := 'REFUSED';
  end;
  -- org_invite_state should also refuse the expired token
  perform set_config('request.jwt.claims', '{}', true);
  begin perform public.org_invite_state(tok);
    perform set_config('t.state_refused', 'NOT_REFUSED', true);
  exception when others then perform set_config('t.state_refused', 'REFUSED', true);
  end;
  perform set_config('t.expired_accept', refused, true);
end$$;
select is(current_setting('t.expired_accept'), 'REFUSED', '[C1] expired token refused on accept');
select is(current_setting('t.state_refused'), 'REFUSED', '[C2] expired token refused on org_invite_state');

-- [D] anon-friendly org_invite_state for VALID token
reset role; select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000003"}', true);
do $$
declare m uuid; t jsonb; tok text; state jsonb;
        email text := 'state+'||gen_random_uuid()::text||'@h.t';
begin
  m := public.org_invite_user('a1000000-0000-0000-0000-000000000002'::uuid, email, 'hiring_manager', null);
  t := public.invite_token_for(m); tok := t->>'token';
  reset role; perform set_config('request.jwt.claims', '{}', true);
  state := public.org_invite_state(tok);
  perform set_config('t.state_email', state->>'invited_email', true);
  perform set_config('t.state_org', state->>'org_name', true);
end$$;
select isnt(current_setting('t.state_email'), '', '[D1] anon read of org_invite_state returns invited_email');
select isnt(current_setting('t.state_org'), '', '[D2] anon read of org_invite_state returns org_name');

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
