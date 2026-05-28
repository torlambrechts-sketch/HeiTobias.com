-- assessment_sample_instrument — Phase 1 Step 4.
-- Seed a SINGLE clearly-DEV-STUB instrument so the assessment pipeline can be
-- exercised end-to-end. Every row carries validity_status='dev_stub' / _dev_stub=true.
-- The seed-guard test asserts no row in this seed has validity_status='validated'.

insert into public.assessment_instruments (
  org_id, key, version, name, vendor, validity_status, body_json
) values (
  null, 'sample_personality_v0', '0.0.1-dev',
  'DEV STUB — Sample Personality Inventory',
  'HeiTobias (DEV STUB)',
  'dev_stub',
  jsonb_build_object(
    'scales',      jsonb_build_array('openness','conscientiousness','extraversion','agreeableness','neuroticism'),
    'description', 'DEV STUB — replace with licensed instrument + I/O-validated scoring'
  )
)
on conflict do nothing;

do $$
declare v_instr_id uuid;
begin
  select id into v_instr_id from public.assessment_instruments
    where key = 'sample_personality_v0' and org_id is null;

  insert into public.assessment_items (instrument_id, key, item_type, prompt, item_json, _dev_stub) values
    (v_instr_id, 'item_openness_1',
     'likert', 'DEV STUB — I have a vivid imagination.',
     jsonb_build_object('scale','openness','direction',1,'choices',jsonb_build_array(1,2,3,4,5)), true),
    (v_instr_id, 'item_conscientiousness_1',
     'likert', 'DEV STUB — I pay attention to details.',
     jsonb_build_object('scale','conscientiousness','direction',1,'choices',jsonb_build_array(1,2,3,4,5)), true),
    (v_instr_id, 'item_extraversion_1',
     'likert', 'DEV STUB — I feel comfortable around people.',
     jsonb_build_object('scale','extraversion','direction',1,'choices',jsonb_build_array(1,2,3,4,5)), true),
    (v_instr_id, 'item_agreeableness_1',
     'likert', 'DEV STUB — I am interested in people.',
     jsonb_build_object('scale','agreeableness','direction',1,'choices',jsonb_build_array(1,2,3,4,5)), true),
    (v_instr_id, 'item_neuroticism_1',
     'likert', 'DEV STUB — I get stressed out easily.',
     jsonb_build_object('scale','neuroticism','direction',1,'choices',jsonb_build_array(1,2,3,4,5)), true)
  on conflict do nothing;
end$$;
