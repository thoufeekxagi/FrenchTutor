-- Learner-owned story bookmarks.  This is separate from generated_stories so
-- changing a favorite does not mutate generated content or its timestamps.
create table if not exists public.story_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  story_id uuid not null references public.generated_stories(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, story_id)
);

create index if not exists idx_story_favorites_user_updated
  on public.story_favorites (user_id, updated_at desc);

alter table public.story_favorites enable row level security;

drop policy if exists "learners manage their own story favorites"
  on public.story_favorites;
create policy "learners manage their own story favorites"
  on public.story_favorites
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.story_favorites from anon;
grant select, insert, update, delete on public.story_favorites to authenticated;
