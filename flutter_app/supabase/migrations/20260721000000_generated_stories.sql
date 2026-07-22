-- A learner's personal library of AI-generated bilingual stories (Story/Quiz/
-- Keywords/Grammar tabs — see StoryReaderScreen). Replaces the old browsable
-- list of hardcoded listening.json exercises; each row is a full story the
-- learner generated themselves, synced so it survives sign-out/sign-in and
-- reinstalls, same as vocab_card_state / daily_session_state.
create table public.generated_stories (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  passage_json jsonb not null,
  quiz_json jsonb not null default '[]',
  keywords_json jsonb not null default '[]',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.generated_stories is 'A learner''s saved AI-generated stories (passage + quiz + keywords), one row per story, owned by the learner.';

create index idx_generated_stories_user_created on public.generated_stories (user_id, created_at desc);

alter table public.generated_stories enable row level security;

create policy "learners manage their own stories" on public.generated_stories
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
