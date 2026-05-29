-- hardening_f4_refusal_precedence — audit finding F-4. Reordering the
-- guidance refusal classifier so dismissal/termination/PIP language
-- takes precedence over generic 'legal' vocabulary. Per SCIENCE-SPEC
-- §6 the consequential action drives the category.
--
-- New order: medical → dismissal → compensation → legal.

create or replace function public._infer_guidance_refusal(p_context_json jsonb)
returns public.guidance_refusal_kind
language sql immutable set search_path to ''
as $$
  with hints as (
    select coalesce(p_context_json->>'refusal_kind', p_context_json->>'topic', p_context_json->>'question', '') as h
  )
  select case
    when (select h from hints) ~* '(medical|diagnos|prognos|illness|accommodation|disability|sick)' then 'medical'::public.guidance_refusal_kind
    when (select h from hints) ~* '(dismiss|terminat|fire[d]?|pip|performance improvement plan|severance|layoff|exit)' then 'dismissal'::public.guidance_refusal_kind
    when (select h from hints) ~* '(salary|compensat|raise|bonus|equity|pay band|payband)' then 'compensation'::public.guidance_refusal_kind
    when (select h from hints) ~* '(legal|lawyer|attorney|sue|lawsuit|contract|gdpr|regulat)' then 'legal'::public.guidance_refusal_kind
    else null
  end;
$$;
