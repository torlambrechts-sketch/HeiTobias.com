-- H-1a Evidence-Base Versioning — discipline tests
--
-- Strategy: probe the CHECK constraints, the partial unique index, the
-- view, and the RPC's refusal modes. No real expert sign-off happens
-- in tests — discipline survives.

-- ─── 1. Schema presence ───────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_type where typname = 'citation_type') then
    raise exception 'h1a: citation_type enum missing';
  end if;
  if not exists (select 1 from pg_type where typname = 'evidence_predictor_type') then
    raise exception 'h1a: evidence_predictor_type enum missing';
  end if;
  if not exists (
    select 1 from information_schema.tables
     where table_schema='public' and table_name='citations'
  ) then raise exception 'h1a: citations table missing'; end if;
  if not exists (
    select 1 from information_schema.tables
     where table_schema='public' and table_name='evidence_base_positions'
  ) then raise exception 'h1a: evidence_base_positions table missing'; end if;
  if not exists (
    select 1 from information_schema.views
     where table_schema='public' and table_name='v_current_evidence_base_position'
  ) then raise exception 'h1a: v_current_evidence_base_position view missing'; end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='rpc_position_signoff'
  ) then raise exception 'h1a: rpc_position_signoff function missing'; end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='has_global_permission'
  ) then raise exception 'h1a: has_global_permission function missing'; end if;
  raise notice 'h1a: schema presence ok';
end$$;

-- ─── 2. Seed completeness ─────────────────────────────────────────────
do $$
declare v_citations int; v_positions int; v_dev_stub int;
begin
  select count(*) into v_citations from public.citations;
  if v_citations < 25 then
    raise exception 'h1a: expected >=25 citations seeded, got %', v_citations;
  end if;

  select count(*) into v_positions
    from public.evidence_base_positions where version_id='ebv-2025-01';
  if v_positions <> 13 then
    raise exception 'h1a: expected 13 ebv-2025-01 positions, got %', v_positions;
  end if;

  -- Every seeded position must be dev_stub
  select count(*) into v_dev_stub
    from public.evidence_base_positions
   where version_id='ebv-2025-01'
     and validity_status='dev_stub' and _dev_stub=true;
  if v_dev_stub <> 13 then
    raise exception 'h1a: expected all 13 positions dev_stub, got % dev_stub', v_dev_stub;
  end if;

  raise notice 'h1a: seed completeness ok (% citations, % positions all dev_stub)',
    v_citations, v_positions;
end$$;

-- ─── 3. Dev-stub discipline (CLAUDE.md guard): zero validated rows ───
do $$
declare v_validated int;
begin
  select count(*) into v_validated
    from public.evidence_base_positions
   where validity_status = 'validated';
  if v_validated <> 0 then
    raise exception 'h1a: % validated rows found in fixtures — DISCIPLINE BREACH', v_validated;
  end if;
  raise notice 'h1a: dev_stub discipline preserved (0 validated rows)';
end$$;

-- ─── 4. CHECK constraints ────────────────────────────────────────────
do $$
declare v_pos_id uuid; v_person_id uuid;
begin
  -- Use a NON-current row (effective_to set) to avoid the partial unique index
  select id into v_person_id from public.people limit 1;

  insert into public.evidence_base_positions
    (version_id, predictor_type, effective_from, effective_to,
     validity_lower, validity_upper, validity_anchor,
     validity_status, _dev_stub)
  values ('ebv-h1a-test', 'sjt', '2020-01-01', '2020-12-31',
          null, null, null, 'dev_stub', true)
  returning id into v_pos_id;

  -- (a) validated requires non-null anchor
  begin
    update public.evidence_base_positions
       set validity_status='validated', _dev_stub=false,
           signoff_actor_id=v_person_id, signoff_at=now(),
           signoff_rationale='rationale long enough to clear the fifty-character minimum bar for testing'
     where id = v_pos_id;
    raise exception 'h1a: CHECK failed — validated with null anchor accepted';
  exception when check_violation then null;
  end;

  -- (b) validated requires _dev_stub=false
  update public.evidence_base_positions set validity_anchor=0.260 where id=v_pos_id;
  begin
    update public.evidence_base_positions
       set validity_status='validated', _dev_stub=true,
           signoff_actor_id=v_person_id, signoff_at=now(),
           signoff_rationale='rationale long enough to clear the fifty-character minimum bar for testing'
     where id = v_pos_id;
    raise exception 'h1a: CHECK failed — validated with _dev_stub=true accepted';
  exception when check_violation then null;
  end;

  -- (c) validated requires signoff_actor
  begin
    update public.evidence_base_positions
       set validity_status='validated', _dev_stub=false,
           signoff_actor_id=null, signoff_at=now(),
           signoff_rationale='rationale long enough to clear the fifty-character minimum bar for testing'
     where id = v_pos_id;
    raise exception 'h1a: CHECK failed — validated with null actor accepted';
  exception when check_violation then null;
  end;

  -- (d) signoff_rationale must be >=50 chars even outside validated
  begin
    update public.evidence_base_positions
       set signoff_rationale = 'short'
     where id = v_pos_id;
    raise exception 'h1a: CHECK failed — short rationale accepted';
  exception when check_violation then null;
  end;

  -- (e) anchor must be inside [lower, upper]
  begin
    update public.evidence_base_positions
       set validity_lower=0.3, validity_upper=0.4, validity_anchor=0.5
     where id = v_pos_id;
    raise exception 'h1a: CHECK failed — anchor outside range accepted';
  exception when check_violation then null;
  end;

  -- (f) lower <= upper
  begin
    update public.evidence_base_positions
       set validity_lower=0.5, validity_upper=0.3, validity_anchor=null
     where id = v_pos_id;
    raise exception 'h1a: CHECK failed — lower>upper accepted';
  exception when check_violation then null;
  end;

  -- Successful full validate (all conditions met)
  update public.evidence_base_positions
     set validity_lower=0.2, validity_upper=0.3, validity_anchor=0.26,
         validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_person_id, signoff_at=now(),
         signoff_rationale='Reviewed evidence base and confirm anchor at .26 is appropriate for our population/use-case.'
   where id = v_pos_id;

  -- Cleanup
  delete from public.evidence_base_positions where id = v_pos_id;
  raise notice 'h1a: all CHECK constraints fire as designed';
end$$;

-- ─── 5. Partial unique index — one current per predictor_type ────────
do $$
declare v_existing_id uuid;
begin
  select id into v_existing_id
    from public.evidence_base_positions
   where predictor_type='gma' and effective_to is null;
  if v_existing_id is null then
    raise exception 'h1a: no current gma position to test against';
  end if;

  -- Insert another current gma — should fail
  begin
    insert into public.evidence_base_positions
      (version_id, predictor_type, validity_lower, validity_upper, validity_anchor)
    values ('ebv-h1a-test', 'gma', 0.31, 0.51, 0.31);
    -- If we get here, the partial unique index failed
    raise exception 'h1a: partial unique index failed — duplicate current gma accepted';
  exception when unique_violation then
    null;
  end;
  raise notice 'h1a: partial unique index enforces one-current-per-predictor';
end$$;

-- ─── 6. RPC refuses without permission ───────────────────────────────
do $$
declare v_pos_id uuid; v_result jsonb;
begin
  -- A test DB session has no auth.uid() context so the permission gate
  -- is the first refusal. The RPC raises insufficient_privilege (42501).
  select id into v_pos_id from public.evidence_base_positions
   where predictor_type='gma' and effective_to is null;
  begin
    v_result := public.rpc_position_signoff(
      v_pos_id,
      'a rationale long enough to clear the fifty-character minimum bar for testing'
    );
    raise exception 'h1a: RPC accepted call without modeling.signoff';
  exception when insufficient_privilege then
    null;
  end;
  raise notice 'h1a: rpc_position_signoff refuses without modeling.signoff';
end$$;

-- ─── 7. RPC refuses short rationale (even if perm were granted) ──────
-- We can probe this by direct call: short rationale should raise BEFORE
-- the permission gate, since the gate is checked first. Actually the
-- gate is checked first — so this exception under the test session is
-- the permission denial. We instead test the rationale guard by
-- pretending the gate passed via a service_role check; here we just
-- verify the function definition includes the length(trim()) >= 50 check.
do $$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_position_signoff';
  if v_src not like '%length(trim(p_decision_rationale)) < 50%' then
    raise exception 'h1a: rpc_position_signoff missing the 50-char rationale guard';
  end if;
  if v_src not like '%validity_anchor is null%' then
    raise exception 'h1a: rpc_position_signoff missing the null-anchor guard';
  end if;
  if v_src not like '%audit_log_event%' then
    raise exception 'h1a: rpc_position_signoff missing audit_log_event call';
  end if;
  raise notice 'h1a: rpc_position_signoff body contains all expected guards + audit';
end$$;

-- ─── 8. View shape ──────────────────────────────────────────────────
do $$
declare r record;
begin
  select * into r from public.v_current_evidence_base_position
   where predictor_type='gma';
  if r is null then raise exception 'h1a: view missing gma row'; end if;
  if r.primary_citation_key <> 'sackett-2022' then
    raise exception 'h1a: view gma primary_citation_key expected sackett-2022, got %', r.primary_citation_key;
  end if;
  if r.validity_status <> 'dev_stub' or r._dev_stub <> true then
    raise exception 'h1a: view gma should still be dev_stub, got status=%, _dev_stub=%',
      r.validity_status, r._dev_stub;
  end if;
  raise notice 'h1a: v_current_evidence_base_position shape ok';
end$$;
