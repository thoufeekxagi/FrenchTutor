-- Per-learner progress for the bundled V3 authored course. The local SQLite
-- copy is immediate; this account-scoped table restores progress on sign-in.
create table if not exists public.v3_course_progress_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_id text not null,
  status text not null check (status in ('in_progress', 'completed')),
  current_step integer not null default 0 check (current_step >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create index if not exists v3_course_progress_state_user_updated_idx
  on public.v3_course_progress_state (user_id, updated_at desc);

alter table public.v3_course_progress_state enable row level security;
revoke all on table public.v3_course_progress_state from anon, authenticated;
grant select, insert, update on table public.v3_course_progress_state
  to authenticated;

drop policy if exists v3_course_progress_select_own
  on public.v3_course_progress_state;
create policy v3_course_progress_select_own
  on public.v3_course_progress_state
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists v3_course_progress_insert_own
  on public.v3_course_progress_state;
create policy v3_course_progress_insert_own
  on public.v3_course_progress_state
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists v3_course_progress_update_own
  on public.v3_course_progress_state;
create policy v3_course_progress_update_own
  on public.v3_course_progress_state
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- The exam deadline is learner-specific profile data, not a device-only
-- preference, so the Home countdown restores with the same account.
alter table public.profiles
  add column if not exists tcf_exam_date date;
