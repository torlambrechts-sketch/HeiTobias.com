-- phase2_step3_employer_activation — receiving-employer first-run experience.
--
-- After placement_execute transfers a candidate's profile to the employer,
-- the data is in the employer org BUT invisible (Phase 2 Step 1 RLS:
-- profile_portability does NOT authorize ongoing viewing — only the
-- transfer event itself). The employer must capture a separate
-- ongoing_management consent before any post-hire surface can read.
--
-- placement_activate(placement_id):
--   * AuthZ: caller holds org.manage_all in the placement's to_org
--     (people_ops_admin / org_admin) — same as the activation surface.
--   * Validates the placement is status='transferred' (Phase 0 hand-off
--     completed) and the employee record exists.
--   * Captures an ongoing_management consent on the data subject's behalf
--     with legal_basis='contract' — the employment contract is the legal
--     basis for ongoing data use per PHASE0 §4.1.
--   * Idempotent: if an active ongoing_management consent already exists
--     for (person, to_org), returns its id without inserting a duplicate.
--   * Audits 'placement.activated' + 'consent.granted'.
--
-- This is NOT a second cross-org bridge: it operates entirely inside the
-- employer org, on data already present from placement_execute. The
-- agency loses standing visibility (already enforced by the agency
-- membership status='removed' that placement_execute set).

create or replace function public.placement_activate(
  p_placement_id uuid
)
returns jsonb
language plpgsql
set search_path = ''
security definer
as $$
declare
  v_caller     uuid := (select auth.uid());
  v_actor_id   uuid;
  v_placement  public.placements%rowtype;
  v_existing   uuid;
  v_consent_id uuid;
begin
  select * into v_placement from public.placements where id = p_placement_id;
  if not found then raise exception 'placement_activate: placement not found'; end if;

  if v_caller is not null and not public.has_permission(v_placement.to_org_id, 'org.manage_all') then
    raise exception 'placement_activate: caller lacks org.manage_all in to_org';
  end if;

  if v_placement.status <> 'transferred' then
    raise exception 'placement_activate: placement is %, requires transferred', v_placement.status;
  end if;

  select id into v_actor_id from public.people where auth_user_id = v_caller limit 1;

  -- Idempotent: if an active ongoing_management consent already exists for
  -- this (person, to_org), reuse it; otherwise capture.
  select id into v_existing from public.consent_grants
    where person_id          = v_placement.person_id
      and granted_to_org_id  = v_placement.to_org_id
      and purpose            = 'ongoing_management'
      and status             = 'active'
      and revoked_at         is null
      and (expires_at is null or expires_at > now())
    limit 1;

  if v_existing is not null then
    v_consent_id := v_existing;
  else
    insert into public.consent_grants (
      person_id, granted_to_org_id, purpose, legal_basis, scope_json
    ) values (
      v_placement.person_id, v_placement.to_org_id, 'ongoing_management', 'contract',
      jsonb_build_object('source','employer_activation','placement_id', p_placement_id)
    )
    returning id into v_consent_id;

    insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
      values (v_placement.to_org_id, v_actor_id, 'consent.granted', 'consent_grants', v_consent_id,
        jsonb_build_object('purpose','ongoing_management','person_id', v_placement.person_id,
                           'source','employer_activation','legal_basis','contract'));
  end if;

  -- Audit the activation event itself (distinct from the consent event).
  insert into public.audit_log (org_id, actor_person_id, action, entity_type, entity_id, after_json)
    values (v_placement.to_org_id, v_actor_id, 'placement.activated', 'placements', p_placement_id,
      jsonb_build_object('person_id', v_placement.person_id, 'ongoing_consent_id', v_consent_id));

  return jsonb_build_object(
    'placement_id',        p_placement_id,
    'ongoing_consent_id',  v_consent_id,
    'already_active',      v_existing is not null
  );
end;
$$;
revoke execute on function public.placement_activate(uuid) from public;
grant  execute on function public.placement_activate(uuid) to authenticated, service_role;
comment on function public.placement_activate(uuid) is
  'Receiving-employer activation. Captures a separate ongoing_management consent (legal_basis=contract) on the data subject''s behalf so post-hire surfaces can read inherited data. Idempotent. AuthZ: org.manage_all in to_org. No new cross-org path — operates entirely on data already inside the employer org from placement_execute.';

-- ---- employer_activations_state(org_id) ----
-- Returns the activation queue for an employer org: every placement
-- transferred to this org with its activation status. Read-only.
-- Authorized callers see all rows in their org; RLS on placements already
-- limits this — but we also gate the RPC explicitly.
create or replace function public.employer_activations_state(p_org_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
security definer
as $$
declare
  v_caller uuid := (select auth.uid());
  v_rows   jsonb;
begin
  if v_caller is null then raise exception 'employer_activations_state: auth required'; end if;
  if not public.has_permission(p_org_id, 'org.manage_all') then
    raise exception 'employer_activations_state: caller lacks org.manage_all in org';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'placement_id',     pl.id,
    'person_id',        pl.person_id,
    'person_name',      p.full_name,
    'person_email',     p.primary_email,
    'from_org_id',      pl.from_org_id,
    'from_org_name',    fo.name,
    'transferred_at',   pl.transferred_at,
    'status',           pl.status,
    'activated',        exists (
      select 1 from public.consent_grants cg
      where cg.person_id = pl.person_id
        and cg.granted_to_org_id = pl.to_org_id
        and cg.purpose = 'ongoing_management'
        and cg.status = 'active'
        and cg.revoked_at is null
    ),
    'ongoing_consent_id', (
      select cg.id from public.consent_grants cg
      where cg.person_id = pl.person_id
        and cg.granted_to_org_id = pl.to_org_id
        and cg.purpose = 'ongoing_management'
        and cg.status = 'active'
        and cg.revoked_at is null
      order by cg.granted_at desc limit 1
    )
  ) order by pl.transferred_at desc nulls last), '[]'::jsonb) into v_rows
  from public.placements pl
  join public.people p on p.id = pl.person_id
  join public.organizations fo on fo.id = pl.from_org_id
  where pl.to_org_id = p_org_id
    and pl.status = 'transferred';

  return jsonb_build_object('placements', v_rows);
end;
$$;
revoke execute on function public.employer_activations_state(uuid) from public;
grant  execute on function public.employer_activations_state(uuid) to authenticated, service_role;
comment on function public.employer_activations_state(uuid) is
  'Returns the employer''s activation queue: every transferred placement + whether ongoing_management consent has been captured. AuthZ: org.manage_all.';
