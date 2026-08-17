-- Keep the independent Reading and Listening shelves separate while sharing
-- the same story/quiz/cover storage contract.
alter table public.generated_stories
  add column if not exists practice_mode text not null default 'reading';

alter table public.generated_stories
  add constraint generated_stories_practice_mode_check
  check (practice_mode in ('reading', 'listening'));

create index if not exists idx_generated_stories_user_mode_created
  on public.generated_stories (user_id, practice_mode, created_at desc);
