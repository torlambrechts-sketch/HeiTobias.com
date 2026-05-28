-- phase1_module_registration — register the 5 Phase 1 capability modules and
-- create the validity_status enum used by every "scientific value" surface
-- (per CLAUDE.md *Validated science & DEV STUBs* and PHASE1-SPEC §4).

-- Validity status — instrument-level provenance.
--   dev_stub  — our placeholder content / scoring; never validated values.
--   licensed  — real instrument's content is plugged in.
--   validated — instrument + scoring are I/O-validated for our population.
create type public.validity_status as enum ('dev_stub', 'licensed', 'validated');

-- ---- Module registration -----------------------------------------------
insert into public.modules (key, name, version, status, config_schema_json) values
  ('role_architecture', 'Role Architecture Engine', '0.1.0', 'beta',
   '{"type":"object","properties":{"default_competency_framework":{"type":"string"},"require_signoff":{"type":"boolean"}},"additionalProperties":true}'::jsonb),
  ('team_definition', 'Team-based Role Definition', '0.1.0', 'beta',
   '{"type":"object","properties":{"min_evaluators":{"type":"integer","minimum":1,"maximum":20},"divergence_threshold":{"type":"number","minimum":0,"maximum":1}},"additionalProperties":true}'::jsonb),
  ('assessment_engine', 'Assessment Engine', '0.1.0', 'beta',
   '{"type":"object","properties":{"default_instrument_key":{"type":"string"},"invite_expiry_days":{"type":"integer","minimum":1,"maximum":90}},"additionalProperties":true}'::jsonb),
  ('fit_scoring', 'Fit Scoring & Placement Report', '0.1.0', 'beta',
   '{"type":"object","properties":{"require_human_decision_before_placement":{"type":"boolean"}},"additionalProperties":true}'::jsonb),
  ('candidate_experience', 'Candidate Experience', '0.1.0', 'beta',
   '{"type":"object","properties":{"consent_required":{"type":"boolean"},"branding_locale_overrides":{"type":"object"}},"additionalProperties":true}'::jsonb)
on conflict (key) do nothing;

-- ---- Phase 1 permission keys -------------------------------------------
insert into public.rbac_permissions (key, description) values
  ('assessment.invite',          'Send an assessment invite to a candidate.'),
  ('assessment.read',            'Read assessment instruments, items, responses, and scores in scope.'),
  ('assessment.write',           'Create / update assessment instances and instruments.'),
  ('fit.read',                   'Read fit_results and placement reports in scope.'),
  ('fit.compute',                'Trigger fit computation for a candidate vs. a role.'),
  ('hiring.decide',              'Record the human hiring decision (advance/reject/hire/withdraw).'),
  ('team_definition.rate',       'Submit independent rating in a team-based role definition.'),
  ('team_definition.reconcile',  'Run reconciliation on a team-rated role to produce a signed-off version.')
on conflict (key) do nothing;

-- ---- Map new permissions to existing system roles ----------------------
-- recruiter drives the recruiter OS: assessment + fit + hiring decision + team rating.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null and r.key = 'recruiter'
  and p.key in (
    'assessment.invite','assessment.read','assessment.write',
    'fit.read','fit.compute',
    'hiring.decide',
    'team_definition.rate','team_definition.reconcile'
  )
on conflict do nothing;

-- hiring_manager: rates roles + reads candidates + records decisions.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null and r.key = 'hiring_manager'
  and p.key in (
    'assessment.read', 'fit.read', 'hiring.decide', 'team_definition.rate'
  )
on conflict do nothing;

-- org_admin + people_ops_admin: all of the above.
insert into public.rbac_role_permissions (role_id, permission_id)
select r.id, p.id from public.rbac_roles r, public.rbac_permissions p
where r.org_id is null and r.key in ('org_admin','people_ops_admin')
  and p.key in (
    'assessment.invite','assessment.read','assessment.write',
    'fit.read','fit.compute',
    'hiring.decide',
    'team_definition.rate','team_definition.reconcile'
  )
on conflict do nothing;
