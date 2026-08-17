-- Private Gemini Live PCM clips for learner-owned vocabulary and lesson words.
-- Audio is never public: every object and row is scoped to auth.uid().
create table if not exists public.vocabulary_audio_cache (
  user_id uuid not null references auth.users(id) on delete cascade,
  cache_key text not null,
  content_item_id text not null,
  spoken_text text not null,
  voice_name text not null,
  storage_path text not null unique,
  sha256 text not null,
  bytes integer not null check (bytes > 0),
  sample_rate_hz integer not null default 24000,
  channels integer not null default 1,
  encoding text not null default 'pcm_s16le',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, cache_key)
);

alter table public.vocabulary_audio_cache enable row level security;

drop policy if exists "learners manage their own vocabulary audio cache"
  on public.vocabulary_audio_cache;
create policy "learners manage their own vocabulary audio cache"
  on public.vocabulary_audio_cache
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.vocabulary_audio_cache from anon;
grant select, insert, update, delete on public.vocabulary_audio_cache to authenticated;

insert into storage.buckets (id, name, public)
values ('vocabulary-audio', 'vocabulary-audio', false)
on conflict (id) do update set public = false;

drop policy if exists "learners read their own vocabulary audio"
  on storage.objects;
create policy "learners read their own vocabulary audio"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "learners upload their own vocabulary audio"
  on storage.objects;
create policy "learners upload their own vocabulary audio"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "learners update their own vocabulary audio"
  on storage.objects;
create policy "learners update their own vocabulary audio"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "learners delete their own vocabulary audio"
  on storage.objects;
create policy "learners delete their own vocabulary audio"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
