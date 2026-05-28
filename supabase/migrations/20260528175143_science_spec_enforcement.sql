-- science_spec_enforcement — structural rules from SCIENCE-SPEC.md.
--
-- 1. assessment_instruments DENY-LIST CHECK: MBTI / DISC / VARK / Belbin
--    (SCIENCE-SPEC §3.2). The catalogue is the single point at which
--    measurement content enters the system; refused at the DB layer.
-- 2. consent_purpose: add 'fairness_monitoring' so sensitive-attribute
--    collection (AI Act Art 10.5) has its own purpose-limited grant.
-- 3. guidance_items.refusal_kind + guidance_refusal_kind enum so a
--    refused query is a first-class, audited, GROUNDED row (cites the
--    refusal policy framework).
-- 4. lifecycle_decisions table — post-hire human decisions (promotion,
--    PIP, RIF, etc.) with required rationale + override flag (§5).

alter table public.assessment_instruments
  add constraint chk_assessment_instruments_deny_list
  check (
    not (
      lower(coalesce(key,   '')) ~ '(mbti|myers[\s_-]?briggs|disc[\s_-]?profile|disc[\s_-]?assessment|disc[\s_-]?model|^disc$|vark|kolb[\s_-]?learning|learning[\s_-]?styles|belbin)'
      or lower(coalesce(name,  '')) ~ '(mbti|myers[\s_-]?briggs|\bdisc\b|vark|learning[\s_-]?styles|belbin)'
      or lower(coalesce(vendor,'')) ~ '(mbti|cpp[\s_-]?\(myers|wiley[\s_-]?disc|everything[\s_-]?disc|belbin)'
    )
  );
comment on constraint chk_assessment_instruments_deny_list on public.assessment_instruments is
  'SCIENCE-SPEC §3.2: MBTI / DISC / learning-styles / Belbin cannot be ingested as scored instruments.';

alter type public.consent_purpose add value if not exists 'fairness_monitoring';

create type public.guidance_refusal_kind as enum (
  'medical', 'legal', 'dismissal', 'compensation', 'out_of_scope'
);

alter table public.guidance_items
  add column refusal_kind public.guidance_refusal_kind;
comment on column public.guidance_items.refusal_kind is
  'If set, the row is a REFUSED query (SCIENCE-SPEC §6). output_json carries the structured refusal + redirection; framework_ids still cites the refusal policy.';

create or replace function public._infer_guidance_refusal(p_context_json jsonb)
returns public.guidance_refusal_kind
language sql immutable set search_path = ''
as $$
  with hints as (
    select coalesce(
      p_context_json->>'refusal_kind',
      p_context_json->>'topic',
      p_context_json->>'question',
      ''
    ) as h
  )
  select case
    when (select h from hints) ~* '(medical|diagnos|prognos|illness|accommodation|disability|sick)' then 'medical'::public.guidance_refusal_kind
    when (select h from hints) ~* '(dismiss|terminat|fire[d]?|pip|performance improvement plan|severance|layoff|exit)' then 'dismissal'::public.guidance_refusal_kind
    when (select h from hints) ~* '(legal|lawyer|attorney|sue|lawsuit|contract|gdpr|regulat)' then 'legal'::public.guidance_refusal_kind
    when (select h from hints) ~* '(salary|compensat|raise|bonus|equity|pay band|payband)' then 'compensation'::public.guidance_refusal_kind
    else null
  end;
$$;
revoke execute on function public._infer_guidance_refusal(jsonb) from public;
grant  execute on function public._infer_guidance_refusal(jsonb) to authenticated, service_role, anon;

insert into public.frameworks (org_id, key, kind, name, body_json, validity_status, _dev_stub, vendor) values
(null, 'refusal_policy_v0', 'manager_prompt',
  'DEV STUB · Refusal policy — direct out-of-scope queries',
  jsonb_build_object(
    'medical',      'Direct to occupational health. Do not generate a diagnosis, prognosis, or accommodation determination.',
    'legal',        'Direct to legal counsel. Do not provide dismissal grounds, contract interpretation, or regulatory defence.',
    'dismissal',    'Capture in growth_conversations and require legal + HR sign-off out-of-band.',
    'compensation', 'Direct to compensation team. Frameworks library carries no salary data.',
    'out_of_scope', 'Out of scope for the guidance composer. Capture in growth_conversations.',
    'citation',     'SCIENCE-SPEC.md §6 (DEV STUB)',
    '_dev_stub',    true
  ),
  'dev_stub', true, 'HeiTobias (SCIENCE-SPEC DEV STUB)')
on conflict (org_id, key, version) do nothing;

create type public.lifecycle_decision_kind as enum (
  'promotion', 'lateral_move', 'role_change', 'pip', 'rif', 'retain'
);

create table public.lifecycle_decisions (
  id                      uuid primary key default extensions.gen_random_uuid(),
  org_id                  uuid not null references public.organizations(id),
  person_id               uuid not null references public.people(id),
  consent_id              uuid not null references public.consent_grants(id),
  kind                    public.lifecycle_decision_kind not null,
  rationale               text not null,
  overrode_recommendation boolean not null default false,
  recommendation_summary  text,
  refit_evaluation_id     uuid references public.refit_evaluations(id),
  guidance_item_id        uuid references public.guidance_items(id),
  decided_by              uuid not null references public.people(id),
  decided_at              timestamptz not null default now(),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint chk_lifecycle_decisions_rationale_nonempty
    check (length(btrim(rationale)) > 0)
);
create index lifecycle_decisions_person_idx on public.lifecycle_decisions (person_id, decided_at desc);
create trigger trg_touch_lifecycle_decisions before update on public.lifecycle_decisions
  for each row execute function public.set_updated_at();
create trigger trg_audit_lifecycle_decisions after insert or update or delete on public.lifecycle_decisions
  for each row execute function public._audit_row();
alter table public.lifecycle_decisions enable row level security;
alter table public.lifecycle_decisions force  row level security;
create policy lifecycle_decisions_select on public.lifecycle_decisions for select using (
  public.is_self(person_id)
  or (public.has_permission(org_id,'guidance.read')
      and public.in_scope(org_id, person_id)
      and public.consent_active(consent_id,'ongoing_management'))
);
create policy lifecycle_decisions_insert on public.lifecycle_decisions for insert with check (
  public.has_permission(org_id,'org.manage_all')
  and public.consent_active(consent_id,'ongoing_management')
);
