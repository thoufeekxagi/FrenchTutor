-- Generated story artwork belongs to the learner who created the story.
-- The existing authenticated folder policies remain in force; remove the
-- anonymous/public read path so only alphabet audio stays public.
update storage.buckets
set public = false
where id = 'story-covers';

drop policy if exists "anyone can read story covers" on storage.objects;
