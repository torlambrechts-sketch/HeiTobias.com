-- hardening_a4_decision_artefacts_view — §A4 of the hardening prompt.
-- Unified read view over hiring_decisions and lifecycle_decisions per
-- SCIENCE-SPEC §9. Both underlying tables already enforce decided_by
-- NOT NULL + rationale NOT NULL via column constraints and the RPCs;
-- this view exposes them as a single decision_artefacts contract for
-- downstream tooling (Annex IV assembly, audit exports, etc.).

create or replace view public.decision_artefacts
with (security_invoker = true) as
select
  hd.id                                            as id,
  hd.org_id                                        as org_id,
  rc.person_id                                     as person_id,
  hd.decision::text                                as decision_type,
  hd.decided_by                                    as decided_by,
  hd.decided_at                                    as decided_at,
  hd.rationale                                     as justification_text,
  array_remove(array[hd.fit_result_id::text], null) as evidence_refs,
  hd.overrode_recommendation                       as human_override,
  hd.recommendation_summary                        as override_justification,
  'hiring_decisions'::text                         as source_table,
  hd.created_at                                    as created_at
from public.hiring_decisions hd
left join public.requisition_candidates rc on rc.id = hd.requisition_candidate_id
union all
select
  ld.id                                                       as id,
  ld.org_id                                                   as org_id,
  ld.person_id                                                as person_id,
  ld.kind::text                                               as decision_type,
  ld.decided_by                                               as decided_by,
  ld.decided_at                                               as decided_at,
  ld.rationale                                                as justification_text,
  array_remove(array[ld.refit_evaluation_id::text, ld.guidance_item_id::text], null) as evidence_refs,
  ld.overrode_recommendation                                  as human_override,
  ld.recommendation_summary                                   as override_justification,
  'lifecycle_decisions'::text                                 as source_table,
  ld.created_at                                               as created_at
from public.lifecycle_decisions ld;

comment on view public.decision_artefacts is
  'Unified view of hiring_decisions + lifecycle_decisions per SCIENCE-SPEC §9. Every consequential action carries one row; decided_by is the human-in-the-loop; rationale + evidence_refs are the explainability record.';

grant select on public.decision_artefacts to authenticated;
