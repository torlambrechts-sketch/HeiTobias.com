-- Step F — diagnostic view: every trait_target row auto-converted from
-- the legacy {trait,min,max} shape in §C (i.e. _dev_stub_shape=true).
-- Surfaces the candidates an I/O psychologist must replace with
-- validated bands + evidence_refs.

create or replace view public.role_trait_targets_backfilled
with (security_invoker = true) as
select
  r.id as role_id, r.org_id, r.title as role_title, r.version as role_version,
  tt ->> 'trait' as trait,
  (tt ->> 'centre')::numeric as centre,
  (tt ->> 'lower')::numeric as lower,
  (tt ->> 'upper')::numeric as upper,
  tt ->> 'direction' as direction,
  tt ->> 'justification' as justification_dev_stub,
  (tt ->> '_dev_stub_shape')::boolean as backfilled_from_legacy,
  r.updated_at as role_updated_at
from public.roles_catalog r,
     lateral jsonb_array_elements(coalesce(r.definition_json -> 'trait_targets', '[]'::jsonb)) tt
where coalesce((tt ->> '_dev_stub_shape')::boolean, false) = true;

comment on view public.role_trait_targets_backfilled is
  'Diagnostic surface: every trait_target row auto-converted from the legacy {trait,min,max} shape in the §C hardening. The candidates an I/O psychologist must replace with validated bands + evidence_refs.';

grant select on public.role_trait_targets_backfilled to authenticated, service_role;
