-- H-9 + H-10 EU AI Act compliance + legal sign-off discipline tests

do $$
begin
  -- legal.signoff permission seeded
  if not exists (select 1 from public.rbac_permissions where key='legal.signoff')
    then raise exception 'h9: legal.signoff permission missing'; end if;

  -- compliance_artifacts extensions
  if not exists (select 1 from information_schema.columns where table_schema='public'
                  and table_name='compliance_artifacts' and column_name='legal_signoff_actor_id')
    then raise exception 'h9: compliance_artifacts.legal_signoff_actor_id missing'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public'
                  and table_name='compliance_artifacts' and column_name='annex_iii_high_risk_class')
    then raise exception 'h9: compliance_artifacts.annex_iii_high_risk_class missing'; end if;
  if not exists (select 1 from pg_constraint where conname='ca_validated_requires_dual_signoff')
    then raise exception 'h9: dual-signoff CHECK missing'; end if;

  -- vendor_acknowledgments table
  if not exists (select 1 from information_schema.tables where table_schema='public'
                  and table_name='vendor_acknowledgments')
    then raise exception 'h10: vendor_acknowledgments missing'; end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_compliance_artifact_signoff_modeling')
    then raise exception 'h9: rpc_compliance_artifact_signoff_modeling missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_compliance_artifact_signoff_legal')
    then raise exception 'h9: rpc_compliance_artifact_signoff_legal missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='rpc_vendor_acknowledgment_signoff')
    then raise exception 'h10: rpc_vendor_acknowledgment_signoff missing'; end if;

  raise notice 'h9/h10: schema + RPC presence ok';
end$$;

do $$
declare v int;
begin
  select count(*) into v from public.compliance_artifacts where validity_status='validated';
  if v <> 0 then raise exception 'h9: % validated artifacts', v; end if;
  select count(*) into v from public.vendor_acknowledgments where validity_status='validated';
  if v <> 0 then raise exception 'h10: % validated vendor_acks', v; end if;
  raise notice 'h9/h10: 0 validated rows';
end$$;

-- Dual-signoff CHECK
do $$
declare v_org uuid; v_artifact_id uuid; v_person uuid;
begin
  select id into v_org from public.organizations limit 1;
  select id into v_person from public.people limit 1;
  if v_org is null then raise notice 'h9: no fixtures'; return; end if;

  insert into public.compliance_artifacts (org_id, kind, key, version, scope_json)
  values (v_org, 'annex_iv_technical_doc', 'h9-test', 'v0', '{}'::jsonb)
  returning id into v_artifact_id;

  -- Validated requires BOTH signoffs → must fail with only modeling
  begin
    update public.compliance_artifacts
       set validity_status='validated', _dev_stub=false,
           modeling_signoff_actor_id=v_person, modeling_signoff_at=now(),
           modeling_signoff_rationale='rationale long enough to clear the 100-character minimum for compliance artifact modeling signoff rationale documentation'
     where id = v_artifact_id;
    raise exception 'h9: validated with only modeling signoff accepted';
  exception when check_violation then null;
  end;

  -- With both → succeeds
  update public.compliance_artifacts
     set validity_status='validated', _dev_stub=false,
         modeling_signoff_actor_id=v_person, modeling_signoff_at=now(),
         modeling_signoff_rationale='rationale long enough to clear the 100-character minimum for compliance artifact modeling signoff rationale documentation',
         legal_signoff_actor_id=v_person, legal_signoff_at=now(),
         legal_signoff_rationale='rationale long enough to clear the 100-character minimum for compliance artifact legal signoff rationale documentation'
   where id = v_artifact_id;

  delete from public.compliance_artifacts where id = v_artifact_id;
  raise notice 'h9: dual-signoff CHECK enforced';
end$$;

-- Vendor ack workday_precedent requirement
do $$
declare v_org uuid; v_ack_id uuid; v_person uuid;
begin
  select id into v_org from public.organizations limit 1;
  select id into v_person from public.people limit 1;
  if v_org is null then raise notice 'h10: no fixtures'; return; end if;

  insert into public.vendor_acknowledgments
    (org_id, vendor_name, vendor_role, acknowledgment_text, workday_precedent_acknowledged)
  values (v_org, 'h10-test-vendor', 'assessment_provider',
          'we ack vendor obligations under emerging case law for vendor liability', false)
  returning id into v_ack_id;

  -- Validated requires workday_precedent_acknowledged=true → must fail
  begin
    update public.vendor_acknowledgments
       set validity_status='validated', _dev_stub=false,
           signoff_actor_id=v_person, signoff_at=now(),
           signoff_rationale='rationale long enough to clear the 100-character minimum for vendor acknowledgment legal signoff rationale documentation'
     where id = v_ack_id;
    raise exception 'h10: validated without Workday ack accepted';
  exception when check_violation then null;
  end;

  -- Set ack=true, then validate succeeds
  update public.vendor_acknowledgments set workday_precedent_acknowledged=true where id=v_ack_id;
  update public.vendor_acknowledgments
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_person, signoff_at=now(),
         signoff_rationale='rationale long enough to clear the 100-character minimum for vendor acknowledgment legal signoff rationale documentation'
   where id = v_ack_id;

  delete from public.vendor_acknowledgments where id = v_ack_id;
  raise notice 'h10: workday_precedent gate enforced';
end$$;

-- Partial unique: one current vendor ack per (org, vendor)
do $$
declare v_org uuid; v_id1 uuid; v_id2 uuid;
begin
  select id into v_org from public.organizations limit 1;
  if v_org is null then raise notice 'h10: no org'; return; end if;
  insert into public.vendor_acknowledgments
    (org_id, vendor_name, vendor_role, acknowledgment_text)
  values (v_org, 'h10-uniq-vendor', 'assessment_provider', 'acknowledgment text long enough to clear the 50-char min length bar')
  returning id into v_id1;

  begin
    insert into public.vendor_acknowledgments
      (org_id, vendor_name, vendor_role, acknowledgment_text)
    values (v_org, 'h10-uniq-vendor', 'assessment_provider',
            'second ack text long enough to clear the 50-char min length bar testing');
    raise exception 'h10: partial unique accepted dup current ack';
  exception when unique_violation then null;
  end;
  delete from public.vendor_acknowledgments where id = v_id1;
  raise notice 'h10: partial unique enforces one current per (org, vendor)';
end$$;
