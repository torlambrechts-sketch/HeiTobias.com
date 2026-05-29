-- Role Profile detail page — Step 0 seed.
-- Four DEV-STUB sample TEMPLATES (org_id null) carrying every
-- PHASE0-SPEC §2.7 component, so the page can render all 11 sections
-- without the agent fabricating data at render time. Every field is
-- clearly _dev_stub-flagged or validation_status='dev_stub'; an I/O
-- psychologist replaces them.
--
-- Families covered: engineering-lead, sales-AE, customer-success-lead,
-- people-leader. version_status values range across draft / under_review
-- / signed_off so the UI can exercise all four pill states.

delete from public.roles_catalog where org_id is null and title like 'SAMPLE %% (full shape, DEV STUB)';

insert into public.roles_catalog (org_id, title, family, is_template, status, version, definition_json, authored_by_json)
values (
  null, 'SAMPLE — Engineering Lead (full shape, DEV STUB)', 'engineering', true, 'draft', 1,
  jsonb_build_object(
    'identity_and_governance', jsonb_build_object('version_status','under_review','signed_off_by','[]'::jsonb,'validation_status','dev_stub','effective_from','2026-01-01','validation_evidence_refs','[]'::jsonb,'external_codes', jsonb_build_object('onet_soc','DEV-STUB 15-1252.00','esco','DEV-STUB 2512.7'),'_dev_stub',true),
    'task_layer', jsonb_build_array(
      jsonb_build_object('task','DEV STUB — Lead architecture reviews','criticality','high','frequency','weekly','outcomes','Design clarity','tools','RFC docs','_dev_stub',true),
      jsonb_build_object('task','DEV STUB — Coach 4-6 engineers','criticality','high','frequency','biweekly','outcomes','Growth velocity','tools','1:1','_dev_stub',true),
      jsonb_build_object('task','DEV STUB — Triage prod incidents','criticality','critical','frequency','as-needed','outcomes','MTTR','tools','Runbook','_dev_stub',true)
    ),
    'competencies', jsonb_build_array(
      jsonb_build_object('key','technical_leadership','name','Technical Leadership','weight',0.30,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','sme_delphi','framework_mapping','UCF: Leading & Deciding','_dev_stub',true),
      jsonb_build_object('key','systems_thinking','name','Systems Thinking','weight',0.25,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','cit','framework_mapping','SHL UCF: Analysing','_dev_stub',true),
      jsonb_build_object('key','team_development','name','Team Development','weight',0.25,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','sme_delphi','framework_mapping','KFLA: Develops Talent','_dev_stub',true),
      jsonb_build_object('key','code_craft','name','Code Craft','weight',0.20,'criticality','important','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','cit','framework_mapping','SHL UCF: Delivering','_dev_stub',true)
    ),
    'trait_targets', jsonb_build_array(
      jsonb_build_object('trait','conscientiousness','direction','optimum','centre',0.70,'lower',0.55,'upper',0.85,'weight',0.30,'justification','DEV STUB — inverted-U per Le 2011','evidence_refs', jsonb_build_array('Le et al. 2011, JAP'),'_dev_stub',true),
      jsonb_build_object('trait','emotional_stability','direction','optimum','centre',0.65,'lower',0.50,'upper',0.80,'weight',0.20,'justification','DEV STUB — TMGT band per Pierce & Aguinis 2013','evidence_refs', jsonb_build_array('Pierce & Aguinis 2013, JoM'),'_dev_stub',true),
      jsonb_build_object('trait','agreeableness','direction','minimum_threshold','centre',0.60,'lower',0.45,'weight',0.15,'justification','DEV STUB — below threshold contraindicated for coaching role','evidence_refs', jsonb_build_array('Mount Barrick Stewart 1998'),'_dev_stub',true),
      jsonb_build_object('trait','openness','direction','optimum','centre',0.65,'lower',0.50,'upper',0.85,'weight',0.20,'justification','DEV STUB — high autonomy + ambiguity context','evidence_refs', jsonb_build_array('DEV STUB ref'),'_dev_stub',true),
      jsonb_build_object('trait','extraversion','direction','linear','weight',0.15,'justification','DEV STUB — neutral; team-context dependent','evidence_refs', '[]'::jsonb,'_dev_stub',true)
    ),
    'cognitive_demand', jsonb_build_object('complexity_level',4,'complexity_level_justification','DEV STUB','target_band', jsonb_build_object('lower',0.65,'upper',0.90,'_dev_stub',true),'use_as','banded','validity_estimate_range', jsonb_build_object('low',0.23,'high',0.40,'_dev_stub',true,'caveat','Sackett 2022 range'),'_dev_stub',true),
    'context_factors', jsonb_build_object('autonomy',4,'ambiguity_tolerance_required',4,'pace_and_urgency',4,'collaboration_intensity',4,'stakeholder_load',3,'cognitive_complexity',5,'adversity_exposure',3,'psychological_safety_dependence',4,'feedback_frequency',3,'coherence_check_passed',true,'notes', jsonb_build_array('DEV STUB — high autonomy + ambiguity coherent with C-band centre 0.70'),'_dev_stub',true),
    'values_and_motivation', jsonb_build_object('schwartz_values', jsonb_build_object('achievement','high','self_direction','high','benevolence','medium','tradition','low','_dev_stub',true),'sdt_needs_supply', jsonb_build_object('autonomy','high','competence','high','relatedness','medium','_dev_stub',true),'_dev_stub',true),
    'success_criteria', jsonb_build_array(
      jsonb_build_object('horizon','90_day','dimension','task','behaviour','DEV STUB — first ADR shipped','_dev_stub',true),
      jsonb_build_object('horizon','90_day','dimension','contextual_ocb','behaviour','DEV STUB — paired with two peers','_dev_stub',true),
      jsonb_build_object('horizon','six_month','dimension','task','behaviour','DEV STUB — owns one core service','_dev_stub',true),
      jsonb_build_object('horizon','six_month','dimension','adaptive','behaviour','DEV STUB — adjusted plan post org change','_dev_stub',true),
      jsonb_build_object('horizon','annual','dimension','leadership','behaviour','DEV STUB — promoted one direct report','_dev_stub',true),
      jsonb_build_object('horizon','annual','dimension','cwb_avoidance','behaviour','DEV STUB — clean integrity record','_dev_stub',true)
    ),
    'evolution_vector', jsonb_build_object('_label','forecast','_dev_stub',true,'horizon_months',18,'confidence','medium','next_review_date','2027-05-01','narrative','DEV STUB — Platform thinking + customer narrative rising.','likely_to_rise', jsonb_build_array(jsonb_build_object('attribute','customer_facing_communication','delta','+0.10','_dev_stub',true),jsonb_build_object('attribute','platform_architecture','delta','+0.15','_dev_stub',true)),'likely_to_fall', jsonb_build_array(jsonb_build_object('attribute','hands_on_coding','delta','-0.10','_dev_stub',true)),'sources', jsonb_build_array('DEV STUB — Lightcast 2026','DEV STUB — SME panel')),
    'team_gap_context', jsonb_build_object('_dev_stub',true,'_peer_rating_blocked_at_schema',true,'note','DEV STUB — team-gap is computed from members own validated profiles; peer-personality rating is blocked at the schema level (SCIENCE-SPEC §7).','complementary_pull_traits', jsonb_build_array('extraversion','openness'),'supplementary_pull_traits', jsonb_build_array('conscientiousness','emotional_stability')),
    'validation_and_defensibility_metadata', jsonb_build_object('_dev_stub',true,'validation_method','pending_io_sme_panel','next_review_date','2026-12-31','framing_default','developmental'),
    '_dev_stub', true
  )::jsonb,
  '[]'::jsonb
);

insert into public.roles_catalog (org_id, title, family, is_template, status, version, definition_json, authored_by_json)
values (
  null, 'SAMPLE — Sales Account Executive (full shape, DEV STUB)', 'sales', true, 'draft', 1,
  jsonb_build_object(
    'identity_and_governance', jsonb_build_object('version_status','under_review','signed_off_by','[]'::jsonb,'validation_status','dev_stub','effective_from','2026-01-01','validation_evidence_refs','[]'::jsonb,'external_codes', jsonb_build_object('onet_soc','DEV-STUB 41-3091.00','esco','DEV-STUB 3322.1'),'_dev_stub',true),
    'task_layer', jsonb_build_array(jsonb_build_object('task','DEV STUB — Discover pain in 30-min calls','criticality','critical','frequency','daily','outcomes','Qualified pipeline','tools','CRM','_dev_stub',true)),
    'competencies', jsonb_build_array(
      jsonb_build_object('key','customer_focus','name','Customer Focus','weight',0.30,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','sme_delphi','framework_mapping','UCF: Interacting','_dev_stub',true),
      jsonb_build_object('key','persuasion','name','Persuasive Communication','weight',0.30,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','cit','framework_mapping','SHL UCF: Persuading','_dev_stub',true),
      jsonb_build_object('key','resilience','name','Resilience under Rejection','weight',0.20,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','cit','framework_mapping','KFLA: Resilience','_dev_stub',true),
      jsonb_build_object('key','deal_orchestration','name','Deal Orchestration','weight',0.20,'criticality','important','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','sme_delphi','framework_mapping','MEDDPICC','_dev_stub',true)
    ),
    'trait_targets', jsonb_build_array(
      jsonb_build_object('trait','extraversion','direction','optimum','centre',0.65,'lower',0.45,'upper',0.85,'weight',0.25,'justification','DEV STUB — Grant 2013 ambivert','evidence_refs', jsonb_build_array('Grant 2013, Psych Sci'),'_dev_stub',true),
      jsonb_build_object('trait','conscientiousness','direction','optimum','centre',0.65,'lower',0.50,'upper',0.85,'weight',0.25,'justification','DEV STUB — Le 2011','evidence_refs', jsonb_build_array('Le et al. 2011'),'_dev_stub',true),
      jsonb_build_object('trait','emotional_stability','direction','minimum_threshold','centre',0.60,'lower',0.50,'weight',0.20,'justification','DEV STUB — high-rejection role; threshold','evidence_refs', jsonb_build_array('DEV STUB'),'_dev_stub',true)
    ),
    'cognitive_demand', jsonb_build_object('complexity_level',3,'complexity_level_justification','DEV STUB','target_band', jsonb_build_object('lower',0.55,'upper',0.80,'_dev_stub',true),'use_as','banded','validity_estimate_range', jsonb_build_object('low',0.18,'high',0.32,'_dev_stub',true,'caveat','Sackett 2022 range'),'_dev_stub',true),
    'context_factors', jsonb_build_object('autonomy',4,'ambiguity_tolerance_required',3,'pace_and_urgency',5,'collaboration_intensity',3,'stakeholder_load',5,'cognitive_complexity',3,'adversity_exposure',4,'psychological_safety_dependence',2,'feedback_frequency',4,'coherence_check_passed',true,'notes', jsonb_build_array('DEV STUB — high stakeholder load + extraversion centre 0.65 coherent'),'_dev_stub',true),
    'values_and_motivation', jsonb_build_object('schwartz_values', jsonb_build_object('achievement','high','power','medium','_dev_stub',true),'sdt_needs_supply', jsonb_build_object('autonomy','medium','competence','high','relatedness','high','_dev_stub',true),'_dev_stub',true),
    'success_criteria', jsonb_build_array(
      jsonb_build_object('horizon','90_day','dimension','task','behaviour','DEV STUB — first qualified opportunity','_dev_stub',true),
      jsonb_build_object('horizon','annual','dimension','task','behaviour','DEV STUB — quota attainment >= 80%','_dev_stub',true)
    ),
    'evolution_vector', jsonb_build_object('_label','forecast','_dev_stub',true,'horizon_months',12,'confidence','low','next_review_date','2026-11-01','narrative','DEV STUB — Consultative depth rising; transactional execution falling.','likely_to_rise', jsonb_build_array(jsonb_build_object('attribute','consultative_depth','delta','+0.10','_dev_stub',true)),'likely_to_fall', jsonb_build_array(jsonb_build_object('attribute','transactional_volume','delta','-0.05','_dev_stub',true)),'sources', jsonb_build_array('DEV STUB — Industry analyst')),
    'team_gap_context', jsonb_build_object('_dev_stub',true,'_peer_rating_blocked_at_schema',true,'note','DEV STUB — built from members own profiles; peer-personality rating blocked at schema level (SCIENCE-SPEC §7).','complementary_pull_traits', jsonb_build_array('agreeableness'),'supplementary_pull_traits', jsonb_build_array('extraversion','conscientiousness')),
    'validation_and_defensibility_metadata', jsonb_build_object('_dev_stub',true,'validation_method','pending_io_sme_panel','next_review_date','2026-12-31','framing_default','developmental'),
    '_dev_stub', true
  )::jsonb,
  '[]'::jsonb
);

insert into public.roles_catalog (org_id, title, family, is_template, status, version, definition_json, authored_by_json)
values (
  null, 'SAMPLE — Customer Success Lead (full shape, DEV STUB)', 'customer_success', true, 'draft', 1,
  jsonb_build_object(
    'identity_and_governance', jsonb_build_object('version_status','draft','signed_off_by','[]'::jsonb,'validation_status','dev_stub','effective_from','2026-01-01','validation_evidence_refs','[]'::jsonb,'external_codes', jsonb_build_object('onet_soc','DEV-STUB 13-1199.00','esco','DEV-STUB 2421.4'),'_dev_stub',true),
    'task_layer', jsonb_build_array(jsonb_build_object('task','DEV STUB — Run quarterly business reviews','criticality','critical','frequency','quarterly','outcomes','Renewal probability','tools','QBR template','_dev_stub',true)),
    'competencies', jsonb_build_array(
      jsonb_build_object('key','customer_orientation','name','Customer Orientation','weight',0.40,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','sme_delphi','framework_mapping','UCF: Adapting','_dev_stub',true),
      jsonb_build_object('key','cross_functional_orchestration','name','Cross-functional Orchestration','weight',0.35,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','cit','framework_mapping','KFLA: Builds Networks','_dev_stub',true),
      jsonb_build_object('key','outcome_storytelling','name','Outcome Storytelling','weight',0.25,'criticality','important','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','sme_delphi','framework_mapping','SHL UCF: Presenting','_dev_stub',true)
    ),
    'trait_targets', jsonb_build_array(
      jsonb_build_object('trait','agreeableness','direction','optimum','centre',0.70,'lower',0.55,'upper',0.85,'weight',0.30,'justification','DEV STUB — customer-relationship intensity','evidence_refs', jsonb_build_array('DEV STUB'),'_dev_stub',true),
      jsonb_build_object('trait','conscientiousness','direction','optimum','centre',0.70,'lower',0.55,'upper',0.85,'weight',0.30,'justification','DEV STUB — follow-through','evidence_refs', jsonb_build_array('Le 2011'),'_dev_stub',true),
      jsonb_build_object('trait','emotional_stability','direction','minimum_threshold','centre',0.60,'lower',0.50,'weight',0.20,'justification','DEV STUB — escalation handling','evidence_refs', jsonb_build_array('DEV STUB'),'_dev_stub',true)
    ),
    'cognitive_demand', jsonb_build_object('complexity_level',3,'complexity_level_justification','DEV STUB','target_band', jsonb_build_object('lower',0.55,'upper',0.80,'_dev_stub',true),'use_as','banded','validity_estimate_range', jsonb_build_object('low',0.18,'high',0.32,'_dev_stub',true,'caveat','Sackett 2022 range'),'_dev_stub',true),
    'context_factors', jsonb_build_object('autonomy',3,'ambiguity_tolerance_required',3,'pace_and_urgency',3,'collaboration_intensity',5,'stakeholder_load',5,'cognitive_complexity',3,'adversity_exposure',3,'psychological_safety_dependence',3,'feedback_frequency',3,'coherence_check_passed',true,'notes', jsonb_build_array('DEV STUB'),'_dev_stub',true),
    'values_and_motivation', jsonb_build_object('schwartz_values', jsonb_build_object('benevolence','high','universalism','medium','_dev_stub',true),'sdt_needs_supply', jsonb_build_object('autonomy','medium','competence','medium','relatedness','high','_dev_stub',true),'_dev_stub',true),
    'success_criteria', jsonb_build_array(
      jsonb_build_object('horizon','90_day','dimension','contextual_ocb','behaviour','DEV STUB — onboarding map','_dev_stub',true),
      jsonb_build_object('horizon','annual','dimension','task','behaviour','DEV STUB — NRR >= 110%','_dev_stub',true)
    ),
    'evolution_vector', jsonb_build_object('_label','forecast','_dev_stub',true,'horizon_months',18,'confidence','low','next_review_date','2027-01-01','narrative','DEV STUB — Outcome data literacy rising.','likely_to_rise', jsonb_build_array(jsonb_build_object('attribute','data_literacy','delta','+0.15','_dev_stub',true)),'likely_to_fall','[]'::jsonb,'sources', jsonb_build_array('DEV STUB — Industry survey')),
    'team_gap_context', jsonb_build_object('_dev_stub',true,'_peer_rating_blocked_at_schema',true,'note','DEV STUB — built from members own profiles; peer-personality rating blocked at schema level (SCIENCE-SPEC §7).','complementary_pull_traits', jsonb_build_array('extraversion'),'supplementary_pull_traits', jsonb_build_array('agreeableness','conscientiousness')),
    'validation_and_defensibility_metadata', jsonb_build_object('_dev_stub',true,'validation_method','pending_io_sme_panel','next_review_date','2026-12-31','framing_default','developmental'),
    '_dev_stub', true
  )::jsonb,
  '[]'::jsonb
);

insert into public.roles_catalog (org_id, title, family, is_template, status, version, definition_json, authored_by_json)
values (
  null, 'SAMPLE — People Leader (full shape, DEV STUB)', 'leadership', true, 'active', 1,
  jsonb_build_object(
    'identity_and_governance', jsonb_build_object('version_status','signed_off','signed_off_by', jsonb_build_array(jsonb_build_object('person_id','b1000000-0000-0000-0000-000000000001','at','2026-05-15T12:00:00Z','_dev_stub',true)),'validation_status','dev_stub','effective_from','2026-01-01','validation_evidence_refs', jsonb_build_array('DEV STUB sme-panel-2026-Q1'),'external_codes', jsonb_build_object('onet_soc','DEV-STUB 11-9151.00','esco','DEV-STUB 1342.5'),'_dev_stub',true),
    'task_layer', jsonb_build_array(jsonb_build_object('task','DEV STUB — Set team OKRs','criticality','critical','frequency','quarterly','outcomes','Team alignment','tools','OKR cadence','_dev_stub',true)),
    'competencies', jsonb_build_array(
      jsonb_build_object('key','people_development','name','People Development','weight',0.40,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','sme_delphi','framework_mapping','KFLA: Develops Talent','_dev_stub',true),
      jsonb_build_object('key','strategic_alignment','name','Strategic Alignment','weight',0.30,'criticality','critical','description','DEV STUB','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','cit','framework_mapping','UCF: Leading','_dev_stub',true),
      jsonb_build_object('key','psychological_safety_setting','name','Setting Psychological Safety','weight',0.30,'criticality','critical','description','DEV STUB — Edmondson 1999','bars_anchors', jsonb_build_array('A','B','C'),'derivation_method','sme_delphi','framework_mapping','Edmondson 1999','_dev_stub',true)
    ),
    'trait_targets', jsonb_build_array(
      jsonb_build_object('trait','agreeableness','direction','optimum','centre',0.65,'lower',0.50,'upper',0.85,'weight',0.30,'justification','DEV STUB — coaching + feedback intensity','evidence_refs', jsonb_build_array('DEV STUB'),'_dev_stub',true),
      jsonb_build_object('trait','emotional_stability','direction','optimum','centre',0.70,'lower',0.55,'upper',0.85,'weight',0.30,'justification','DEV STUB — high pressure','evidence_refs', jsonb_build_array('Pierce & Aguinis 2013'),'_dev_stub',true),
      jsonb_build_object('trait','openness','direction','optimum','centre',0.65,'lower',0.50,'upper',0.85,'weight',0.20,'justification','DEV STUB','evidence_refs','[]'::jsonb,'_dev_stub',true),
      jsonb_build_object('trait','extraversion','direction','minimum_threshold','centre',0.55,'lower',0.45,'weight',0.20,'justification','DEV STUB — minimum-threshold for visible leader','evidence_refs', jsonb_build_array('DEV STUB'),'_dev_stub',true)
    ),
    'cognitive_demand', jsonb_build_object('complexity_level',4,'complexity_level_justification','DEV STUB','target_band', jsonb_build_object('lower',0.60,'upper',0.85,'_dev_stub',true),'use_as','banded','validity_estimate_range', jsonb_build_object('low',0.23,'high',0.40,'_dev_stub',true,'caveat','Sackett 2022 range'),'_dev_stub',true),
    'context_factors', jsonb_build_object('autonomy',4,'ambiguity_tolerance_required',4,'pace_and_urgency',3,'collaboration_intensity',5,'stakeholder_load',5,'cognitive_complexity',4,'adversity_exposure',3,'psychological_safety_dependence',5,'feedback_frequency',4,'coherence_check_passed',true,'notes', jsonb_build_array('DEV STUB — psych-safety-dep=5 coherent with agreeableness optimum'),'_dev_stub',true),
    'values_and_motivation', jsonb_build_object('schwartz_values', jsonb_build_object('benevolence','high','self_direction','high','_dev_stub',true),'sdt_needs_supply', jsonb_build_object('autonomy','high','competence','high','relatedness','high','_dev_stub',true),'_dev_stub',true),
    'success_criteria', jsonb_build_array(
      jsonb_build_object('horizon','90_day','dimension','contextual_ocb','behaviour','DEV STUB — first 1:1 cycle','_dev_stub',true),
      jsonb_build_object('horizon','six_month','dimension','leadership','behaviour','DEV STUB — team psych safety score measured','_dev_stub',true),
      jsonb_build_object('horizon','annual','dimension','leadership','behaviour','DEV STUB — promoted one direct report','_dev_stub',true)
    ),
    'evolution_vector', jsonb_build_object('_label','forecast','_dev_stub',true,'horizon_months',24,'confidence','medium','next_review_date','2027-05-01','narrative','DEV STUB — Async + cross-cultural leadership rising.','likely_to_rise', jsonb_build_array(jsonb_build_object('attribute','async_leadership','delta','+0.20','_dev_stub',true),jsonb_build_object('attribute','cross_cultural_fluency','delta','+0.15','_dev_stub',true)),'likely_to_fall', jsonb_build_array(jsonb_build_object('attribute','office_presence_signals','delta','-0.10','_dev_stub',true)),'sources', jsonb_build_array('DEV STUB — WEF 2026','DEV STUB — SME panel')),
    'team_gap_context', jsonb_build_object('_dev_stub',true,'_peer_rating_blocked_at_schema',true,'note','DEV STUB — built from members own profiles; peer-personality rating blocked at schema level (SCIENCE-SPEC §7).','complementary_pull_traits', jsonb_build_array('conscientiousness'),'supplementary_pull_traits', jsonb_build_array('agreeableness','emotional_stability')),
    'validation_and_defensibility_metadata', jsonb_build_object('_dev_stub',true,'validation_method','pending_io_sme_panel','next_review_date','2026-12-31','framing_default','developmental'),
    '_dev_stub', true
  )::jsonb,
  '[]'::jsonb
);
