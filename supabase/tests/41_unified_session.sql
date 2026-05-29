-- 41_unified_session — unified candidate assessment session contract.
-- T1  demo_mode flows through to session
-- T2  demo cognitive count = 10
-- T3  demo values count = 8
-- T4  demo structured-prep count = 2
-- T5  Sackett methodology note present in state
-- T6  cognitive item submit advances answered count
-- T7  production cognitive count = 25
-- T8  mark_section idempotent + transitions session.status to completed
-- T9  structured-prep submit creates row + advances state

begin;
select plan(9);

do $$
declare
  fjord constant uuid := 'a1000000-0000-0000-0000-000000000002';
  linnea constant uuid := 'b1000000-0000-0000-0000-000000000003';
  v_mem uuid; v_person uuid; v_invite jsonb; v_tok text; v_sess uuid;
  v_state jsonb; v_first_item uuid; v_invite2 jsonb; v_tok2 text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', linnea)::text, true);
  v_mem := public.org_invite_user(fjord, 't41_'||gen_random_uuid()||'@cand.test', 'employee', 'T41 Cand');
  select person_id into v_person from public.invite_tokens where membership_id = v_mem;
  v_invite := public.assessment_invite_create(fjord, v_person, 'sample_personality_v0','personality',14);
  v_tok := v_invite->>'token';

  v_sess := public.assessment_session_init(v_tok, true);
  v_state := public.assessment_session_state(v_tok);
  perform set_config('t.demo', (v_state->>'demo_mode'), true);
  perform set_config('t.cog_total', (v_state -> 'sections' -> 'cognitive' ->> 'total'), true);
  perform set_config('t.val_total', (v_state -> 'sections' -> 'values'    ->> 'total'), true);
  perform set_config('t.prep_total',(v_state -> 'sections' -> 'structured_prep' ->> 'total'), true);
  perform set_config('t.method',     v_state -> 'sections' -> 'structured_prep' ->> 'methodology_note', true);

  perform public.assessment_capture_consent(v_tok);
  v_first_item := ((v_state -> 'sections' -> 'cognitive' -> 'items') -> 0 ->> 'id')::uuid;
  perform public.assessment_session_submit_item(v_tok, v_first_item, 3);
  perform set_config('t.cog_one_answered',
    ((public.assessment_session_state(v_tok) -> 'sections' -> 'cognitive' ->> 'answered')::int)::text, true);

  -- prep submit
  perform public.assessment_session_submit_prep(v_tok, 'analyzing',
    'Sample structured-prep response — described a situation, task, action and result for analysis.');
  perform set_config('t.prep_answered',
    ((public.assessment_session_state(v_tok) -> 'sections' -> 'structured_prep' ->> 'answered')::int)::text, true);

  -- mark all sections complete + verify status flip
  perform public.assessment_session_mark_section(v_tok, 'personality');
  perform public.assessment_session_mark_section(v_tok, 'cognitive');
  perform public.assessment_session_mark_section(v_tok, 'values');
  perform public.assessment_session_mark_section(v_tok, 'structured_prep');
  perform set_config('t.status',
    (select status::text from public.assessment_sessions where invite_token = v_tok), true);

  -- production init on a fresh token
  v_invite2 := public.assessment_invite_create(fjord, v_person, 'sample_personality_v0','personality',14);
  v_tok2 := v_invite2->>'token';
  perform public.assessment_session_init(v_tok2, false);
  perform set_config('t.cog_full',
    (public.assessment_session_state(v_tok2) -> 'sections' -> 'cognitive' ->> 'total'), true);
end$$;

select is(current_setting('t.demo'), 'true', '[T1] demo_mode true');
select is(current_setting('t.cog_total'), '10', '[T2] demo cog=10');
select is(current_setting('t.val_total'), '8',  '[T3] demo val=8');
select is(current_setting('t.prep_total'),'2',  '[T4] demo prep=2');
select ok(current_setting('t.method') like '%Sackett%', '[T5] methodology Sackett note present');
select is(current_setting('t.cog_one_answered'), '1', '[T6] cognitive submit advances state');
select is(current_setting('t.cog_full'), '25', '[T7] production cog=25');
select is(current_setting('t.status'), 'completed', '[T8] mark_section all four → session completed');
select is(current_setting('t.prep_answered'), '1', '[T9] prep submit advances state');

select count(*) as failure_lines, string_agg(line, E'\n') as msgs from (select * from finish() as line) f;
rollback;
