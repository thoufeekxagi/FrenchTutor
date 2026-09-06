-- Course taps are render-only. The complete generated payload and its durable
-- preparation state live on the learner-owned Adaptive Course session.

alter table public.adaptive_course_sessions
  add column if not exists target_phrases_json jsonb not null default '[]'::jsonb,
  add column if not exists source_session_ids_json jsonb not null default '[]'::jsonb,
  add column if not exists generation_status text not null default 'queued',
  add column if not exists artifact_kind text,
  add column if not exists artifact_json jsonb,
  add column if not exists generation_version integer not null default 1,
  add column if not exists generation_attempts integer not null default 0,
  add column if not exists generation_error text;

update public.adaptive_course_sessions
set generation_status = 'ready',
    generation_error = null
where sequence <= 5;

update public.adaptive_course_sessions
set generation_status = 'queued'
where sequence > 5
  and artifact_json is null
  and status not in ('completed', 'replaced');

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'adaptive_course_generation_status_check'
      and conrelid = 'public.adaptive_course_sessions'::regclass
  ) then
    alter table public.adaptive_course_sessions
      add constraint adaptive_course_generation_status_check
      check (generation_status in ('queued', 'generating', 'ready', 'failed'));
  end if;
end
$$;

create index if not exists idx_adaptive_course_sessions_generation
  on public.adaptive_course_sessions (user_id, generation_status, sequence)
  where deleted_at is null;

comment on column public.adaptive_course_sessions.artifact_json is
  'Complete validated Course payload. Practice screens render this value and never generate from a Course tap.';

comment on column public.adaptive_course_sessions.generation_status is
  'Durable server-owned preparation state: queued, generating, ready, or failed.';
