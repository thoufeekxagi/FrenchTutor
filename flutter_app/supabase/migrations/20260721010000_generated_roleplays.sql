-- A learner's personal library of AI-generated roleplay scenes (walked
-- through live in AgentLedListeningScreen, which acts as both the
-- in-character partner and the tutor). Mirrors generated_stories exactly,
-- minus the quiz/keywords columns a roleplay has no use for.
create table public.generated_roleplays (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  passage_json jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.generated_roleplays is 'A learner''s saved AI-generated roleplay scenes, one row per scene, owned by the learner.';

create index idx_generated_roleplays_user_created on public.generated_roleplays (user_id, created_at desc);

alter table public.generated_roleplays enable row level security;

create policy "learners manage their own roleplays" on public.generated_roleplays
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
