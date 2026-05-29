-- hardening_p2_denylist_expanded — audit finding P-2. Adds Insights
-- Discovery / colours-model / 9-box auto to the assessment_instruments
-- deny-list CHECK. Per CLAUDE.md Pillar 5 + SCIENCE-SPEC §4.

alter table public.assessment_instruments
  drop constraint if exists chk_assessment_instruments_deny_list;

alter table public.assessment_instruments
  add constraint chk_assessment_instruments_deny_list
  check (
    not (
      lower(coalesce(key,   '')) ~ '(mbti|myers[\s_-]?briggs|disc[\s_-]?profile|disc[\s_-]?assessment|disc[\s_-]?model|^disc$|vark|kolb[\s_-]?learning|learning[\s_-]?styles|belbin|insights[\s_-]?discovery|colou?rs?[\s_-]?model|colou?rs?[\s_-]?profile|9[\s_-]?box[\s_-]?auto)'
      or lower(coalesce(name,'')) ~ '(mbti|myers[\s_-]?briggs|\bdisc\b|vark|learning[\s_-]?styles|belbin|insights[\s_-]?discovery|colou?rs?\s+model|colou?rs?\s+profile|9[\s_-]?box)'
      or lower(coalesce(vendor,'')) ~ '(mbti|cpp[\s_-]?\(myers|wiley[\s_-]?disc|everything[\s_-]?disc|belbin|insights\s+learning)'
    )
  );
