-- hardening_p4_p5_scope_policies — audit findings P-4, P-5. Permissive
-- global-catalog policies using bare using(true) now scoped to
-- authenticated so anon callers don't inadvertently read them.

drop policy if exists rbac_roles_select on public.rbac_roles;
drop policy if exists rbac_permissions_select on public.rbac_permissions;
drop policy if exists rbac_role_permissions_select on public.rbac_role_permissions;
drop policy if exists modules_select on public.modules;
drop policy if exists component_registry_select on public.component_registry;
drop policy if exists compliance_rules_select on public.compliance_rules;

create policy rbac_roles_select            on public.rbac_roles            for select to authenticated using (true);
create policy rbac_permissions_select      on public.rbac_permissions      for select to authenticated using (true);
create policy rbac_role_permissions_select on public.rbac_role_permissions for select to authenticated using (true);
create policy modules_select               on public.modules               for select to authenticated using (true);
create policy component_registry_select    on public.component_registry    for select to authenticated using (true);
create policy compliance_rules_select      on public.compliance_rules      for select to authenticated using (true);
