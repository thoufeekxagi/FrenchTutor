-- Learner-owned vocabulary libraries, including starter content assigned at
-- sign-in. The rows are private; cover images use the private story-covers
-- bucket and signed URLs rather than public storage URLs.
create table if not exists public.generated_vocabulary_sets (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  summary text not null default '',
  topic text not null default '',
  level_band text not null default 'A1',
  entries_json jsonb not null default '[]'::jsonb,
  cover_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.generated_vocabulary_sets enable row level security;

drop policy if exists "learners manage their own vocabulary sets"
  on public.generated_vocabulary_sets;
create policy "learners manage their own vocabulary sets"
  on public.generated_vocabulary_sets
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.generated_vocabulary_sets from anon;
grant select, insert, update on public.generated_vocabulary_sets to authenticated;

create index if not exists idx_generated_vocabulary_sets_user_created
  on public.generated_vocabulary_sets (user_id, created_at desc);
