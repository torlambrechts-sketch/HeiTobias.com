-- H-1c — curvilinear band schema discipline tests.

-- Schema presence
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='compute_trait_band_fit_v1'
  ) then raise exception 'h1c: compute_trait_band_fit_v1 missing'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='rpc_trait_direction_signoff'
  ) then raise exception 'h1c: rpc_trait_direction_signoff missing'; end if;

  if not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='personality_role_template_traits'
       and column_name='inflection_point'
  ) then raise exception 'h1c: inflection_point column missing'; end if;

  if not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='personality_role_template_traits'
       and column_name='validity_status'
  ) then raise exception 'h1c: validity_status column missing'; end if;

  if not exists (
    select 1 from pg_constraint c
     join pg_class t on t.oid=c.conrelid
     where t.relname='personality_role_template_traits'
       and c.conname='prtt_validated_requires_signoff'
  ) then raise exception 'h1c: prtt_validated_requires_signoff CHECK missing'; end if;

  -- New enum value present
  if not exists (
    select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid
     where t.typname='personality_trait_direction' and e.enumlabel='inverted_u'
  ) then raise exception 'h1c: inverted_u enum value missing'; end if;

  raise notice 'h1c: schema presence ok';
end$$;

-- Discipline: no validated trait rows in fixtures
do $$
declare v_validated int;
begin
  select count(*) into v_validated
    from public.personality_role_template_traits
   where validity_status='validated';
  if v_validated <> 0 then
    raise exception 'h1c: % validated trait rows — DISCIPLINE BREACH', v_validated;
  end if;
  raise notice 'h1c: dev_stub discipline preserved (0 validated rows)';
end$$;

-- CHECK constraints (rolled-back tx)
do $$
declare v_template uuid; v_role_key text; v_trait_key text;
begin
  select id, role_key into v_template, v_role_key from public.personality_role_templates limit 1;
  select pt.trait_key into v_trait_key from public.personality_traits pt
   where not exists (select 1 from public.personality_role_template_traits prtt
                      where prtt.template_id=v_template and prtt.trait_key=pt.trait_key)
   limit 1;
  if v_template is null or v_trait_key is null then
    raise notice 'h1c: no test prerequisites; skipping'; return;
  end if;

  -- inverted_u WITHOUT params: must fail
  begin
    insert into public.personality_role_template_traits
      (template_id, role_key, trait_key, direction, weight, review_flag)
    values (v_template, v_role_key, v_trait_key,
            'inverted_u'::public.personality_trait_direction, 0.5, false);
    raise exception 'h1c: inverted_u w/o params accepted (CHECK breach)';
  exception when check_violation then null;
  end;

  -- inverted_u WITH params: must succeed (then we test signoff)
  insert into public.personality_role_template_traits
    (template_id, role_key, trait_key, direction, weight, review_flag,
     inflection_point, half_width, direction_rationale)
  values (v_template, v_role_key, v_trait_key,
          'inverted_u'::public.personality_trait_direction, 0.5, false,
          50, 20,
          'Per Le 2011 / Pierce-Aguinis 2013 / Grant 2013, this trait shows inverted-U; pending I/O sign-off for our population.');

  -- Validated without signoff: must fail
  begin
    update public.personality_role_template_traits
       set validity_status='validated', _dev_stub=false
     where template_id=v_template and trait_key=v_trait_key;
    raise exception 'h1c: validated w/o signoff accepted (CHECK breach)';
  exception when check_violation then null;
  end;

  -- Cleanup (we're in tx that will rollback, but be tidy)
  delete from public.personality_role_template_traits
   where template_id=v_template and trait_key=v_trait_key;

  raise notice 'h1c: CHECK + dev_stub seam discipline ok';
end$$;
