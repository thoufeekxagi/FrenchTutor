-- Unit 2's Listening lesson (sequence 9) is fixed, authored content that is
-- byte-identical for every learner, unlike the per-user personalized
-- listening lessons (sequence 11+) this bucket otherwise stores. Reading it
-- with the existing per-user policy would force every single new learner to
-- trigger a brand new, redundant TTS render of the exact same French text --
-- the same waste the alphabet-audio bucket's public policy already avoids
-- for the alphabet catalog. This adds one narrow, fixed-prefix policy for a
-- single shared object, without loosening access to any learner's own
-- personalized listening audio elsewhere in this bucket.
create policy "anyone can read shared course listening audio"
on storage.objects for select to authenticated
using (
  bucket_id = 'listening-audio'
  and (storage.foldername(name))[1] = 'course-shared'
);
