-- 20260528120000_baseline_extensions
--
-- Enables the Postgres extensions that the Phase 0 schema and tests depend on.
-- Idempotent: every CREATE EXTENSION uses IF NOT EXISTS.
--
-- pgcrypto      -> gen_random_uuid() (already installed on Supabase, included for explicitness)
-- citext        -> case-insensitive text for people.primary_email
-- pg_jsonschema -> JSONB shape validation (e.g. roles_catalog.definition_json,
--                  modules.config_schema_json) so the database — not just app code —
--                  enforces template body shapes
-- moddatetime   -> trigger that touches updated_at on row updates
-- pgtap         -> SQL-level unit testing framework used by supabase/tests/*.sql
--
-- Supabase convention: shared extensions live in the `extensions` schema (already on search_path).

create extension if not exists pgcrypto      with schema extensions;
create extension if not exists citext        with schema extensions;
create extension if not exists pg_jsonschema with schema extensions;
create extension if not exists moddatetime   with schema extensions;
create extension if not exists pgtap         with schema extensions;
