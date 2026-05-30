-- H-2 Trait Activation Theory — discipline tests
do $$
begin
  if not exists (select 1 from pg_type where typname='trait_activation_level')
    then raise exception 'h2: trait_activation_level enum missing'; end if;
  if not exists (select 1 from pg_type where typname='trait_activation_category')
    then raise exception 'h2: trait_activation_category enum missing'; end if;
  if not exists (select 1 from information_schema.tables
                  where table_schema='public' and table_name='trait_activation_factor_catalog')
    then raise exception 'h2: trait_activation_factor_catalog missing'; end if;
  if not exists (select 1 from information_schema.tables
                  where table_schema='public' and table_name='role_context_factors')
    then raise exception 'h2: role_context_factors missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_factor_catalog_signoff')
    then raise exception 'h2: rpc_factor_catalog_signoff missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_role_context_signoff')
    then raise exception 'h2: rpc_role_context_signoff missing'; end if;
  raise notice 'h2: schema/RPC presence ok';
end$$;

do $$
declare v_n int;
begin
  select count(*) into v_n from public.trait_activation_factor_catalog;
  if v_n < 11 then
    raise exception 'h2: expected >=11 seeded factors (Tett-Burnett taxonomy), got %', v_n; end if;
  select count(*) into v_n from public.trait_activation_factor_catalog where validity_status='validated';
  if v_n <> 0 then raise exception 'h2: % validated factors — DISCIPLINE BREACH', v_n; end if;
  select count(*) into v_n from public.role_context_factors where validity_status='validated';
  if v_n <> 0 then raise exception 'h2: % validated role_context rows — DISCIPLINE BREACH', v_n; end if;
  raise notice 'h2: seed + dev_stub discipline ok';
end$$;

-- CHECK + FK probes
do $$
declare v_org uuid; v_role uuid;
begin
  select id into v_org  from public.organizations limit 1;
  select id into v_role from public.roles_catalog where org_id is not null limit 1;
  if v_role is null then raise notice 'h2: no role to probe; skipping'; return; end if;

  -- (a) intensity out of range
  begin
    insert into public.role_context_factors (org_id, role_id, factor_key, intensity, rationale)
    values (v_org, v_role, 'task_ambiguity', 7, 'rationale long enough to clear the 30-char minimum bar test');
    raise exception 'h2: intensity 7 accepted';
  exception when check_violation then null;
  end;

  -- (b) intensity 0 rejected too
  begin
    insert into public.role_context_factors (org_id, role_id, factor_key, intensity, rationale)
    values (v_org, v_role, 'task_ambiguity', 0, 'rationale long enough to clear the 30-char minimum bar test');
    raise exception 'h2: intensity 0 accepted';
  exception when check_violation then null;
  end;

  -- (c) rationale too short
  begin
    insert into public.role_context_factors (org_id, role_id, factor_key, intensity, rationale)
    values (v_org, v_role, 'task_ambiguity', 3, 'short');
    raise exception 'h2: short rationale accepted';
  exception when check_violation then null;
  end;

  -- (d) unknown factor_key
  begin
    insert into public.role_context_factors (org_id, role_id, factor_key, intensity, rationale)
    values (v_org, v_role, 'unknown_factor_xyz', 3, 'rationale long enough to clear the 30-char minimum bar test');
    raise exception 'h2: unknown factor_key accepted';
  exception when foreign_key_violation then null;
  end;

  raise notice 'h2: CHECK + FK constraints fire';
end$$;

-- RPC source guards
do $$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_factor_catalog_signoff';
  if v_src not like '%has_global_permission(''modeling.signoff'')%' then
    raise exception 'h2: rpc_factor_catalog_signoff missing modeling.signoff gate'; end if;
  if v_src not like '%audit_log_event%' then
    raise exception 'h2: rpc_factor_catalog_signoff missing audit_log_event'; end if;

  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rpc_role_context_signoff';
  if v_src not like '%has_permission(v_org_id, ''role.signoff'')%' then
    raise exception 'h2: rpc_role_context_signoff missing role.signoff gate'; end if;
  raise notice 'h2: RPC source guards present';
end$$;
