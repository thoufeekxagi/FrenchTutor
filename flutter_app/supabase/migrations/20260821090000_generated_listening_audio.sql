-- Persist the exact rendered listening clip for replay across route changes,
-- sign-in hydration, and reinstalls. Audio is private and learner-scoped.
alter table public.generated_stories
  add column if not exists audio_path text,
  add column if not exists audio_mode text;

insert into storage.buckets (id, name, public)
values ('listening-audio', 'listening-audio', false)
on conflict (id) do update set public = false;

drop policy if exists "learners read their own listening audio"
  on storage.objects;
create policy "learners read their own listening audio"
on storage.objects for select to authenticated
using (
  bucket_id = 'listening-audio'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "learners upload their own listening audio"
  on storage.objects;
create policy "learners upload their own listening audio"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'listening-audio'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "learners update their own listening audio"
  on storage.objects;
create policy "learners update their own listening audio"
on storage.objects for update to authenticated
using (
  bucket_id = 'listening-audio'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'listening-audio'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "learners delete their own listening audio"
  on storage.objects;
create policy "learners delete their own listening audio"
on storage.objects for delete to authenticated
using (
  bucket_id = 'listening-audio'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
