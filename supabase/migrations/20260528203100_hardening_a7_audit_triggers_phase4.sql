-- hardening_a7_audit_triggers_phase4 — adds trg_audit_* to 5 Phase 4
-- tables that shipped without them, regressing test 06 + PHASE0-SPEC §9
-- bullet 8. Audit finding F-3.

create trigger trg_audit_compliance_artifact_sources after insert or update or delete on public.compliance_artifact_sources for each row execute function public._audit_row();
create trigger trg_audit_compliance_rules            after insert or update or delete on public.compliance_rules            for each row execute function public._audit_row();
create trigger trg_audit_model_dataset_subjects      after insert or update or delete on public.model_dataset_subjects      for each row execute function public._audit_row();
create trigger trg_audit_norm_percentiles            after insert or update or delete on public.norm_percentiles            for each row execute function public._audit_row();
create trigger trg_audit_pareto_curve_points         after insert or update or delete on public.pareto_curve_points         for each row execute function public._audit_row();
