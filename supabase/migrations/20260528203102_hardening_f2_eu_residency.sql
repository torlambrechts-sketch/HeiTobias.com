-- hardening_f2_eu_residency — audit finding F-2. Per CLAUDE.md hard
-- "never" + SCIENCE-SPEC §8 every organization MUST be EU-region.
-- The underlying Supabase project region (config.toml) is an
-- operator-level guarantee outside this migration's scope.

update public.organizations set data_region = 'eu' where data_region <> 'eu';

alter table public.organizations drop constraint if exists chk_organizations_eu_residency;
alter table public.organizations add constraint chk_organizations_eu_residency
  check (data_region = 'eu');
comment on constraint chk_organizations_eu_residency on public.organizations is
  'SCIENCE-SPEC §8 + CLAUDE.md hard never: every organization data_region must be EU.';
