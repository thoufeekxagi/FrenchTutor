-- Connect the adaptive Course roadmap to the learner evidence that shaped
-- each future lesson. Existing rows remain valid and receive empty arrays.

alter table public.adaptive_course_sessions
  add column if not exists target_phrases_json jsonb not null default '[]'::jsonb,
  add column if not exists source_session_ids_json jsonb not null default '[]'::jsonb;

comment on column public.adaptive_course_sessions.target_phrases_json is
  'Learner-relevant phrases selected from recent Course and Practice evidence.';

comment on column public.adaptive_course_sessions.source_session_ids_json is
  'Canonical practice/session ids used when building this Course session.';
