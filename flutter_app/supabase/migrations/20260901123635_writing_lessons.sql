-- Validated, personalized Writing V2 lessons shared across a learner's devices.
create table if not exists public.writing_lessons (
  id text primary key,
  mode text not null check (mode in ('guided', 'complete', 'roleplay')),
  level_band text not null check (level_band in ('A1', 'A2', 'B1', 'B2')),
  title text not null,
  fingerprint text not null,
  lesson_json jsonb not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  is_validated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (created_by, mode, level_band, fingerprint)
);

create index if not exists idx_writing_lessons_owner_mode_level
  on public.writing_lessons (created_by, mode, level_band, created_at)
  where is_validated = true and deleted_at is null;

alter table public.writing_lessons enable row level security;

drop policy if exists "owners can read writing lessons"
  on public.writing_lessons;
create policy "owners can read writing lessons"
  on public.writing_lessons for select
  to authenticated
  using (created_by = auth.uid() and is_validated = true and deleted_at is null);

drop policy if exists "owners can create writing lessons"
  on public.writing_lessons;
create policy "owners can create writing lessons"
  on public.writing_lessons for insert
  to authenticated
  with check (created_by = auth.uid() and is_validated = true);

drop policy if exists "owners can update writing lessons"
  on public.writing_lessons;
create policy "owners can update writing lessons"
  on public.writing_lessons for update
  to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid() and is_validated = true);

drop policy if exists "owners can delete writing lessons"
  on public.writing_lessons;
create policy "owners can delete writing lessons"
  on public.writing_lessons for delete
  to authenticated
  using (created_by = auth.uid());

revoke all on public.writing_lessons from anon, authenticated;
grant select, insert, update, delete on public.writing_lessons to authenticated;

comment on table public.writing_lessons is
  'Per-learner validated Guided, Complete, and Roleplay writing lessons.';
