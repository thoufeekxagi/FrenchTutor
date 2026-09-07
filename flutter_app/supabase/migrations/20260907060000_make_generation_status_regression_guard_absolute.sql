-- Explicit product decision: once a course session is genuinely ready
-- with a real artifact, NOTHING may ever reset it back to
-- queued/no-artifact again, through any path, for any reason, including
-- one that attaches an explanatory generation_error. The previous version
-- of this trigger only blocked a *silent* reset (no error attached),
-- which is exactly what let a real bug (ensureCurrentPlan's curriculum-
-- upgrade comparison, fixed separately in adaptive_course_store.dart)
-- slip through, since that bug's reset always carried a plausible-looking
-- error message. There is no longer any routine code path that
-- legitimately needs to demote a ready row -- the one that existed (a
-- narrow repair for a specific historical guided-speaking defect, in
-- prepare-course-lesson/index.ts) is removed in the same change that
-- ships this migration. Any future deliberate repair must not use a
-- routine update path at all.
create or replace function public.prevent_generation_status_regression()
returns trigger as $$
begin
  if old.generation_status = 'ready'
     and old.artifact_json is not null
     and new.generation_status = 'queued'
     and new.artifact_json is null then
    new.generation_status := old.generation_status;
    new.artifact_kind := old.artifact_kind;
    new.artifact_json := old.artifact_json;
    new.generation_attempts := old.generation_attempts;
    new.generation_error := old.generation_error;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;
