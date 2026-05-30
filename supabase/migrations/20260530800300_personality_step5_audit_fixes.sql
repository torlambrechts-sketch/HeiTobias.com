-- Personality Module — Step 5: audit-driven fixes.
--
-- A senior-team review of Steps 1-4 caught five integrity / correctness
-- issues. This migration closes them. The fixes preserve the existing
-- semantics (global vs org-scoped templates, dev_stub discipline) but
-- repair the schema so the semantics are actually enforced.
--
-- FIX 1 — "global template = NULL org_id" was broken.
--   `primary key (role_key, org_id)` implicitly makes org_id NOT NULL,
--   so the seed migration's `org_id=null` rows could never insert. The
--   personality_role_templates table was effectively empty in any real
--   deployment.
--
-- FIX 2 — Orphan FK under MATCH SIMPLE semantics.
--   `foreign key (role_key, org_id) references templates(role_key, org_id)`
--   skips the check when org_id IS NULL (PostgreSQL MATCH SIMPLE default).
--   Audit probe confirmed: a template_traits row referencing a
--   non-existent (role_key, NULL) template inserted successfully.
--
-- FIX 3 — Compute RPC missed org-scoped templates.
--   The role-template loop filtered `where org_id is null`, which (once
--   FIX 1 makes globals possible) still misses per-org templates that a
--   recruiter might have cloned. The right filter is `org_id is null OR
--   org_id = v_session.org_id`.
--
-- FIX 4 — Dead service_role bypass in compute auth check.
--   `current_user = 'service_role'` inside a SECDEF function returns the
--   FUNCTION OWNER (postgres), never the caller. The whole branch was
--   unreachable. Switch to `session_user` + `pg_has_role` so the bypass
--   actually works for the migration / operator roles.
--
-- FIX 5 — assessment_instruments unique-with-null lets duplicates in.
--   `unique (org_id, key, version)` treats each NULL org_id as distinct,
--   so two `(NULL, 'personality_v1', '1.0.0')` rows could coexist and
--   the compute RPC's lookup would pick one nondeterministically. Add a
--   partial-unique index to enforce singleness for global instruments.
--
-- These fixes use partial unique indexes + a surrogate id on templates,
-- so the existing (role_key, org_id) columns remain readable for code
-- that already joins on them. The FK on template_traits switches to the
-- surrogate, closing the MATCH SIMPLE hole.

-- ─── FIX 1 + 2 — Surrogate id PK + switch template_traits FK ────────
-- Drop the OLD FK on template_traits FIRST (it depends on the old PK
-- index, so Postgres refuses to drop the PK while the FK is in place).
-- Then drop the PK, add surrogate id + partial-unique indexes, then
-- repoint the FK at the new surrogate.

alter table public.personality_role_template_traits
  drop constraint if exists personality_role_template_traits_role_key_org_id_fkey;
alter table public.personality_role_template_traits
  drop constraint if exists personality_role_template_traits_role_key_org_id_trait_key_key;

alter table public.personality_role_templates
  drop constraint if exists personality_role_templates_pkey;

alter table public.personality_role_templates
  add column if not exists id uuid not null default extensions.gen_random_uuid();

-- backfill in case any rows already exist (shouldn't on a clean DB)
update public.personality_role_templates set id = extensions.gen_random_uuid() where id is null;

alter table public.personality_role_templates
  add constraint personality_role_templates_pkey primary key (id);

-- Dropping the OLD PK does NOT remove the inferred NOT NULL on the
-- columns it covered; drop it explicitly so org_id can actually be NULL
-- (the design intent for "global = NULL").
alter table public.personality_role_templates
  alter column org_id drop not null;

-- Partial-unique enforces "at most one global per role_key" + "at most
-- one per-org per role_key" — a plain UNIQUE on a nullable column does
-- NOT enforce this (NULLs are treated as distinct by UNIQUE).
create unique index if not exists personality_role_templates_role_global_uniq
  on public.personality_role_templates (role_key) where org_id is null;
create unique index if not exists personality_role_templates_role_org_uniq
  on public.personality_role_templates (role_key, org_id) where org_id is not null;

alter table public.personality_role_template_traits
  add column if not exists template_id uuid;

update public.personality_role_template_traits tt
   set template_id = rt.id
  from public.personality_role_templates rt
 where rt.role_key = tt.role_key
   and (rt.org_id is not distinct from tt.org_id)
   and tt.template_id is null;

alter table public.personality_role_template_traits
  alter column template_id set not null;

alter table public.personality_role_template_traits
  add constraint personality_role_template_traits_template_fkey
  foreign key (template_id) references public.personality_role_templates(id)
  on delete cascade;

create unique index if not exists personality_role_template_traits_template_trait_uniq
  on public.personality_role_template_traits (template_id, trait_key);

-- Keep the (role_key, org_id) columns as denormalised shortcuts — the
-- compute RPC reads them — but add a TRIGGER that keeps them in sync
-- with the parent template, so they can't drift.

create or replace function public._personality_template_trait_sync()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_rk text; v_org uuid;
begin
  select role_key, org_id into v_rk, v_org
    from public.personality_role_templates where id = new.template_id;
  if v_rk is null then
    raise exception 'personality_role_template_traits: template_id % does not reference an existing template', new.template_id;
  end if;
  new.role_key := v_rk;
  new.org_id := v_org;
  return new;
end;
$$;

drop trigger if exists trg_personality_template_trait_sync on public.personality_role_template_traits;
create trigger trg_personality_template_trait_sync
  before insert or update of template_id on public.personality_role_template_traits
  for each row execute function public._personality_template_trait_sync();

-- ─── FIX 5 — Partial-unique for global instruments + global templates' content
-- The existing `unique (org_id, key, version)` on assessment_instruments
-- allows multiple globals; same fix pattern.

create unique index if not exists assessment_instruments_global_uniq
  on public.assessment_instruments (key, version) where org_id is null;

-- ─── FIX 3 + FIX 4 — Rewrite personality_compute_scores ─────────────
-- (a) Role-template loop now includes org-scoped templates for the
--     session's org.
-- (b) Privileged-bypass uses session_user (the role that connected),
--     not current_user (the function owner). pg_has_role catches the
--     case where the connecting role is a member of service_role.

create or replace function public.personality_compute_scores(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session       public.assessment_sessions%rowtype;
  v_invite        public.assessment_invites%rowtype;
  v_instrument_id uuid;
  v_actor         uuid := (select id from public.people where auth_user_id = (select auth.uid()) limit 1);
  -- Bypass for privileged sessions (operator psql, supabase_admin,
  -- service_role JWT). current_user inside SECDEF is the function
  -- OWNER, not the caller — must use session_user.
  v_is_privileged boolean := (
    session_user in ('service_role','postgres','supabase_admin')
    or pg_has_role(session_user, 'service_role', 'MEMBER')
  );
  v_trait_count   int := 0;
  v_match_count   int := 0;
  r record; tt record;
  v_raw           numeric;
  v_percentile    int;
  v_t_score       int;
  v_template_org  uuid;
  v_pcts          jsonb;
  v_penalty       numeric;
  v_contribs      jsonb;
  v_flags         jsonb;
  v_match         int;
begin
  select * into v_session from public.assessment_sessions where id = p_session_id;
  if not found then
    raise exception 'personality_compute_scores: session not found';
  end if;
  select * into v_invite from public.assessment_invites where id = v_session.invite_id;

  if not v_is_privileged
     and not public.has_permission(v_session.org_id, 'fit.compute')
     and not public.is_self(v_session.person_id)
     and not coalesce(public.is_platform_admin(), false) then
    raise exception 'personality_compute_scores: forbidden';
  end if;

  select id into v_instrument_id
    from public.assessment_instruments
   where key = 'personality_v1' and org_id is null and version = '1.0.0';
  if v_instrument_id is null then
    raise exception 'personality_compute_scores: instrument personality_v1 not found';
  end if;

  for r in
    with resp as (
      select i.item_json->>'trait_key' as trait_key,
             (i.item_json->>'reverse_score')::boolean as reverse_score,
             (rsp.response_json->>'value')::numeric as response
        from public.assessment_responses rsp
        join public.assessment_items i on i.id = rsp.item_id
       where rsp.assessment_id = v_invite.assessment_id
         and i.instrument_id = v_instrument_id
    ),
    keyed as (
      select trait_key,
             case when reverse_score then 6 - response else response end as keyed_val
        from resp
       where response is not null
    ),
    means as (
      select trait_key, avg(keyed_val)::numeric as mean, count(*)::int as n
        from keyed group by trait_key
    )
    select m.trait_key, m.mean, m.n,
           pn.breakpoints, pn.validity_status::text as norm_status,
           pn._dev_stub as norm_stub
      from means m
      left join public.personality_norms pn
             on pn.trait_key = m.trait_key
            and pn.population_key = 'global_dev_stub'
  loop
    v_raw        := r.mean;
    v_percentile := public._personality_percentile(v_raw, r.breakpoints);
    v_t_score    := public._personality_percentile_to_t(v_percentile);

    insert into public.assessment_scores
      (org_id, assessment_id, person_id, consent_id,
       scale_key, raw_score, scaled_score, norm_band,
       validity_status, _dev_stub, validity_flags_json)
    values (
      v_session.org_id, v_invite.assessment_id, v_session.person_id, v_invite.consent_recorded_id,
      'trait:' || r.trait_key,
      v_raw, v_t_score,
      case when v_percentile is null then null
           when v_percentile < 30    then 'low'
           when v_percentile < 70    then 'mid'
           else                           'high' end,
      coalesce(r.norm_status, 'dev_stub')::public.validity_status,
      coalesce(r.norm_stub, true) or r.n < 5,
      jsonb_build_object(
        'percentile', v_percentile, 'n_keyed_responses', r.n,
        'norm_population', 'global_dev_stub',
        'note', case when r.n < 5 then 'fewer than 5 keyed items — exploratory only' else null end
      )
    )
    on conflict (assessment_id, scale_key) do update set
      raw_score = excluded.raw_score, scaled_score = excluded.scaled_score,
      norm_band = excluded.norm_band, validity_status = excluded.validity_status,
      _dev_stub = excluded._dev_stub, validity_flags_json = excluded.validity_flags_json,
      computed_at = now(), updated_at = now();
    v_trait_count := v_trait_count + 1;
  end loop;

  select coalesce(jsonb_object_agg(
    replace(scale_key, 'trait:', ''),
    (validity_flags_json->>'percentile')::int
  ), '{}'::jsonb)
    into v_pcts
    from public.assessment_scores
   where assessment_id = v_invite.assessment_id and scale_key like 'trait:%';

  -- FIX 3: include org-scoped templates, not just global.
  for r in
    select * from public.personality_role_templates
     where org_id is null or org_id = v_session.org_id
  loop
    v_penalty := 0;
    v_contribs := '[]'::jsonb;
    v_flags    := '[]'::jsonb;
    v_template_org := r.org_id;

    for tt in
      select trait_key, band_low, band_high, direction::text as direction, weight
        from public.personality_role_template_traits
       where template_id = r.id and review_flag = false
    loop
      declare
        v_pct numeric := nullif(v_pcts->>tt.trait_key, '')::numeric;
        v_dist numeric;
        v_severity numeric;
        v_p numeric;
      begin
        if v_pct is null then continue; end if;
        if tt.direction = 'higher_better' then
          v_dist := case when v_pct < tt.band_low then (tt.band_low - v_pct) else 0 end;
        elsif tt.direction = 'lower_better' then
          v_dist := case when v_pct > tt.band_high then (v_pct - tt.band_high) else 0 end;
        else
          v_dist := case when v_pct < tt.band_low then (tt.band_low - v_pct)
                         when v_pct > tt.band_high then (v_pct - tt.band_high)
                         else 0 end;
        end if;
        v_severity := least(1, v_dist / r.match_tolerance_ref);
        v_p := tt.weight * v_severity;
        v_penalty := v_penalty + v_p;
        v_contribs := v_contribs || jsonb_build_object(
          'trait', tt.trait_key, 'percentile', v_pct::int,
          'band', jsonb_build_array(tt.band_low, tt.band_high),
          'direction', tt.direction, 'weight', tt.weight,
          'severity', round(v_severity::numeric, 3), 'penalty', round(v_p::numeric, 3)
        );
      end;
    end loop;

    for tt in
      select trait_key, flag_threshold
        from public.personality_role_template_traits
       where template_id = r.id and review_flag = true
    loop
      declare
        v_pct numeric := nullif(v_pcts->>tt.trait_key, '')::numeric;
      begin
        if v_pct is not null and tt.flag_threshold is not null and v_pct >= tt.flag_threshold then
          v_flags := v_flags || jsonb_build_object(
            'trait', tt.trait_key, 'percentile', v_pct::int, 'threshold', tt.flag_threshold
          );
        end if;
      end;
    end loop;

    select coalesce(jsonb_agg(c order by (c->>'penalty')::numeric desc), '[]'::jsonb)
      into v_contribs from jsonb_array_elements(v_contribs) c;

    v_match := greatest(0, least(100, round(100 * (1 - v_penalty))::int));

    insert into public.personality_role_matches
      (org_id, session_id, person_id, role_key, role_template_org_id,
       match_score, contributions_json, flags_json, validity_status, _dev_stub)
    values (
      v_session.org_id, v_session.id, v_session.person_id, r.role_key, v_template_org,
      v_match, v_contribs, v_flags, 'dev_stub', true
    )
    on conflict (session_id, role_key) do update set
      match_score = excluded.match_score,
      contributions_json = excluded.contributions_json,
      flags_json = excluded.flags_json,
      validity_status = excluded.validity_status,
      _dev_stub = excluded._dev_stub,
      computed_at = now(), updated_at = now();
    v_match_count := v_match_count + 1;
  end loop;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
  values (
    v_session.org_id, v_actor, 'personality.compute', 'assessment_sessions', v_session.id,
    jsonb_build_object('traits_scored', v_trait_count, 'role_matches_written', v_match_count)
  );

  return jsonb_build_object(
    'ok', true, 'session_id', v_session.id,
    'traits_scored', v_trait_count, 'role_matches_written', v_match_count
  );
end;
$$;
revoke execute on function public.personality_compute_scores(uuid) from public;
grant  execute on function public.personality_compute_scores(uuid) to authenticated, service_role;

comment on function public.personality_compute_scores(uuid) is
  'Compute personality trait scores + role matches for a session. AuthZ: session''s person (is_self) OR fit.compute on the org OR platform_admin OR a privileged session role (service_role / postgres). Reads template_id-keyed template_traits (post-audit fix). All output rows ship as dev_stub until H-2 / H-3 / H-7 close.';
