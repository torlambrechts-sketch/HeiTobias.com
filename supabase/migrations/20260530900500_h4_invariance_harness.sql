-- H-4 — MGCFA Invariance Harness (Run 6 of H-1..H-10)
--
-- Vandenberg & Lance 2000 / Cheung & Rensvold 2002 / Chen 2007 /
-- Meade, Johnson & Braddy 2008. Measurement invariance hierarchy:
--   configural (same structure) → metric (same loadings)
--   → scalar (same intercepts) → strict (same residuals).
-- The MGCFA workflow runs a model at each level and compares fit
-- against the prior level. The Δ-CFI cutoff is contested:
--   * Cheung-Rensvold 2002: ΔCFI ≤ -.01
--   * Chen 2007: ΔCFI ≤ -.010 AND ΔRMSEA ≤ +.015
--   * Meade-Johnson-Braddy 2008: ΔCFI ≤ -.002 (stricter)
-- The platform must NOT pick a cutoff for the operator; it must
-- record which standard the operator/expert is judging against and
-- preserve the inputs for re-evaluation against any standard.
--
-- This run extends the existing invariance_* tables with:
--   * validity_status on both invariance_runs and invariance_results
--     (the existing tables had _dev_stub but no provenance enum).
--   * level made a strict enum (configural|metric|scalar|strict).
--   * cutoff_standard at run AND result level — which standard was
--     applied for the verdict. Stored as text-with-CHECK enum so
--     new standards can be added without enum migration.
--   * raw fit statistics (chi_square, df, chi_square_p) for re-
--     evaluation against future standards.
--   * passes_cutoff_by_standard jsonb on results — pre-computed
--     "would this pass under each known standard?" so a future
--     consumer can swap standards without re-running the engine.
--   * RPC rpc_invariance_run_signoff to promote a whole run +
--     all its results from dev_stub to validated under
--     modeling.signoff in the run's org.
--
-- INFRASTRUCTURE ONLY: no actual MGCFA fits computed in this run.
-- The R service that does the fit is out of scope (would require
-- installing lavaan / heavy R deps); operator-side setup is doc'd
-- separately. The DB happily accepts results when they arrive.

-- ─── 1. Extend invariance_runs ───────────────────────────────────────
alter table public.invariance_runs
  add column if not exists validity_status   public.validity_status not null default 'dev_stub',
  add column if not exists engine            text,
  add column if not exists engine_version    text,
  add column if not exists n_groups          int,
  add column if not exists cutoff_standard   text,
  add column if not exists signoff_actor_id  uuid references public.people(id),
  add column if not exists signoff_at        timestamptz,
  add column if not exists signoff_rationale text;

alter table public.invariance_runs
  drop constraint if exists ir_cutoff_standard_enum,
  drop constraint if exists ir_engine_enum,
  drop constraint if exists ir_signoff_rationale_len,
  drop constraint if exists ir_validated_requires_signoff;

alter table public.invariance_runs
  add constraint ir_cutoff_standard_enum check (
    cutoff_standard is null or cutoff_standard in (
      'cheung-rensvold-2002', 'chen-2007', 'meade-2008', 'custom')),
  add constraint ir_engine_enum check (
    engine is null or engine in ('lavaan-r','mplus','onyx','sem-py','custom')),
  add constraint ir_signoff_rationale_len check (
    signoff_rationale is null or length(signoff_rationale) >= 100),
  add constraint ir_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and engine is not null
      and cutoff_standard is not null
      and signoff_actor_id is not null
      and signoff_at is not null
      and signoff_rationale is not null
      and length(signoff_rationale) >= 100
    ));

create index if not exists ir_status_idx on public.invariance_runs(validity_status);

-- ─── 2. Extend invariance_results ────────────────────────────────────
alter table public.invariance_results
  add column if not exists validity_status            public.validity_status not null default 'dev_stub',
  add column if not exists chi_square                 numeric,
  add column if not exists df                         int,
  add column if not exists chi_square_p               numeric,
  add column if not exists cutoff_standard_used       text,
  add column if not exists passes_cutoff_by_standard  jsonb,
  add column if not exists configural_baseline_cfi    numeric,
  add column if not exists configural_baseline_rmsea  numeric;

alter table public.invariance_results
  drop constraint if exists irs_level_enum,
  drop constraint if exists irs_verdict_enum,
  drop constraint if exists irs_cfi_in_unit,
  drop constraint if exists irs_rmsea_in_unit,
  drop constraint if exists irs_srmr_in_unit;

alter table public.invariance_results
  add constraint irs_level_enum check (
    level in ('configural','metric','scalar','strict','residual')),
  add constraint irs_verdict_enum check (
    invariance_verdict_by_expert is null
    or invariance_verdict_by_expert in ('established','partial','rejected','inconclusive')),
  add constraint irs_cfi_in_unit check (
    cfi is null or (cfi >= 0 and cfi <= 1)),
  add constraint irs_rmsea_in_unit check (
    rmsea is null or (rmsea >= 0 and rmsea <= 1)),
  add constraint irs_srmr_in_unit check (
    srmr is null or (srmr >= 0 and srmr <= 1));

create index if not exists irs_status_idx on public.invariance_results(validity_status);

-- ─── 3. Helper: would this Δ-CFI pass each known standard? ──────────
-- Pure utility, used by ingestion to populate passes_cutoff_by_standard.
-- Returns jsonb {cheung-rensvold-2002: bool|null, chen-2007: bool|null,
-- meade-2008: bool|null}.
create or replace function public.invariance_evaluate_cutoffs(
  p_delta_cfi   numeric,
  p_delta_rmsea numeric
) returns jsonb language plpgsql immutable set search_path = '' as $$
declare v jsonb := '{}'::jsonb;
begin
  if p_delta_cfi is not null then
    v := v || jsonb_build_object(
      'cheung-rensvold-2002', p_delta_cfi >= -0.010,
      'meade-2008',            p_delta_cfi >= -0.002
    );
    if p_delta_rmsea is not null then
      v := v || jsonb_build_object(
        'chen-2007',
        (p_delta_cfi >= -0.010 and p_delta_rmsea <= 0.015)
      );
    end if;
  end if;
  return v;
end;
$$;

revoke all on function public.invariance_evaluate_cutoffs(numeric, numeric) from public;
grant execute on function public.invariance_evaluate_cutoffs(numeric, numeric) to authenticated, service_role;

comment on function public.invariance_evaluate_cutoffs(numeric, numeric) is
  'Returns a jsonb map of {standard_name: pass?} for the three published Δ-CFI/Δ-RMSEA cutoffs. Pre-computed on each result row so verdicts can be re-evaluated against any standard without re-running the engine.';

-- ─── 4. Run sign-off RPC ────────────────────────────────────────────
create or replace function public.rpc_invariance_run_signoff(
  p_run_id             uuid,
  p_decision_rationale text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_caller_person_id uuid;
  v_row              public.invariance_runs%rowtype;
  v_n_results        int;
  v_n_with_verdict   int;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 100 then
    raise exception 'rationale must be at least 100 characters' using errcode='22023';
  end if;

  select * into v_row from public.invariance_runs where id = p_run_id for update;
  if not found then
    raise exception 'invariance_run % not found', p_run_id using errcode='P0002';
  end if;
  if not public.has_permission(v_row.org_id, 'modeling.signoff') then
    raise exception 'denied: modeling.signoff required in org %', v_row.org_id using errcode='42501';
  end if;
  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;
  if v_row.engine is null then
    raise exception 'cannot sign off run without engine metadata' using errcode='22023';
  end if;
  if v_row.cutoff_standard is null then
    raise exception 'cannot sign off run without cutoff_standard' using errcode='22023';
  end if;

  -- Every result row must have an expert verdict before run sign-off.
  select count(*), count(*) filter (where invariance_verdict_by_expert is not null)
    into v_n_results, v_n_with_verdict
    from public.invariance_results where run_id = p_run_id;
  if v_n_results = 0 then
    raise exception 'cannot sign off run with 0 result rows' using errcode='22023';
  end if;
  if v_n_with_verdict <> v_n_results then
    raise exception 'cannot sign off run: only % of % result rows have an expert verdict',
      v_n_with_verdict, v_n_results using errcode='22023';
  end if;

  update public.invariance_runs
     set validity_status='validated', _dev_stub=false,
         signoff_actor_id=v_caller_person_id, signoff_at=now(),
         signoff_rationale=p_decision_rationale
   where id = p_run_id;

  update public.invariance_results
     set validity_status='validated', _dev_stub=false
   where run_id = p_run_id;

  perform public.audit_log_event(
    v_row.org_id, 'invariance_run.signoff', 'invariance_run', p_run_id,
    to_jsonb(v_row),
    jsonb_build_object('signoff_actor_id', v_caller_person_id, 'signoff_at', now(),
      'rationale_length', length(p_decision_rationale),
      'engine', v_row.engine, 'cutoff_standard', v_row.cutoff_standard,
      'n_results', v_n_results), null);

  return jsonb_build_object('ok', true, 'run_id', p_run_id,
    'validity_status', 'validated', 'n_results_validated', v_n_results,
    'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_invariance_run_signoff(uuid, text) from public;
grant execute on function public.rpc_invariance_run_signoff(uuid, text) to authenticated, service_role;
