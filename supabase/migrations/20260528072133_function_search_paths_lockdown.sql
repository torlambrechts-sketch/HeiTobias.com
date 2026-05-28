-- function_search_paths_lockdown
--
-- Hardening: lock the search_path on every trigger / helper function so an attacker
-- who can create objects in a schema earlier on the path cannot shadow our calls.
-- All internal references are already fully schema-qualified (public.*, extensions.*),
-- so search_path = '' is safe. pg_catalog is always implicitly searched, so built-ins
-- like now() still resolve.

alter function public.set_updated_at()                                set search_path = '';
alter function public._check_dept_parent_same_org()                   set search_path = '';
alter function public._check_team_dept_same_org()                     set search_path = '';
alter function public._check_team_member_same_org()                   set search_path = '';
alter function public._check_role_supersedes()                        set search_path = '';
alter function public._check_role_template_source()                   set search_path = '';
alter function public._check_position_role_org()                      set search_path = '';
alter function public._check_position_manager_org()                   set search_path = '';
alter function public._check_position_team_org()                      set search_path = '';
alter function public._check_assessment_result_profile()              set search_path = '';
alter function public._check_requisition_role_org()                   set search_path = '';
alter function public._check_req_candidate_same_org()                 set search_path = '';
alter function public._check_placement_from_org_matches_requisition() set search_path = '';
