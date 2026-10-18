-- Authored daily practice is data rendered by the reviewed client. Answer keys
-- stay server-side and are checked by the daily-challenge Edge Function.
create table if not exists public.daily_challenge_versions (
  id uuid primary key default gen_random_uuid(),
  challenge_key text not null,
  revision integer not null check (revision > 0),
  level_band text not null check (level_band in ('a1', 'a2', 'b1', 'b2')),
  primary_skill text not null check (
    primary_skill in ('Listening', 'Reading', 'Speaking', 'Writing')
  ),
  available_on date not null,
  title text not null,
  summary text not null,
  minutes smallint not null check (minutes between 1 and 15),
  step_labels jsonb not null check (jsonb_typeof(step_labels) = 'array'),
  source_lesson_ids text[] not null default '{}',
  content_json jsonb not null check (jsonb_typeof(content_json) = 'object'),
  answer_key_json jsonb not null check (jsonb_typeof(answer_key_json) = 'object'),
  status text not null default 'draft' check (
    status in ('draft', 'preview', 'scheduled', 'published', 'archived')
  ),
  scheduled_at timestamptz,
  author text not null default '',
  reviewed_by text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (challenge_key, revision)
);

create index if not exists daily_challenge_lookup_idx
  on public.daily_challenge_versions (level_band, available_on, status, revision desc);

create table if not exists public.daily_challenge_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  challenge_version_id uuid not null references public.daily_challenge_versions(id),
  learner_local_date date not null,
  status text not null default 'assigned' check (
    status in ('assigned', 'started', 'completed', 'abandoned')
  ),
  current_step smallint not null default 0 check (current_step >= 0),
  assigned_at timestamptz not null default now(),
  started_at timestamptz,
  last_active_at timestamptz not null default now(),
  completed_at timestamptz,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  unique (user_id, challenge_version_id, learner_local_date)
);

create index if not exists daily_challenge_attempts_user_date_idx
  on public.daily_challenge_attempts (user_id, learner_local_date desc);

create table if not exists public.daily_challenge_step_events (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.daily_challenge_attempts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  step_id text not null,
  selected_index smallint not null check (selected_index >= 0),
  is_correct boolean not null,
  answered_at timestamptz not null default now()
);

create index if not exists daily_challenge_step_events_attempt_idx
  on public.daily_challenge_step_events (attempt_id, step_id, answered_at);

alter table public.daily_challenge_versions enable row level security;
alter table public.daily_challenge_attempts enable row level security;
alter table public.daily_challenge_step_events enable row level security;

-- All content and answer-key reads/writes go through the authenticated
-- function. The service key never ships in the app.
revoke all on public.daily_challenge_versions from anon, authenticated;
revoke all on public.daily_challenge_step_events from anon, authenticated;
grant all on public.daily_challenge_versions to service_role;
grant all on public.daily_challenge_step_events to service_role;

-- Learners may inspect only their own attempt summary. Mutations are handled by
-- the Edge Function, which validates the caller and the versioned answer key.
revoke all on public.daily_challenge_attempts from anon, authenticated;
grant select on public.daily_challenge_attempts to authenticated;
grant all on public.daily_challenge_attempts to service_role;
drop policy if exists "Learners read their own daily challenge attempts"
  on public.daily_challenge_attempts;
create policy "Learners read their own daily challenge attempts"
  on public.daily_challenge_attempts
  for select
  to authenticated
  using ((select auth.uid()) = user_id);
