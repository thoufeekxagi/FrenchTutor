-- Learner-owned AI-generated writing prompts. Submissions remain in the
-- append-only learner_events stream; this table preserves the prompt itself
-- and its generated cover for reopenable Writing-lab history.
create table if not exists public.generated_writing_tasks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  task_json jsonb not null,
  level_band text not null default 'A2',
  cover_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.generated_writing_tasks enable row level security;

drop policy if exists "learners manage their own writing tasks"
  on public.generated_writing_tasks;
create policy "learners manage their own writing tasks"
  on public.generated_writing_tasks
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.generated_writing_tasks from anon;
grant select, insert, update on public.generated_writing_tasks to authenticated;

create index if not exists idx_generated_writing_tasks_user_created
  on public.generated_writing_tasks (user_id, created_at desc);
