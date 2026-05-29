-- hardening_c_role_definition_expansion — SCIENCE-SPEC §2 + PHASE0-SPEC
-- §2.7 trait_targets band shape. Audit finding F-1.
--
-- Two structural rules made physical:
--
--   * trait_targets accepts EITHER the new band shape (centre/lower/upper +
--     direction enum {optimum|minimum_threshold|maximum_threshold|linear})
--     OR the legacy {trait,min,max} shape (kept for backward compat;
--     auto-backfilled to band shape with _dev_stub_shape=true).
--
--   * Band rules trigger _validate_role_trait_targets enforces:
--       - direction='optimum' requires centre + lower + upper
--       - direction in (max|min)_threshold requires >=10-char justification
--     This is the SCIENCE-SPEC §2 "trait targets are RANGES, not maxima"
--     rule, finally enforced at the DB.

create table public.role_definition_schema (
  id           uuid primary key default extensions.gen_random_uuid(),
  version      text not null unique,
  status       text not null default 'active' check (status in ('active','superseded')),
  schema_json  jsonb not null,
  notes        text,
  effective_from date not null default current_date,
  created_at   timestamptz not null default now()
);
alter table public.role_definition_schema enable row level security;
alter table public.role_definition_schema force row level security;
create policy role_definition_schema_select on public.role_definition_schema for select to authenticated using (true);
create trigger trg_audit_role_definition_schema after insert or update or delete on public.role_definition_schema for each row execute function public._audit_row();

insert into public.role_definition_schema (version, schema_json, notes) values
  ('1.0.0-band',
   '{"$schema":"http://json-schema.org/draft-07/schema#","type":"object","required":["competencies","trait_targets"],"properties":{"identity_and_governance":{"type":"object"},"task_layer":{"type":["array","object","null"]},"competencies":{"type":"array","items":{"type":"object","required":["key","weight"]}},"trait_targets":{"type":"array","items":{"anyOf":[{"type":"object","required":["trait","direction"],"properties":{"trait":{"type":"string"},"direction":{"enum":["optimum","minimum_threshold","maximum_threshold","linear"]},"centre":{"type":"number"},"lower":{"type":"number"},"upper":{"type":"number"},"weight":{"type":"number"},"justification":{"type":"string"},"evidence_refs":{"type":"array"}}},{"type":"object","required":["trait","min","max"]}]}},"cognitive_demand":{"type":["object","null"]},"context_factors":{"type":["object","array","null"]},"values_and_motivation":{"type":["object","null"]},"success_criteria":{"type":["array","object","null"]},"evolution_vector":{"type":["object","null"]},"team_gap_context":{"type":["object","null"]},"validation_and_defensibility_metadata":{"type":["object","null"]}}}'::jsonb,
   'PHASE0-SPEC §2.7 + SCIENCE-SPEC §2 band-with-direction shape. Accepts legacy {trait,min,max} for backward compat (auto-backfilled).')
on conflict (version) do nothing;

alter table public.roles_catalog drop constraint if exists chk_role_definition_shape;
alter table public.roles_catalog add constraint chk_role_definition_shape
  check (extensions.jsonb_matches_schema(
    schema => '{"type":"object","required":["competencies","trait_targets"],"properties":{"identity_and_governance":{"type":"object"},"task_layer":{"type":["array","object","null"]},"competencies":{"type":"array","items":{"type":"object","required":["key","weight"],"properties":{"key":{"type":"string"},"weight":{"type":"number","minimum":0,"maximum":1}},"additionalProperties":true}},"trait_targets":{"type":"array","items":{"anyOf":[{"type":"object","required":["trait","direction"],"properties":{"trait":{"type":"string"},"direction":{"enum":["optimum","minimum_threshold","maximum_threshold","linear"]},"centre":{"type":"number"},"lower":{"type":"number"},"upper":{"type":"number"},"weight":{"type":"number"},"justification":{"type":"string"},"evidence_refs":{"type":"array"},"_dev_stub":{"type":"boolean"},"_dev_stub_shape":{"type":"boolean"}}},{"type":"object","required":["trait","min","max"],"properties":{"trait":{"type":"string"},"min":{"type":"number"},"max":{"type":"number"},"_dev_stub":{"type":"boolean"}}}]}},"cognitive_demand":{"type":["object","null"]},"context_factors":{"type":["array","object","null"]},"values_and_motivation":{"type":["object","null"]},"success_criteria":{"type":["array","object","null"]},"evolution_vector":{"type":["object","null"]},"team_gap_context":{"type":["object","null"]},"validation_and_defensibility_metadata":{"type":["object","null"]}},"additionalProperties":true}'::json,
    instance => definition_json
  ));

create or replace function public._validate_role_trait_targets() returns trigger
language plpgsql set search_path = '' as $$
declare target jsonb;
begin
  if new.definition_json -> 'trait_targets' is null then return new; end if;
  for target in select * from jsonb_array_elements(new.definition_json -> 'trait_targets') loop
    if target ? 'direction' then
      if (target ->> 'direction') = 'optimum' then
        if not (target ? 'centre' and target ? 'lower' and target ? 'upper') then
          raise exception 'trait_target with direction=optimum requires centre+lower+upper band (SCIENCE-SPEC §2 — Le 2011, Pierce & Aguinis 2013): %', target;
        end if;
      end if;
      if (target ->> 'direction') in ('maximum_threshold','minimum_threshold') then
        if not (target ? 'justification') or length(coalesce(target ->> 'justification', '')) < 10 then
          raise exception 'trait_target with direction=%s requires non-empty justification (>=10 chars; SCIENCE-SPEC §2): %', target ->> 'direction', target;
        end if;
      end if;
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_validate_role_trait_targets on public.roles_catalog;
create trigger trg_validate_role_trait_targets
  before insert or update of definition_json on public.roles_catalog
  for each row execute function public._validate_role_trait_targets();

-- Backfill: legacy {trait,min,max} → band shape with _dev_stub_shape=true.
update public.roles_catalog
set definition_json = jsonb_set(
  definition_json,
  '{trait_targets}',
  coalesce(
    (
      select jsonb_agg(
        case
          when t ? 'direction' then t
          when t ? 'min' and t ? 'max' then
            jsonb_build_object(
              'trait', t->>'trait',
              'direction', 'optimum',
              'lower', (t->>'min')::numeric,
              'upper', (t->>'max')::numeric,
              'centre', (((t->>'min')::numeric) + ((t->>'max')::numeric)) / 2,
              '_dev_stub_shape', true,
              '_dev_stub', true,
              'justification', 'DEV STUB — auto-backfilled from legacy {min,max} shape; pending I/O psychologist band + evidence_refs (SCIENCE-SPEC §2)'
            )
          else t
        end
      )
      from jsonb_array_elements(definition_json -> 'trait_targets') t
    ),
    '[]'::jsonb
  )
)
where definition_json ? 'trait_targets'
  and jsonb_typeof(definition_json -> 'trait_targets') = 'array'
  and jsonb_array_length(definition_json -> 'trait_targets') > 0;
