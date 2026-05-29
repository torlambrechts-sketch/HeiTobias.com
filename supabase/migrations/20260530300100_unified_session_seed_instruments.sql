-- Unified session seeded dev_stub instruments: cognitive + values.
-- Prompts are clearly synthetic ("Sample matrix item ... DEV STUB ...").
-- Real items + IRT calibration land per H-1 / H-2.

do $$
declare v_cog uuid; v_val uuid; i int;
declare schwartz_themes text[] := array['power','achievement','hedonism','stimulation','self_direction',
                                         'universalism','benevolence','tradition','conformity','security',
                                         'power','achievement','hedonism','stimulation','self_direction',
                                         'universalism','benevolence','tradition','conformity','security','power'];
declare sdt_themes    text[] := array['autonomy','competence','relatedness'];
begin
  select id into v_cog from public.assessment_instruments where key = 'sample_cognitive_v0' limit 1;
  if v_cog is null then
    insert into public.assessment_instruments (id, key, name, vendor, validity_status, version, body_json)
    values (extensions.gen_random_uuid(), 'sample_cognitive_v0',
      'SAMPLE Matrix Reasoning (DEV STUB)', 'heitobias-internal', 'dev_stub', '0.1',
      '{"item_count": 25, "demo_item_count": 10, "scale": "matrix_choice_5", "_dev_stub": true,
        "_note": "Pending H-1 sign-off + IRT calibration on real Nordic norm sample (H-2)"}'::jsonb)
    returning id into v_cog;
  end if;
  if (select count(*) from public.assessment_items where instrument_id = v_cog) < 25 then
    delete from public.assessment_items where instrument_id = v_cog;
    for i in 1..25 loop
      insert into public.assessment_items (instrument_id, key, prompt, item_type, item_json, _dev_stub)
      values (v_cog, 'matrix_' || i,
        'Sample matrix item ' || i || ' — which figure completes the pattern? (DEV STUB — pending H-1 sign-off + IRT calibration)',
        'timed',
        jsonb_build_object('choices', jsonb_build_array(1,2,3,4,5),
                            'time_limit_seconds', 90, 'scale','matrix_choice_5',
                            '_dev_stub_prompt', true), true);
    end loop;
  end if;

  select id into v_val from public.assessment_instruments where key = 'sample_values_v0' limit 1;
  if v_val is null then
    insert into public.assessment_instruments (id, key, name, vendor, validity_status, version, body_json)
    values (extensions.gen_random_uuid(), 'sample_values_v0',
      'SAMPLE Schwartz PVQ-21 + SDT (DEV STUB)', 'heitobias-internal', 'dev_stub', '0.1',
      '{"item_count": 24, "demo_item_count": 8, "scale": "likert_6", "_dev_stub": true,
        "_note": "Production item content requires Schwartz PVQ-21 licensing; SDT items per Deci & Ryan."}'::jsonb)
    returning id into v_val;
  end if;
  if (select count(*) from public.assessment_items where instrument_id = v_val) < 24 then
    delete from public.assessment_items where instrument_id = v_val;
    for i in 1..21 loop
      insert into public.assessment_items (instrument_id, key, prompt, item_type, item_json, _dev_stub)
      values (v_val, 'pvq_' || i,
        'Sample portrait ' || i || ': someone for whom ' || schwartz_themes[i] || ' matters a great deal (DEV STUB). How similar is this person to you?',
        'likert',
        jsonb_build_object('choices', jsonb_build_array(1,2,3,4,5,6),
                            'scale_anchor_low','Not like me at all',
                            'scale_anchor_high','Very much like me',
                            '_theme', schwartz_themes[i], '_dev_stub_prompt', true), true);
    end loop;
    for i in 1..3 loop
      insert into public.assessment_items (instrument_id, key, prompt, item_type, item_json, _dev_stub)
      values (v_val, 'sdt_' || sdt_themes[i],
        'Sample SDT item — how important is ' || sdt_themes[i] || ' to you in your work? (DEV STUB)',
        'likert',
        jsonb_build_object('choices', jsonb_build_array(1,2,3,4,5,6),
                            'scale_anchor_low','Not important',
                            'scale_anchor_high','Essential',
                            '_theme', sdt_themes[i], '_sdt', true, '_dev_stub_prompt', true), true);
    end loop;
  end if;
end$$;
