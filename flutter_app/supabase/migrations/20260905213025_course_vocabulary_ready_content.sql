-- Persist the complete Course vocabulary artifact before a learner can open
-- its Adaptive Course session. Existing independent library sets remain
-- valid with no course_session_id and an empty examples object.

alter table public.generated_vocabulary_sets
  add column if not exists course_session_id uuid
    references public.adaptive_course_sessions(id) on delete cascade,
  add column if not exists examples_json jsonb not null default '{}'::jsonb;

create unique index if not exists idx_generated_vocabulary_course_session
  on public.generated_vocabulary_sets (course_session_id)
  where course_session_id is not null and deleted_at is null;

comment on column public.generated_vocabulary_sets.course_session_id is
  'Owning Adaptive Course session. Null only for independent Vocabulary library sets.';

comment on column public.generated_vocabulary_sets.examples_json is
  'Prepared bilingual sentence/story beats keyed by vocabulary entry id.';
