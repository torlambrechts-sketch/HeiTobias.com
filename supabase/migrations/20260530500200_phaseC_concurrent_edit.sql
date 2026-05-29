-- Phase C concurrent-edit detection.
--
-- The schema already has updated_at on every domain table. What it
-- doesn't have is an enforced way for clients to say "I'm updating
-- the row I last saw at timestamp X — refuse if it's changed since."
-- This adds an RPC `requisition_update_optimistic` that takes the
-- caller's last-seen updated_at and refuses with a clear error code
-- if the row has moved on. UIs surface this to the user as
-- "this requisition was updated by someone else 2 minutes ago — refresh
-- to see latest" instead of silently overwriting their work.
--
-- We do not retrofit every domain table here — only requisitions, the
-- single surface that has a real concurrent-edit risk today (multiple
-- recruiters on the same hiring intent). Other tables can adopt the
-- same pattern when their UI surfaces support concurrent edits.

create or replace function public.requisition_update_optimistic(
  p_id uuid,
  p_expected_updated_at timestamptz,
  p_status text default null,
  p_team_id uuid default null,
  p_collaborating_org_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now    timestamptz;
  v_actual timestamptz;
  v_org    uuid;
begin
  -- RLS still applies here even though we are SECURITY DEFINER — we
  -- explicitly call has_permission inside the function and use the
  -- caller's auth.uid() to look it up. The function is not a privilege
  -- escalation path.
  select org_id, updated_at into v_org, v_actual
    from public.requisitions where id = p_id;

  if v_actual is null then
    raise exception 'requisition_update: not found';
  end if;

  if not public.has_permission(v_org, 'requisition.write') then
    raise exception 'requisition_update: forbidden';
  end if;

  if v_actual <> p_expected_updated_at then
    -- Conflict. Return the actual updated_at so the client can decide
    -- (typically: refetch and show the diff to the user).
    return jsonb_build_object(
      'ok', false,
      'reason', 'stale_write',
      'actual_updated_at', v_actual,
      'expected_updated_at', p_expected_updated_at
    );
  end if;

  -- No conflict — apply the update.
  v_now := now();
  update public.requisitions set
    status               = coalesce(p_status::public.requisition_status, status),
    team_id              = coalesce(p_team_id, team_id),
    collaborating_org_id = coalesce(p_collaborating_org_id, collaborating_org_id),
    updated_at           = v_now
  where id = p_id;

  return jsonb_build_object(
    'ok', true,
    'updated_at', v_now
  );
end;
$$;

revoke execute on function public.requisition_update_optimistic(uuid, timestamptz, text, uuid, uuid) from public;
grant  execute on function public.requisition_update_optimistic(uuid, timestamptz, text, uuid, uuid) to authenticated;

comment on function public.requisition_update_optimistic(uuid, timestamptz, text, uuid, uuid) is
  'Optimistic-concurrency requisition update. Compares the caller''s expected updated_at to the row''s actual; on mismatch, returns {ok:false, reason:''stale_write'', actual_updated_at, expected_updated_at} so the UI can re-fetch and show the diff to the user. On match, applies the update and returns the new updated_at.';
