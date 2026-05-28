-- assessment_take_state — Phase 1 UI support.
--
-- Anon-callable, token-gated read RPC the candidate /take/:token page uses
-- to render the consent + item-by-item flow. Returns everything the page
-- needs in one round-trip:
--   { invite_id, assessment_id, instrument_name, consent_captured,
--     items: [{id, key, prompt, type, choices, answered}],
--     completed: bool }
-- SECURITY DEFINER so anon can fetch through the token without needing
-- table-level grants on assessment_items / assessment_responses.

create or replace function public.assessment_take_state(
  p_token text
)
returns jsonb
language plpgsql
stable
set search_path = ''
security definer
as $$
declare
  v_invite     public.assessment_invites%rowtype;
  v_assessment public.assessments%rowtype;
  v_instr      public.assessment_instruments%rowtype;
  v_items      jsonb;
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'assessment_take_state: token required';
  end if;
  select * into v_invite from public.assessment_invites where token = p_token;
  if not found then
    raise exception 'assessment_take_state: invalid token';
  end if;
  select * into v_assessment from public.assessments where id = v_invite.assessment_id;
  select * into v_instr from public.assessment_instruments where key = v_assessment.instrument_key;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',       i.id,
    'key',      i.key,
    'prompt',   i.prompt,
    'type',     i.item_type,
    'choices',  i.item_json->'choices',
    'scale',    i.item_json->>'scale',
    '_dev_stub', i._dev_stub,
    'answered', exists (
      select 1 from public.assessment_responses r
      where r.assessment_id = v_invite.assessment_id and r.item_id = i.id
    )
  ) order by i.key), '[]'::jsonb) into v_items
  from public.assessment_items i
  where i.instrument_id = v_instr.id;

  return jsonb_build_object(
    'invite_id',         v_invite.id,
    'assessment_id',     v_invite.assessment_id,
    'instrument_key',    v_instr.key,
    'instrument_name',   v_instr.name,
    'validity_status',   v_instr.validity_status,
    'consent_captured',  v_invite.consent_recorded_id is not null,
    'completed',         v_assessment.status = 'completed',
    'used',              v_invite.used_at is not null,
    'expires_at',        v_invite.expires_at,
    'items',             v_items
  );
end;
$$;

revoke execute on function public.assessment_take_state(text) from public;
grant  execute on function public.assessment_take_state(text) to anon, authenticated, service_role;
comment on function public.assessment_take_state(text) is
  'Anon-callable. Returns the full state the /take/:token page needs to render: invite, instrument, items (with answered flag), consent status.';
