-- H-7 — Norm Sample Registry + Continuous Norming (Run 9 of H-1..H-10)
--
-- Existing norm_samples + norm_percentiles capture raw normative
-- distributions per (instrument, country, language). This run adds:
--   * continuous-norming metadata (Lenhard & Lenhard 2019: parametric
--     models that smooth across age + sex + region, addressing the
--     small-cell problem of pure tabulated norms)
--   * representativeness metadata + Nordic-adaptation linkage
--   * sample sign-off RPC + reuse-readiness check
--
-- Plus a NEW table `norm_sample_adaptations` linking norm_samples to
-- the published adaptation citation (e.g. our Norwegian BFI-2 sample
-- claims to inherit from Føllesdal & Soto 2022). This is the audit
-- trail for "where did these norms come from?"

-- ─── 1. Extend norm_samples ─────────────────────────────────────────
alter table public.norm_samples
  add column if not exists adapted_from_citation_id uuid references public.citations(id),
  add column if not exists representativeness_notes text,
  add column if not exists representativeness_assessed_at timestamptz,
  add column if not exists is_continuous_norming   boolean not null default false,
  add column if not exists continuous_norming_method text,
  add column if not exists continuous_norming_smoothing_params jsonb,
  add column if not exists signoff_actor_id        uuid references public.people(id),
  add column if not exists signoff_at              timestamptz,
  add column if not exists signoff_rationale       text;

alter table public.norm_samples
  drop constraint if exists ns_cnm_enum,
  drop constraint if exists ns_signoff_rationale_len,
  drop constraint if exists ns_validated_requires_signoff;

alter table public.norm_samples
  add constraint ns_cnm_enum check (
    continuous_norming_method is null or continuous_norming_method in (
      'lenhard-2019','rasch-irt','polynomial','spline','kernel','none')),
  add constraint ns_signoff_rationale_len check (
    signoff_rationale is null or length(signoff_rationale) >= 100),
  add constraint ns_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    ));

create index if not exists ns_status_idx on public.norm_samples(validity_status);
create index if not exists ns_adapted_idx on public.norm_samples(adapted_from_citation_id) where adapted_from_citation_id is not null;

-- ─── 2. norm_percentiles gets validity_status ───────────────────────
alter table public.norm_percentiles
  add column if not exists validity_status public.validity_status not null default 'dev_stub';

create index if not exists np_status_idx on public.norm_percentiles(validity_status);

-- ─── 3. Adaptation linkage table ────────────────────────────────────
-- A norm sample may inherit methodology + items from MULTIPLE
-- published adaptations (e.g. a Nordic pan-region norm draws on
-- Føllesdal-Soto 2022 + Vedel 2021 + Zakrisson 2025). Many-to-many.
create table if not exists public.norm_sample_adaptations (
  sample_id    uuid not null references public.norm_samples(id) on delete cascade,
  citation_id  uuid not null references public.citations(id),
  role         text not null default 'methodology_source',
  note         text,
  primary key (sample_id, citation_id),
  constraint nsa_role_enum check (
    role in ('methodology_source','item_set_source','sample_pool_source','translation_source','validation_partner'))
);

create index if not exists nsa_citation_idx on public.norm_sample_adaptations(citation_id);

-- ─── 4. Helper: norm sample reuse-readiness check ──────────────────
-- A consumer (e.g. personality_compute_scores) calling for norms can
-- query this function: are these norms in good enough shape to use?
-- Returns jsonb {ready: bool, reasons: [text]}.
create or replace function public.norm_sample_reuse_ready(p_sample_id uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_row public.norm_samples%rowtype;
  v_reasons text[] := array[]::text[];
begin
  select * into v_row from public.norm_samples where id = p_sample_id;
  if not found then
    return jsonb_build_object('ready', false, 'reasons', array['sample_not_found']);
  end if;
  if v_row.validity_status <> 'validated' then
    v_reasons := v_reasons || ('not_validated:'||v_row.validity_status::text);
  end if;
  if v_row.sample_n is null or v_row.sample_n < 100 then
    v_reasons := v_reasons || 'sample_n_below_100';
  end if;
  if v_row.country_code is null then
    v_reasons := v_reasons || 'country_code_missing';
  end if;
  if v_row.representativeness_notes is null then
    v_reasons := v_reasons || 'representativeness_not_assessed';
  end if;
  return jsonb_build_object(
    'ready',   array_length(v_reasons, 1) is null,
    'reasons', v_reasons
  );
end;
$$;

revoke all on function public.norm_sample_reuse_ready(uuid) from public;
grant execute on function public.norm_sample_reuse_ready(uuid) to authenticated, service_role;

comment on function public.norm_sample_reuse_ready(uuid) is
  'Returns jsonb {ready: bool, reasons: [text]} — quick gate for "can the platform use these norms operationally?". Consumers (compute RPCs, fit calculations) should refuse to consume norms with ready=false unless explicitly opted in.';

-- ─── 5. Sample sign-off RPC ─────────────────────────────────────────
create or replace function public.rpc_norm_sample_signoff(
  p_sample_id          uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_caller_person_id uuid;
  v_row              public.norm_samples%rowtype;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;
  select * into v_row from public.norm_samples where id = p_sample_id for update;
  if not found then
    raise exception 'norm_sample % not found', p_sample_id using errcode='P0002';
  end if;
  -- norm samples may be global (org_id null) or per-org. Global needs
  -- global signoff; per-org needs org-scoped.
  if v_row.org_id is null then
    if not public.has_global_permission('modeling.signoff') then
      raise exception 'denied: modeling.signoff required (global norm sample)' using errcode='42501';
    end if;
  else
    if not public.has_permission(v_row.org_id, 'modeling.signoff') then
      raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
    end if;
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;
  if v_row.sample_n is null or v_row.sample_n < 100 then
    raise exception 'cannot sign off sample with N=% (<100 too small)', v_row.sample_n using errcode='22023';
  end if;
  if v_row.representativeness_notes is null then
    raise exception 'cannot sign off sample without representativeness_notes' using errcode='22023';
  end if;

  update public.norm_samples
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale, updated_at=now()
   where id = p_sample_id;
  update public.norm_percentiles
     set validity_status='validated'
   where sample_id = p_sample_id;
  -- ALSO clear _dev_stub on percentiles
  update public.norm_percentiles
     set _dev_stub=false
   where sample_id = p_sample_id;

  perform public.audit_log_event(
    v_row.org_id, 'norm_sample.signoff', 'norm_sample', p_sample_id, to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'sample_n', v_row.sample_n, 'country_code', v_row.country_code,
      'is_continuous_norming', v_row.is_continuous_norming), null);

  return jsonb_build_object('ok', true, 'sample_id', p_sample_id,
    'validity_status', 'validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_norm_sample_signoff(uuid, text) from public;
grant execute on function public.rpc_norm_sample_signoff(uuid, text) to authenticated, service_role;

-- ─── 6. RLS for new table ───────────────────────────────────────────
alter table public.norm_sample_adaptations enable row level security;
alter table public.norm_sample_adaptations force  row level security;

drop policy if exists nsa_select_authenticated on public.norm_sample_adaptations;
create policy nsa_select_authenticated on public.norm_sample_adaptations
  for select using ((select auth.uid()) is not null);

drop policy if exists nsa_write_modeling on public.norm_sample_adaptations;
create policy nsa_write_modeling on public.norm_sample_adaptations
  for all using (public.has_global_permission('modeling.write'))
          with check (public.has_global_permission('modeling.write'));

grant select on public.norm_sample_adaptations to authenticated;
grant insert, update, delete on public.norm_sample_adaptations to authenticated;
