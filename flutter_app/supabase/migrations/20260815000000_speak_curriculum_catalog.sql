-- Published course catalog for the Speak-style path. This is shared content,
-- not learner-owned data: users can read published rows, while generation and
-- publishing happen through a server-side job or Supabase service role.
create table if not exists public.course_sessions (
  content_key text primary key,
  level text not null check (level in ('A1', 'A2', 'B1', 'B2')),
  unit_number integer not null check (unit_number > 0),
  unit_title text not null,
  session_index integer not null check (session_index >= 0),
  title text not null,
  subtitle text not null,
  kind text not null check (kind in (
    'build', 'choice', 'choose', 'elaborate', 'listen', 'listening',
    'review', 'roleplay', 'speaking', 'story', 'use', 'video'
  )),
  primary_skill text not null default 'speaking',
  supporting_skills jsonb not null default '[]'::jsonb,
  estimated_minutes integer not null default 8 check (estimated_minutes > 0),
  target_phrases jsonb not null default '[]'::jsonb,
  roleplay_scene jsonb,
  published boolean not null default false,
  content_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (level, session_index),
  unique (level, unit_number, title)
);

alter table public.course_sessions
  add column if not exists primary_skill text not null default 'speaking';
alter table public.course_sessions
  add column if not exists supporting_skills jsonb not null default '[]'::jsonb;

comment on table public.course_sessions is 'Versioned, reviewed course content shared by all learners.';

create index if not exists idx_course_sessions_published_level
  on public.course_sessions (level, session_index)
  where published = true;

alter table public.course_sessions enable row level security;

drop policy if exists "anyone can read published course sessions" on public.course_sessions;
create policy "anyone can read published course sessions"
  on public.course_sessions for select
  using (published = true);

-- Make the intended Data API surface explicit. The mobile client only needs
-- published reads; generation and publishing must stay server-side with the
-- service role and must never be possible from the public app key.
revoke all on public.course_sessions from anon, authenticated;
grant select on public.course_sessions to anon, authenticated;

-- Existing session history is learner-owned. Adding content_key is additive,
-- so older sessions continue to hydrate with a null key.
alter table if exists public.sessions_state
  add column if not exists content_key text;

create index if not exists idx_sessions_state_user_content_key
  on public.sessions_state (user_id, content_key)
  where content_key is not null;
