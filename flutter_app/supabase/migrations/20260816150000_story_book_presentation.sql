-- Readle-inspired story-book presentation metadata and one generated cover.
-- The story body remains in generated_stories.passage_json; these fields are
-- stable library metadata so reopening a story never calls Gemini again.
alter table public.generated_stories
  add column if not exists level_band text not null default 'A2',
  add column if not exists summary text not null default '',
  add column if not exists topic text not null default '',
  add column if not exists read_time_minutes integer not null default 5,
  add column if not exists cover_url text;

alter table public.generated_stories
  add constraint generated_stories_level_band_check
  check (upper(level_band) in ('A1', 'A2', 'B1', 'B2'));

-- Covers are generated artwork, not learner transcripts or private lesson
-- content. Keeping them in a public bucket avoids signed-URL refresh churn in
-- the library cards while the story row itself remains RLS-protected.
insert into storage.buckets (id, name, public)
values ('story-covers', 'story-covers', true)
on conflict (id) do update set public = excluded.public;

create policy "learners upload their own story covers"
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'story-covers'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

create policy "learners update their own story covers"
on storage.objects
for update to authenticated
using (
  bucket_id = 'story-covers'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
)
with check (
  bucket_id = 'story-covers'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

create policy "learners read their own story covers"
on storage.objects
for select to authenticated
using (
  bucket_id = 'story-covers'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

create policy "anyone can read story covers"
on storage.objects
for select to anon
using (bucket_id = 'story-covers');
