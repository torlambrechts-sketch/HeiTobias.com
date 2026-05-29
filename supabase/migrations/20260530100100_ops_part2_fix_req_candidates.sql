-- Fix-up: rpc_req_candidates had two issues
--  (a) `id` was ambiguous between the function's RETURNS TABLE column
--      and requisitions.id — aliased to req.id
--  (b) people.full_name + primary_email are citext, not text — explicit
--      ::text casts on the SELECT to match the RETURNS TABLE signature

create or replace function public.rpc_req_candidates(p_requisition_id uuid)
returns table (
  id uuid, person_id uuid, full_name text, primary_email text, stage text,
  created_at timestamptz
) language plpgsql set search_path = '' security definer as $$
declare v_org uuid;
begin
  select req.org_id into v_org from public.requisitions req where req.id = p_requisition_id;
  if v_org is null then raise exception 'rpc_req_candidates: requisition not found'; end if;
  if (select auth.uid()) is null or not public.has_permission(v_org, 'requisition.read') then
    raise exception 'rpc_req_candidates: requires requisition.read';
  end if;
  return query
    select rc.id, rc.person_id, p.full_name::text, p.primary_email::text, rc.stage::text, rc.created_at
    from public.requisition_candidates rc
    join public.people p on p.id = rc.person_id
    where rc.requisition_id = p_requisition_id
    order by rc.created_at desc;
end;
$$;
