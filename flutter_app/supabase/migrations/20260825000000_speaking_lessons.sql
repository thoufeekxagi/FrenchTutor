-- Shared, validated Speaking lessons.
--
-- The mobile app always validates the bilingual payload before inserting it.
-- RLS keeps the table publicly readable only for validated, non-deleted rows;
-- writes still require an authenticated Supabase user and are attributable to
-- that user. This lets the starter catalog and validated AI lessons be shared
-- across installs without exposing the auth/service-role key in the app.
create table if not exists public.speaking_lessons (
  id text primary key,
  source text not null check (source in ('default', 'generated')),
  mode text not null check (mode in ('guided', 'freeTalk', 'roleplay')),
  level_band text not null check (level_band in ('A1', 'A2', 'B1', 'B2')),
  title text not null,
  fingerprint text not null,
  lesson_json jsonb not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  is_validated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (mode, level_band, fingerprint)
);

create index if not exists idx_speaking_lessons_public_mode_level
  on public.speaking_lessons (mode, level_band, created_at)
  where is_validated = true and deleted_at is null;

alter table public.speaking_lessons enable row level security;

drop policy if exists "anyone can read validated speaking lessons"
  on public.speaking_lessons;
create policy "anyone can read validated speaking lessons"
  on public.speaking_lessons for select
  to anon, authenticated
  using (is_validated = true and deleted_at is null);

drop policy if exists "authenticated users can publish validated speaking lessons"
  on public.speaking_lessons;
create policy "authenticated users can publish validated speaking lessons"
  on public.speaking_lessons for insert
  to authenticated
  with check (created_by = auth.uid() and is_validated = true);

drop policy if exists "owners can update speaking lessons"
  on public.speaking_lessons;
create policy "owners can update speaking lessons"
  on public.speaking_lessons for update
  to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid() and is_validated = true);

drop policy if exists "owners can delete speaking lessons"
  on public.speaking_lessons;
create policy "owners can delete speaking lessons"
  on public.speaking_lessons for delete
  to authenticated
  using (created_by = auth.uid());

revoke all on public.speaking_lessons from anon, authenticated;
grant select on public.speaking_lessons to anon, authenticated;
grant insert, update, delete on public.speaking_lessons to authenticated;

comment on table public.speaking_lessons is
  'Shared default and validated AI Guided, Free Talk, and Roleplay lessons.';
