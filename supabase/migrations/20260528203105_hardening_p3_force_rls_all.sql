-- hardening_p3_force_rls_all — audit finding P-3. FORCE RLS on every
-- domain table so the table owner (migrate-time / service-role) also
-- goes through RLS. Closes the service-role-bypass gap.
-- audit_log is excluded — protection is the _audit_log_immutable
-- triggers; FORCE would block the trigger function itself.

alter table public.assessment_instruments              force row level security;
alter table public.assessment_invites                  force row level security;
alter table public.assessment_items                    force row level security;
alter table public.assessment_responses                force row level security;
alter table public.assessment_scores                   force row level security;
alter table public.assessments                         force row level security;
alter table public.competency_frameworks               force row level security;
alter table public.component_registry                  force row level security;
alter table public.consent_grants                      force row level security;
alter table public.departments                         force row level security;
alter table public.fit_results                         force row level security;
alter table public.hiring_decisions                    force row level security;
alter table public.membership_roles                    force row level security;
alter table public.memberships                         force row level security;
alter table public.modules                             force row level security;
alter table public.org_modules                         force row level security;
alter table public.organizations                       force row level security;
alter table public.people                              force row level security;
alter table public.placement_reports                   force row level security;
alter table public.placements                          force row level security;
alter table public.positions                           force row level security;
alter table public.profiles                            force row level security;
alter table public.rbac_permissions                    force row level security;
alter table public.rbac_role_permissions               force row level security;
alter table public.rbac_roles                          force row level security;
alter table public.requisition_candidates              force row level security;
alter table public.requisitions                        force row level security;
alter table public.role_definition_evaluations         force row level security;
alter table public.role_definition_reconciliations     force row level security;
alter table public.roles_catalog                       force row level security;
alter table public.team_members                        force row level security;
alter table public.teams                               force row level security;
alter table public.templates                           force row level security;
