-- Per-learner validated Grammar V2 sessions.
-- Each row contains one bounded 4-5 step lesson in session_json. Individual
-- steps are intentionally not separate rows or library cards.
create table if not exists public.grammar_course_sessions (
  id text primary key,
  mode text not null check (mode in ('guided', 'complete', 'roleplay')),
  tense text not null,
  level_band text not null check (level_band in ('A1', 'A2', 'B1', 'B2')),
  title text not null,
  grammar_focus text not null,
  fingerprint text not null,
  session_json jsonb not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  is_validated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (created_by, mode, tense, level_band, fingerprint)
);

create index if not exists idx_grammar_course_sessions_owner_filter
  on public.grammar_course_sessions (created_by, mode, tense, level_band, created_at)
  where is_validated = true and deleted_at is null;

alter table public.grammar_course_sessions enable row level security;

drop policy if exists "owners can read grammar course sessions"
  on public.grammar_course_sessions;
create policy "owners can read grammar course sessions"
  on public.grammar_course_sessions for select
  to authenticated
  using (created_by = auth.uid() and is_validated = true and deleted_at is null);

drop policy if exists "owners can create grammar course sessions"
  on public.grammar_course_sessions;
create policy "owners can create grammar course sessions"
  on public.grammar_course_sessions for insert
  to authenticated
  with check (created_by = auth.uid() and is_validated = true);

drop policy if exists "owners can update grammar course sessions"
  on public.grammar_course_sessions;
create policy "owners can update grammar course sessions"
  on public.grammar_course_sessions for update
  to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid() and is_validated = true);

drop policy if exists "owners can delete grammar course sessions"
  on public.grammar_course_sessions;
create policy "owners can delete grammar course sessions"
  on public.grammar_course_sessions for delete
  to authenticated
  using (created_by = auth.uid());

revoke all on public.grammar_course_sessions from anon, authenticated;
grant select, insert, update, delete on public.grammar_course_sessions to authenticated;

comment on table public.grammar_course_sessions is
  'Per-learner validated Grammar V2 sessions with nested 4-5 step flows.';
