-- phase3_step4_team_composition — aggregate team strengths/gaps from
-- members' OWN profiles. HARD RULE per CLAUDE.md: no peer rating. We
-- aggregate from each member's own validated (or DEV-STUB) profile,
-- gated by each member's active ongoing_management consent.

create or replace function public.team_composition_compute(
  p_team_id uuid
)
returns uuid
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller    uuid := (select auth.uid());
  v_actor_id  uuid;
  v_team      public.teams%rowtype;
  v_members_total int;
  v_members_consented int := 0;
  v_consented_profiles jsonb := '[]'::jsonb;
  v_trait_agg jsonb;
  v_snapshot  jsonb;
  v_id        uuid;
begin
  select * into v_team from public.teams where id = p_team_id;
  if not found then raise exception 'team_composition_compute: team not found'; end if;
  if v_caller is not null and not public.has_permission(v_team.org_id, 'team.read') then
    raise exception 'team_composition_compute: caller lacks team.read in org';
  end if;
  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  -- Total members on the team (denominator for coverage).
  select count(*) into v_members_total from public.team_members where team_id = p_team_id;

  -- Members WITH an active ongoing_management consent to this org —
  -- and a latest profile in the org. We aggregate from THEIR profile,
  -- never from peer ratings.
  select coalesce(jsonb_agg(jsonb_build_object(
    'person_id',  tm.person_id,
    'traits_json', pr.traits_json
  )), '[]'::jsonb) into v_consented_profiles
  from public.team_members tm
  join public.consent_grants cg on cg.person_id = tm.person_id
    and cg.granted_to_org_id = v_team.org_id
    and cg.purpose = 'ongoing_management'
    and cg.status = 'active'
    and cg.revoked_at is null
    and (cg.expires_at is null or cg.expires_at > now())
  join lateral (
    select traits_json from public.profiles p
      where p.person_id = tm.person_id and p.org_id = v_team.org_id
      order by p.valid_from desc nulls last
      limit 1
  ) pr on true
  where tm.team_id = p_team_id;

  v_members_consented := jsonb_array_length(v_consented_profiles);

  -- Aggregate trait values (mean per trait key across consented members).
  with traits_flat as (
    select trait_key, (trait_val)::numeric as v
    from jsonb_array_elements(v_consented_profiles) m,
    lateral jsonb_each_text(coalesce(m->'traits_json','{}'::jsonb)) as t(trait_key, trait_val)
    where jsonb_typeof(m->'traits_json') = 'object'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'trait', trait_key,
    'mean',  round(avg(v), 3),
    'n',     count(*),
    'min',   min(v),
    'max',   max(v)
  ) order by trait_key), '[]'::jsonb)
  into v_trait_agg
  from traits_flat
  group by ();

  v_snapshot := jsonb_build_object(
    'team_id',           p_team_id,
    'team_name',         v_team.name,
    'members_total',     v_members_total,
    'members_consented', v_members_consented,
    'coverage',          case when v_members_total = 0 then 0 else round((v_members_consented::numeric / v_members_total), 3) end,
    'trait_aggregates',  coalesce(v_trait_agg, '[]'::jsonb),
    '_dev_stub',         true,
    '_grounded',         true,
    '_source',           'members_own_profiles',
    '_peer_rating',      false,   -- hard rule discipline made structural
    'computed_at',       now()
  );

  insert into public.team_composition_snapshots (
    org_id, team_id, snapshot_json, members_consented, members_total,
    validity_status, _dev_stub, generated_by, generated_at
  ) values (
    v_team.org_id, p_team_id, v_snapshot, v_members_consented, v_members_total,
    'dev_stub', true, v_actor_id, now()
  )
  returning id into v_id;

  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_team.org_id, v_actor_id, 'team_composition.computed', 'team_composition_snapshots', v_id,
      jsonb_build_object('team_id', p_team_id, 'members_consented', v_members_consented,
                          'members_total', v_members_total));

  return v_id;
end;
$$;
revoke execute on function public.team_composition_compute(uuid) from public;
grant  execute on function public.team_composition_compute(uuid) to authenticated, service_role;
comment on function public.team_composition_compute(uuid) is
  'Aggregates team strengths/gaps from members'' OWN profiles (consent-gated). NEVER peer-personality rating. Snapshot carries _peer_rating=false structurally + members_consented/members_total coverage so the UI can show how representative the aggregate is.';
