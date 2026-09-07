-- Shared, cross-learner cache for one-word contextual meaning lookups (the
-- "tap a word to see its meaning" panel in Reading/Course/Listening). A
-- word's meaning in a given sentence at a given CEFR level never changes
-- and carries no learner-specific data, so unlike vocabulary_audio_cache/
-- generated_listening_audio (private, per-learner) this is intentionally a
-- single shared table: the same (word, sentence, level) triggers exactly
-- one model call ever, across every learner who ever taps that word in
-- that sentence, not once per learner. Popular authored content (Course's
-- Unit 2, curated Practice library stories) is read by many learners, so
-- this is where the real savings are.
create table public.word_meaning_cache (
  cache_key text primary key,
  word text not null,
  sentence text not null,
  level_band text not null,
  response_json jsonb not null,
  created_at timestamptz not null default now()
);

comment on table public.word_meaning_cache is
  'Shared, non-learner-specific cache of one-word contextual meaning lookups. Public read; any authenticated learner may add a missing entry.';

alter table public.word_meaning_cache enable row level security;

create policy "anyone can read word meaning cache"
on public.word_meaning_cache
for select
using (true);

create policy "authenticated learners can add word meaning cache entries"
on public.word_meaning_cache
for insert
to authenticated
with check (true);

grant select on table public.word_meaning_cache to anon, authenticated;
grant insert on table public.word_meaning_cache to authenticated;
