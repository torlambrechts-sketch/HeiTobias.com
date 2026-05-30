-- H-1c — Curvilinear Trait-Target Band Engine (Run 3 of H-1..H-10)
--
-- Le 2011 / Pierce & Aguinis 2013 / Grant 2013 show that some traits
-- (especially Conscientiousness, Emotional Stability, Extraversion in
-- sales) have inverted-U relations to performance — fit drops off on
-- BOTH sides of an inflection point. The current personality module
-- supports three directions: higher_better | lower_better | target_band,
-- all monotonic / piecewise-linear; none expresses an inverted-U peak.
--
-- This run:
--   1. Extends `personality_trait_direction` enum with `inverted_u`.
--   2. Extends `personality_role_template_traits` with inverted-U
--      params (inflection_point, half_width), a direction rationale,
--      and per-row dev_stub + signoff fields (the parent template
--      already has dev_stub, but a fine-grained signoff per (template,
--      trait_key) is what an I/O psychologist actually does).
--   3. Adds CHECK direction='inverted_u' => params + ≥50-char rationale.
--   4. Adds load-bearing CHECK per-row validated => signed off
--      (mirrors evidence_base_positions discipline from Run 1).
--   5. Ships generic `public.compute_trait_band_fit_v1(...) RETURNS
--      numeric` — severity in [0, 1]; 0=perfect fit, 1=worst.
--      Personality compute is the first consumer; future modules
--      (cognitive, values) call the same helper for engine consistency.
--   6. Adds `rpc_trait_direction_signoff(trait_row_id, rationale)` —
--      promotes a per-trait row from dev_stub to validated under the
--      role.signoff permission (org-scoped).
--
-- Cross-engine: src/lib/personality/scoring.ts gains a mirror impl of
-- compute_trait_band_fit_v1 + tests against a shared fixture file.
--
-- IMPORTANT: All `direction = 'inverted_u'` comparisons in CHECK
-- constraints cast through ::text to avoid the Postgres restriction
-- "unsafe use of new enum value" within the same transaction that
-- added it. This keeps the migration single-file.

alter type public.personality_trait_direction add value if not exists 'inverted_u';

alter table public.personality_role_template_traits
  add column if not exists inflection_point integer,
  add column if not exists half_width        integer,
  add column if not exists direction_rationale text,
  add column if not exists direction_signoff_actor_id uuid references public.people(id),
  add column if not exists direction_signoff_at       timestamptz,
  add column if not exists direction_signoff_rationale text,
  add column if not exists validity_status public.validity_status not null default 'dev_stub',
  add column if not exists _dev_stub        boolean not null default true;

-- ─── Constraints (text-cast to avoid the same-tx enum-value restriction) ─
alter table public.personality_role_template_traits
  drop constraint if exists prtt_inverted_u_requires_params,
  drop constraint if exists prtt_inverted_u_rationale_len,
  drop constraint if exists prtt_inflection_in_unit,
  drop constraint if exists prtt_halfwidth_in_unit,
  drop constraint if exists prtt_signoff_rationale_len,
  drop constraint if exists prtt_validated_requires_signoff;

alter table public.personality_role_template_traits
  add constraint prtt_inflection_in_unit check (
    inflection_point is null or (inflection_point between 0 and 99)
  ),
  add constraint prtt_halfwidth_in_unit check (
    half_width is null or (half_width between 1 and 99)
  ),
  add constraint prtt_inverted_u_requires_params check (
    direction::text <> 'inverted_u'
    or (
      inflection_point is not null
      and half_width is not null
      and direction_rationale is not null
      and length(direction_rationale) >= 50
    )
  ),
  add constraint prtt_signoff_rationale_len check (
    direction_signoff_rationale is null or length(direction_signoff_rationale) >= 50
  ),
  add constraint prtt_validated_requires_signoff check (
    validity_status <> 'validated' or (
      coalesce(_dev_stub, true) = false
      and direction_signoff_actor_id is not null
      and direction_signoff_at is not null
      and direction_signoff_rationale is not null
      and length(direction_signoff_rationale) >= 50
    )
  );

create index if not exists prtt_status_idx on public.personality_role_template_traits(validity_status);

-- chk_template_trait_shape pre-dates the inverted_u direction; it
-- requires band_low/band_high for any scored trait. inverted_u traits
-- use inflection_point/half_width instead — expand the constraint to
-- accept either shape.
alter table public.personality_role_template_traits
  drop constraint if exists chk_template_trait_shape;

alter table public.personality_role_template_traits
  add constraint chk_template_trait_shape check (
    -- (a) flag-only trait
    (review_flag = true and weight = 0 and flag_threshold is not null)
    or
    -- (b) scored monotonic trait
    (review_flag = false and weight > 0
       and direction::text in ('higher_better','lower_better','target_band')
       and band_low is not null and band_high is not null and band_low <= band_high)
    or
    -- (c) scored inverted_u trait
    (review_flag = false and weight > 0
       and direction::text = 'inverted_u'
       and inflection_point is not null and half_width is not null)
  );

-- ─── Generic band-fit function ───────────────────────────────────────
-- Returns severity in [0, 1]:
--   0 = perfect fit (inside band, at peak, above threshold etc.)
--   1 = worst fit (very far outside the band / very far from peak)
--
-- Parameters:
--   score        : the person's percentile score, 0..99 (or NULL → NULL out)
--   direction    : 'higher_better' | 'lower_better' | 'target_band' | 'inverted_u'
--   band_low     : low end of band (0..99) — required for all directions except inverted_u
--   band_high    : high end of band (0..99) — same
--   inflection_point : ONLY for inverted_u: the peak position 0..99
--   half_width   : ONLY for inverted_u: the percentile distance from peak
--                  at which severity reaches 1.0 (1..99)
--
-- Reference window for severity scaling on the monotonic forms is the
-- max possible distance: 99 (so e.g. score=0 with direction=higher_better
-- and band_low=50 yields severity = 50/99 ≈ 0.505).
create or replace function public.compute_trait_band_fit_v1(
  p_score             integer,
  p_direction         text,
  p_band_low          integer,
  p_band_high         integer,
  p_inflection_point  integer default null,
  p_half_width        integer default null
) returns numeric
language plpgsql immutable
set search_path = ''
as $$
declare
  v_x    integer := p_score;
  v_dist numeric;
  v_sev  numeric;
begin
  if v_x is null then return null; end if;
  if v_x < 0 or v_x > 99 then
    raise exception 'score % out of [0,99]', v_x using errcode='22023';
  end if;

  if p_direction = 'higher_better' then
    if p_band_low is null then
      raise exception 'higher_better requires band_low' using errcode='22023';
    end if;
    v_dist := greatest(0, p_band_low - v_x);
    v_sev  := least(1.0, v_dist / 99.0);
    return v_sev;

  elsif p_direction = 'lower_better' then
    if p_band_high is null then
      raise exception 'lower_better requires band_high' using errcode='22023';
    end if;
    v_dist := greatest(0, v_x - p_band_high);
    v_sev  := least(1.0, v_dist / 99.0);
    return v_sev;

  elsif p_direction = 'target_band' then
    if p_band_low is null or p_band_high is null then
      raise exception 'target_band requires band_low and band_high' using errcode='22023';
    end if;
    if v_x >= p_band_low and v_x <= p_band_high then
      return 0.0;
    end if;
    v_dist := case
      when v_x < p_band_low  then p_band_low  - v_x
      else                         v_x - p_band_high
    end;
    v_sev := least(1.0, v_dist::numeric / 99.0);
    return v_sev;

  elsif p_direction = 'inverted_u' then
    if p_inflection_point is null or p_half_width is null then
      raise exception 'inverted_u requires inflection_point and half_width' using errcode='22023';
    end if;
    v_dist := abs(v_x - p_inflection_point);
    -- Linear ramp: severity = min(1, distance / half_width)
    -- (Half_width is the percentile distance at which severity = 1.0.)
    v_sev := least(1.0, v_dist::numeric / p_half_width::numeric);
    return v_sev;

  else
    raise exception 'unknown direction: %', p_direction using errcode='22023';
  end if;
end;
$$;

revoke all on function public.compute_trait_band_fit_v1(integer, text, integer, integer, integer, integer) from public;
grant execute on function public.compute_trait_band_fit_v1(integer, text, integer, integer, integer, integer)
  to authenticated, service_role;

comment on function public.compute_trait_band_fit_v1(integer, text, integer, integer, integer, integer) is
  'Generic trait-band fit. Returns severity in [0,1] (0=perfect, 1=worst). Mirrored by src/lib/personality/scoring.ts; cross-engine tests assert identical output.';

-- ─── RPC: per-trait sign-off ─────────────────────────────────────────
create or replace function public.rpc_trait_direction_signoff(
  p_trait_row_id       bigint,
  p_decision_rationale text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller_person_id uuid;
  v_row              public.personality_role_template_traits%rowtype;
  v_template_org_id  uuid;
begin
  if p_decision_rationale is null or length(trim(p_decision_rationale)) < 50 then
    raise exception 'rationale must be at least 50 characters' using errcode='22023';
  end if;
  select * into v_row from public.personality_role_template_traits where id = p_trait_row_id for update;
  if not found then
    raise exception 'trait row % not found', p_trait_row_id using errcode='P0002';
  end if;

  -- org scope: trait's org_id may be null (global template). For global,
  -- require global modeling.signoff. For org-scoped, require role.signoff
  -- in that org.
  if v_row.org_id is null then
    if not public.has_global_permission('modeling.signoff') then
      raise exception 'denied: modeling.signoff required (global template)' using errcode='42501';
    end if;
  else
    if not public.has_permission(v_row.org_id, 'role.signoff') then
      raise exception 'denied: role.signoff required in org %', v_row.org_id using errcode='42501';
    end if;
  end if;

  select pp.id into v_caller_person_id from public.people pp where pp.auth_user_id=(select auth.uid());
  if v_caller_person_id is null then
    raise exception 'caller has no person identity' using errcode='42501';
  end if;

  update public.personality_role_template_traits
     set validity_status='validated', _dev_stub=false,
         direction_signoff_actor_id=v_caller_person_id,
         direction_signoff_at=now(),
         direction_signoff_rationale=p_decision_rationale,
         updated_at=now()
   where id = p_trait_row_id;

  perform public.audit_log_event(
    v_row.org_id, 'trait_direction.signoff', 'personality_role_template_trait', null,
    to_jsonb(v_row),
    jsonb_build_object(
      'trait_row_id', p_trait_row_id,
      'role_key', v_row.role_key,
      'trait_key', v_row.trait_key,
      'direction', v_row.direction,
      'signoff_actor_id', v_caller_person_id,
      'rationale_length', length(p_decision_rationale)
    ),
    null);

  return jsonb_build_object('ok', true, 'trait_row_id', p_trait_row_id,
    'validity_status','validated', 'signoff_actor_id', v_caller_person_id);
end;
$$;

revoke all on function public.rpc_trait_direction_signoff(bigint, text) from public;
grant execute on function public.rpc_trait_direction_signoff(bigint, text) to authenticated, service_role;

-- Existing dev-stub seam guard: no validated rows in this table from
-- this migration. (None should exist anyway; the column default is
-- dev_stub and the seed migration runs earlier.)
do $$
declare v_count int;
begin
  select count(*) into v_count from public.personality_role_template_traits where validity_status='validated';
  if v_count > 0 then
    raise warning 'h1c: % validated trait rows pre-existing — investigate', v_count;
  end if;
end$$;
