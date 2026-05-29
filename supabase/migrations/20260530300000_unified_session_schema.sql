-- Unified candidate assessment session — schema.
-- Adds session-level state that ties together personality / cognitive /
-- values / structured_interview_prep under one invite token. demo_mode
-- (?demo=true) flag flows through to every section + is visible on the
-- recruiter's candidate detail view.

create type public.unified_section as enum
  ('personality','cognitive','values','structured_prep');

create type public.unified_session_status as enum
  ('initializing','in_progress','completed','abandoned');

create table public.assessment_sessions (
  id                    uuid primary key default extensions.gen_random_uuid(),
  invite_id             uuid not null references public.assessment_invites(id) on delete cascade,
  invite_token          text not null unique,
  org_id                uuid not null references public.organizations(id),
  person_id             uuid not null references public.people(id),
  demo_mode             boolean not null default false,
  status                public.unified_session_status not null default 'initializing',
  sections_json         jsonb not null default '{}'::jsonb,
  started_at            timestamptz not null default now(),
  completed_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  is_demo_data          boolean not null default false
);
create index assessment_sessions_invite_idx on public.assessment_sessions (invite_token);
create index assessment_sessions_person_idx on public.assessment_sessions (person_id);
create trigger trg_touch_assessment_sessions before update on public.assessment_sessions for each row execute function public.set_updated_at();
create trigger trg_audit_assessment_sessions after insert or update or delete on public.assessment_sessions for each row execute function public._audit_row();
alter table public.assessment_sessions enable row level security;
alter table public.assessment_sessions force  row level security;
create policy assessment_sessions_org_read on public.assessment_sessions for select to authenticated using (
  public.has_permission(org_id, 'requisition.read')
);

create table public.assessment_prep_responses (
  id                    uuid primary key default extensions.gen_random_uuid(),
  session_id            uuid not null references public.assessment_sessions(id) on delete cascade,
  competency_key        text not null,
  competency_label      text not null,
  prompt_text           text not null,
  response_text         text,
  answered_at           timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (session_id, competency_key)
);
create index assessment_prep_responses_session_idx on public.assessment_prep_responses (session_id);
create trigger trg_touch_assessment_prep_responses before update on public.assessment_prep_responses for each row execute function public.set_updated_at();
alter table public.assessment_prep_responses enable row level security;
alter table public.assessment_prep_responses force  row level security;
create policy assessment_prep_responses_org_read on public.assessment_prep_responses for select to authenticated using (
  exists (select 1 from public.assessment_sessions s where s.id = session_id and public.has_permission(s.org_id, 'requisition.read'))
);
