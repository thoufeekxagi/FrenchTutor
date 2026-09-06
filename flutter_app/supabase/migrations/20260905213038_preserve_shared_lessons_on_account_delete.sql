-- Shared validated catalog lessons must survive deletion of the account that
-- originally published them. Learner-owned progress/content is still removed
-- by delete-account; only the shared catalog creator reference is anonymized.

alter table public.speaking_lessons
  alter column created_by drop not null;

alter table public.speaking_lessons
  drop constraint if exists speaking_lessons_created_by_fkey;

alter table public.speaking_lessons
  add constraint speaking_lessons_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;

alter table public.writing_lessons
  alter column created_by drop not null;

alter table public.writing_lessons
  drop constraint if exists writing_lessons_created_by_fkey;

alter table public.writing_lessons
  add constraint writing_lessons_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;
