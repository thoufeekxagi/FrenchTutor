-- Durable Course + Practice content contract.
--
-- This migration is intentionally idempotent. Some early environments were
-- created from dashboard SQL or older migration histories, so a table may
-- already exist with only part of the current shape. The app stores the
-- complete validated payload in JSON and mirrors it locally; these tables are
-- the recovery source after reinstall or sign-in on another device.

-- ---------------------------------------------------------------------------
-- Adaptive Course: ordered units, completion, and prepared artifacts
-- ---------------------------------------------------------------------------

create table if not exists public.adaptive_course_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  goal text not null default '',
  level text not null default 'A1' check (level in ('A1', 'A2', 'B1', 'B2')),
  profile_fingerprint text not null default '',
  version integer not null default 1 check (version > 0),
  status text not null default 'active' check (status in ('active', 'replaced')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.adaptive_course_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.adaptive_course_plans(id) on delete cascade,
  content_key text not null,
  sequence integer not null check (sequence > 0),
  level text not null default 'A1' check (level in ('A1', 'A2', 'B1', 'B2')),
  unit integer not null default 1 check (unit > 0),
  unit_title text not null default '',
  title text not null default '',
  subtitle text not null default '',
  competency text not null default '',
  context text not null default '',
  primary_skill text not null default 'speaking',
  supporting_skills_json jsonb not null default '[]'::jsonb,
  grammar_focus_json jsonb not null default '[]'::jsonb,
  success_criteria_json jsonb not null default '[]'::jsonb,
  estimated_minutes integer not null default 10 check (estimated_minutes > 0),
  target_phrases_json jsonb not null default '[]'::jsonb,
  source_session_ids_json jsonb not null default '[]'::jsonb,
  generation_status text not null default 'queued',
  artifact_kind text,
  artifact_json jsonb,
  generation_version integer not null default 1,
  generation_attempts integer not null default 0,
  generation_error text,
  profile_fingerprint text not null default '',
  status text not null default 'planned'
    check (status in ('planned', 'active', 'completed', 'replaced')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  deleted_at timestamptz,
  unique (plan_id, sequence)
);

alter table public.adaptive_course_plans
  add column if not exists goal text not null default '',
  add column if not exists level text not null default 'A1',
  add column if not exists profile_fingerprint text not null default '',
  add column if not exists version integer not null default 1,
  add column if not exists status text not null default 'active',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

alter table public.adaptive_course_sessions
  add column if not exists target_phrases_json jsonb not null default '[]'::jsonb,
  add column if not exists source_session_ids_json jsonb not null default '[]'::jsonb,
  add column if not exists generation_status text not null default 'queued',
  add column if not exists artifact_kind text,
  add column if not exists artifact_json jsonb,
  add column if not exists generation_version integer not null default 1,
  add column if not exists generation_attempts integer not null default 0,
  add column if not exists generation_error text;

create index if not exists idx_adaptive_course_plans_user_active
  on public.adaptive_course_plans (user_id, status, version desc)
  where deleted_at is null;
create index if not exists idx_adaptive_course_sessions_user_generation
  on public.adaptive_course_sessions (user_id, generation_status, sequence)
  where deleted_at is null;
create index if not exists idx_adaptive_course_sessions_user_content
  on public.adaptive_course_sessions (user_id, content_key);

-- ---------------------------------------------------------------------------
-- Learner-owned generated libraries used by Practice
-- ---------------------------------------------------------------------------

create table if not exists public.generated_stories (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  passage_json jsonb not null default '{}'::jsonb,
  quiz_json jsonb not null default '[]'::jsonb,
  keywords_json jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.generated_stories
  add column if not exists title text not null default '',
  add column if not exists passage_json jsonb not null default '{}'::jsonb,
  add column if not exists quiz_json jsonb not null default '[]'::jsonb,
  add column if not exists keywords_json jsonb not null default '[]'::jsonb,
  add column if not exists level_band text,
  add column if not exists summary text,
  add column if not exists topic text,
  add column if not exists read_time_minutes integer,
  add column if not exists cover_url text,
  add column if not exists music_background_url text,
  add column if not exists audio_path text,
  add column if not exists audio_mode text,
  add column if not exists practice_mode text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create table if not exists public.generated_roleplays (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  passage_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.generated_roleplays
  add column if not exists title text not null default '',
  add column if not exists passage_json jsonb not null default '{}'::jsonb,
  add column if not exists level_band text,
  add column if not exists cover_url text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create table if not exists public.generated_grammar_stories (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  grammar_point text not null default '',
  level_band text not null default 'A1',
  passage_json jsonb not null default '{}'::jsonb,
  quiz_json jsonb not null default '[]'::jsonb,
  keywords_json jsonb not null default '[]'::jsonb,
  explanation_json jsonb not null default '{}'::jsonb,
  score double precision,
  cover_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.generated_grammar_stories
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists title text not null default '',
  add column if not exists grammar_point text not null default '',
  add column if not exists level_band text not null default 'A1',
  add column if not exists passage_json jsonb not null default '{}'::jsonb,
  add column if not exists quiz_json jsonb not null default '[]'::jsonb,
  add column if not exists keywords_json jsonb not null default '[]'::jsonb,
  add column if not exists explanation_json jsonb not null default '{}'::jsonb,
  add column if not exists score double precision,
  add column if not exists cover_url text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create table if not exists public.generated_writing_tasks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  task_json jsonb not null default '{}'::jsonb,
  level_band text not null default 'A2',
  cover_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.generated_writing_tasks
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists task_json jsonb not null default '{}'::jsonb,
  add column if not exists level_band text not null default 'A2',
  add column if not exists cover_url text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create table if not exists public.generated_vocabulary_sets (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  course_session_id uuid,
  title text not null default '',
  summary text not null default '',
  topic text not null default '',
  level_band text not null default 'A1',
  entries_json jsonb not null default '[]'::jsonb,
  examples_json jsonb not null default '{}'::jsonb,
  cover_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.generated_vocabulary_sets
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists course_session_id uuid,
  add column if not exists title text not null default '',
  add column if not exists summary text not null default '',
  add column if not exists topic text not null default '',
  add column if not exists level_band text not null default 'A1',
  add column if not exists entries_json jsonb not null default '[]'::jsonb,
  add column if not exists examples_json jsonb not null default '{}'::jsonb,
  add column if not exists cover_url text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create index if not exists idx_generated_stories_user_created
  on public.generated_stories (user_id, created_at desc)
  where deleted_at is null;
create index if not exists idx_generated_roleplays_user_created
  on public.generated_roleplays (user_id, created_at desc)
  where deleted_at is null;
create index if not exists idx_generated_grammar_stories_user_created
  on public.generated_grammar_stories (user_id, created_at desc)
  where deleted_at is null;
create index if not exists idx_generated_writing_tasks_user_created
  on public.generated_writing_tasks (user_id, created_at desc)
  where deleted_at is null;
create index if not exists idx_generated_vocabulary_sets_user_created
  on public.generated_vocabulary_sets (user_id, created_at desc)
  where deleted_at is null;
create unique index if not exists idx_generated_vocabulary_course_session
  on public.generated_vocabulary_sets (course_session_id)
  where course_session_id is not null and deleted_at is null;

-- ---------------------------------------------------------------------------
-- Course/Practice session ledger and bounded Live transcript turns
-- ---------------------------------------------------------------------------
-- The mobile client writes these rows first and retries them through the
-- sync outbox. Keeping the ledger on the same learner-owned Supabase account
-- is what lets Review/Warm-up survive uninstall and continue on another
-- device. Transcript turns are intentionally separate so a session summary
-- can be restored even if a Live socket closes before its last turn arrives.
create table if not exists public.sessions_state (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz,
  summary text,
  topic text,
  content_key text,
  vocabulary_json jsonb not null default '[]'::jsonb,
  stage text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.sessions_state
  add column if not exists content_key text,
  add column if not exists vocabulary_json jsonb not null default '[]'::jsonb,
  add column if not exists stage text,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create table if not exists public.chat_messages_state (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id text not null,
  role text not null,
  content text not null,
  created_at timestamptz not null default now()
);

alter table public.chat_messages_state
  add column if not exists created_at timestamptz not null default now();

create index if not exists idx_sessions_state_user_updated
  on public.sessions_state (user_id, updated_at desc)
  where deleted_at is null;
create index if not exists idx_sessions_state_user_content_key
  on public.sessions_state (user_id, content_key)
  where content_key is not null and deleted_at is null;
create index if not exists idx_chat_messages_state_user_session
  on public.chat_messages_state (user_id, session_id, created_at);

alter table public.sessions_state enable row level security;
alter table public.chat_messages_state enable row level security;

drop policy if exists "sessions are owned by the signed-in learner" on public.sessions_state;
create policy "sessions are owned by the signed-in learner"
  on public.sessions_state for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "chat messages are owned by the signed-in learner" on public.chat_messages_state;
create policy "chat messages are owned by the signed-in learner"
  on public.chat_messages_state for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.sessions_state, public.chat_messages_state from anon;
grant select, insert, update, delete on public.sessions_state,
  public.chat_messages_state to authenticated;

-- Audio is cached privately per learner. The database row and storage object
-- share the same user-prefixed path so a second device can hydrate the row and
-- download the exact clip without generating it again.
create table if not exists public.vocabulary_audio_cache (
  user_id uuid not null references auth.users(id) on delete cascade,
  cache_key text not null,
  content_item_id text not null default '',
  spoken_text text not null default '',
  voice_name text not null default '',
  storage_path text not null,
  sha256 text not null default '',
  bytes integer not null default 1 check (bytes > 0),
  sample_rate_hz integer not null default 24000,
  channels integer not null default 1,
  encoding text not null default 'pcm_s16le',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, cache_key),
  unique (storage_path)
);

alter table public.vocabulary_audio_cache
  add column if not exists content_item_id text not null default '',
  add column if not exists spoken_text text not null default '',
  add column if not exists voice_name text not null default '',
  add column if not exists storage_path text not null default '',
  add column if not exists sha256 text not null default '',
  add column if not exists bytes integer not null default 1,
  add column if not exists sample_rate_hz integer not null default 24000,
  add column if not exists channels integer not null default 1,
  add column if not exists encoding text not null default 'pcm_s16le',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_vocabulary_audio_cache_user_item
  on public.vocabulary_audio_cache (user_id, content_item_id);

insert into storage.buckets (id, name, public)
values
  ('story-covers', 'story-covers', false),
  ('listening-audio', 'listening-audio', false),
  ('vocabulary-audio', 'vocabulary-audio', false)
on conflict (id) do update set public = false;

drop policy if exists "learners read their own story covers" on storage.objects;
create policy "learners read their own story covers" on storage.objects
  for select to authenticated using (
    bucket_id = 'story-covers'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "learners upload their own story covers" on storage.objects;
create policy "learners upload their own story covers" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'story-covers'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "learners update their own story covers" on storage.objects;
create policy "learners update their own story covers" on storage.objects
  for update to authenticated using (
    bucket_id = 'story-covers'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  ) with check (
    bucket_id = 'story-covers'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "learners delete their own story covers" on storage.objects;
create policy "learners delete their own story covers" on storage.objects
  for delete to authenticated using (
    bucket_id = 'story-covers'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "learners read their own listening audio" on storage.objects;
create policy "learners read their own listening audio" on storage.objects
  for select to authenticated using (
    bucket_id = 'listening-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "learners upload their own listening audio" on storage.objects;
create policy "learners upload their own listening audio" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'listening-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "learners update their own listening audio" on storage.objects;
create policy "learners update their own listening audio" on storage.objects
  for update to authenticated using (
    bucket_id = 'listening-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  ) with check (
    bucket_id = 'listening-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "learners delete their own listening audio" on storage.objects;
create policy "learners delete their own listening audio" on storage.objects
  for delete to authenticated using (
    bucket_id = 'listening-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "learners read their own vocabulary audio" on storage.objects;
create policy "learners read their own vocabulary audio" on storage.objects
  for select to authenticated using (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "learners upload their own vocabulary audio" on storage.objects;
create policy "learners upload their own vocabulary audio" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "learners update their own vocabulary audio" on storage.objects;
create policy "learners update their own vocabulary audio" on storage.objects
  for update to authenticated using (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  ) with check (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "learners delete their own vocabulary audio" on storage.objects;
create policy "learners delete their own vocabulary audio" on storage.objects
  for delete to authenticated using (
    bucket_id = 'vocabulary-audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- Validated Practice V2 payloads (shared metadata, learner-owned writes)
-- ---------------------------------------------------------------------------

create table if not exists public.speaking_lessons (
  id text primary key,
  source text not null default 'generated',
  mode text not null default 'guided',
  level_band text not null default 'A1',
  title text not null default '',
  fingerprint text not null default '',
  lesson_json jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id) on delete cascade,
  is_validated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.speaking_lessons
  add column if not exists source text not null default 'generated',
  add column if not exists mode text not null default 'guided',
  add column if not exists level_band text not null default 'A1',
  add column if not exists title text not null default '',
  add column if not exists fingerprint text not null default '',
  add column if not exists lesson_json jsonb not null default '{}'::jsonb,
  add column if not exists created_by uuid references auth.users(id) on delete cascade,
  add column if not exists is_validated boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create table if not exists public.writing_lessons (
  id text primary key,
  mode text not null default 'guided',
  level_band text not null default 'A1',
  title text not null default '',
  fingerprint text not null default '',
  lesson_json jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id) on delete cascade,
  is_validated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.writing_lessons
  add column if not exists mode text not null default 'guided',
  add column if not exists level_band text not null default 'A1',
  add column if not exists title text not null default '',
  add column if not exists fingerprint text not null default '',
  add column if not exists lesson_json jsonb not null default '{}'::jsonb,
  add column if not exists created_by uuid references auth.users(id) on delete cascade,
  add column if not exists is_validated boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create table if not exists public.grammar_course_sessions (
  id text primary key,
  mode text not null default 'guided',
  tense text not null default 'present',
  level_band text not null default 'A1',
  title text not null default '',
  grammar_focus text not null default '',
  fingerprint text not null default '',
  session_json jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id) on delete cascade,
  is_validated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.grammar_course_sessions
  add column if not exists mode text not null default 'guided',
  add column if not exists tense text not null default 'present',
  add column if not exists level_band text not null default 'A1',
  add column if not exists title text not null default '',
  add column if not exists grammar_focus text not null default '',
  add column if not exists fingerprint text not null default '',
  add column if not exists session_json jsonb not null default '{}'::jsonb,
  add column if not exists created_by uuid references auth.users(id) on delete cascade,
  add column if not exists is_validated boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create index if not exists idx_speaking_lessons_public
  on public.speaking_lessons (mode, level_band, created_at)
  where is_validated = true and deleted_at is null;
create index if not exists idx_writing_lessons_owner
  on public.writing_lessons (created_by, mode, level_band, created_at)
  where deleted_at is null;
create index if not exists idx_grammar_course_sessions_owner
  on public.grammar_course_sessions (created_by, mode, tense, level_band, created_at)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- Review/warm-up provenance and attempts
-- ---------------------------------------------------------------------------

create table if not exists public.review_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'review',
  requested_mode text not null default '',
  resolved_mode text not null default '',
  level_band text not null default 'A1',
  goal text not null default '',
  duration_minutes integer not null default 10,
  topic text not null default '',
  source_fingerprint text not null default '',
  brief_json jsonb not null default '{}'::jsonb,
  generated_json jsonb,
  status text not null default 'planned',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.review_plan_targets (
  id uuid primary key,
  plan_id uuid not null references public.review_plans(id) on delete cascade,
  target_key text not null default '',
  target_type text not null default '',
  display_text text not null default '',
  reason text not null default '',
  priority double precision not null default 0,
  source_ids_json jsonb not null default '[]'::jsonb,
  evidence_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.review_attempts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.review_plans(id) on delete cascade,
  activity_id text,
  session_id text,
  mode text not null default '',
  status text not null default 'started',
  score double precision,
  result_json jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_review_plans_user_created
  on public.review_plans (user_id, kind, created_at desc)
  where deleted_at is null;
create index if not exists idx_review_plan_targets_plan_priority
  on public.review_plan_targets (plan_id, priority desc)
  where deleted_at is null;
create index if not exists idx_review_attempts_user_started
  on public.review_attempts (user_id, started_at desc)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- Ownership and Data API boundary
-- ---------------------------------------------------------------------------

alter table public.adaptive_course_plans enable row level security;
alter table public.adaptive_course_sessions enable row level security;
alter table public.generated_stories enable row level security;
alter table public.generated_roleplays enable row level security;
alter table public.generated_grammar_stories enable row level security;
alter table public.generated_writing_tasks enable row level security;
alter table public.generated_vocabulary_sets enable row level security;
alter table public.vocabulary_audio_cache enable row level security;
alter table public.speaking_lessons enable row level security;
alter table public.writing_lessons enable row level security;
alter table public.grammar_course_sessions enable row level security;
alter table public.review_plans enable row level security;
alter table public.review_plan_targets enable row level security;
alter table public.review_attempts enable row level security;

drop policy if exists "learners manage their own adaptive plans"
  on public.adaptive_course_plans;
create policy "learners manage their own adaptive plans"
  on public.adaptive_course_plans for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "learners manage their own adaptive sessions"
  on public.adaptive_course_sessions;
create policy "learners manage their own adaptive sessions"
  on public.adaptive_course_sessions for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Each of these libraries is private to the learner who generated it.
drop policy if exists "learners manage their own stories" on public.generated_stories;
create policy "learners manage their own stories" on public.generated_stories
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "learners manage their own roleplays" on public.generated_roleplays;
create policy "learners manage their own roleplays" on public.generated_roleplays
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "learners manage their own grammar stories" on public.generated_grammar_stories;
create policy "learners manage their own grammar stories" on public.generated_grammar_stories
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "learners manage their own writing tasks" on public.generated_writing_tasks;
create policy "learners manage their own writing tasks" on public.generated_writing_tasks
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "learners manage their own vocabulary sets" on public.generated_vocabulary_sets;
create policy "learners manage their own vocabulary sets" on public.generated_vocabulary_sets
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "learners manage their own vocabulary audio cache"
  on public.vocabulary_audio_cache;
create policy "learners manage their own vocabulary audio cache"
  on public.vocabulary_audio_cache for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "owners can read writing lessons" on public.writing_lessons;
create policy "owners can read writing lessons" on public.writing_lessons
  for select to authenticated
  using (created_by = (select auth.uid()) and is_validated and deleted_at is null);
drop policy if exists "owners can create writing lessons" on public.writing_lessons;
create policy "owners can create writing lessons" on public.writing_lessons
  for insert to authenticated
  with check (created_by = (select auth.uid()) and is_validated);
drop policy if exists "owners can update writing lessons" on public.writing_lessons;
create policy "owners can update writing lessons" on public.writing_lessons
  for update to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()) and is_validated);
drop policy if exists "owners can delete writing lessons" on public.writing_lessons;
create policy "owners can delete writing lessons" on public.writing_lessons
  for delete to authenticated using (created_by = (select auth.uid()));

drop policy if exists "owners can read grammar course sessions" on public.grammar_course_sessions;
create policy "owners can read grammar course sessions" on public.grammar_course_sessions
  for select to authenticated
  using (created_by = (select auth.uid()) and is_validated and deleted_at is null);
drop policy if exists "owners can create grammar course sessions" on public.grammar_course_sessions;
create policy "owners can create grammar course sessions" on public.grammar_course_sessions
  for insert to authenticated
  with check (created_by = (select auth.uid()) and is_validated);
drop policy if exists "owners can update grammar course sessions" on public.grammar_course_sessions;
create policy "owners can update grammar course sessions" on public.grammar_course_sessions
  for update to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()) and is_validated);
drop policy if exists "owners can delete grammar course sessions" on public.grammar_course_sessions;
create policy "owners can delete grammar course sessions" on public.grammar_course_sessions
  for delete to authenticated using (created_by = (select auth.uid()));

-- Speaking defaults are shared read-only; generated rows are still validated
-- and attributable to the authenticated creator.
drop policy if exists "anyone can read validated speaking lessons" on public.speaking_lessons;
create policy "anyone can read validated speaking lessons" on public.speaking_lessons
  for select to anon, authenticated
  using (is_validated and deleted_at is null);
drop policy if exists "authenticated users can publish validated speaking lessons" on public.speaking_lessons;
create policy "authenticated users can publish validated speaking lessons" on public.speaking_lessons
  for insert to authenticated
  with check (created_by = (select auth.uid()) and is_validated);
drop policy if exists "owners can update speaking lessons" on public.speaking_lessons;
create policy "owners can update speaking lessons" on public.speaking_lessons
  for update to authenticated using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()) and is_validated);
drop policy if exists "owners can delete speaking lessons" on public.speaking_lessons;
create policy "owners can delete speaking lessons" on public.speaking_lessons
  for delete to authenticated using (created_by = (select auth.uid()));

drop policy if exists "review plans are owned by the signed-in learner" on public.review_plans;
create policy "review plans are owned by the signed-in learner" on public.review_plans
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "review targets follow their owned plan" on public.review_plan_targets;
create policy "review targets follow their owned plan" on public.review_plan_targets
  for all to authenticated
  using (exists (select 1 from public.review_plans p
    where p.id = plan_id and p.user_id = (select auth.uid())))
  with check (exists (select 1 from public.review_plans p
    where p.id = plan_id and p.user_id = (select auth.uid())));
drop policy if exists "review attempts are owned by the signed-in learner" on public.review_attempts;
create policy "review attempts are owned by the signed-in learner" on public.review_attempts
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.adaptive_course_plans, public.adaptive_course_sessions,
  public.generated_stories, public.generated_roleplays,
  public.generated_grammar_stories, public.generated_writing_tasks,
  public.generated_vocabulary_sets, public.writing_lessons,
  public.grammar_course_sessions, public.review_plans,
  public.review_plan_targets, public.review_attempts,
  public.vocabulary_audio_cache from anon;

grant select, insert, update on public.adaptive_course_plans,
  public.adaptive_course_sessions, public.generated_stories,
  public.generated_roleplays, public.generated_grammar_stories,
  public.generated_writing_tasks, public.generated_vocabulary_sets,
  public.writing_lessons, public.grammar_course_sessions,
  public.review_plans, public.review_plan_targets, public.review_attempts
  to authenticated;
grant select, insert, update, delete on public.vocabulary_audio_cache
  to authenticated;

revoke all on public.speaking_lessons from anon, authenticated;
grant select on public.speaking_lessons to anon, authenticated;
grant insert, update, delete on public.speaking_lessons to authenticated;

comment on table public.adaptive_course_sessions is
  'Ordered learner Course rows with durable validated Vocabulary, Reading, Listening, Writing, Speaking, and Grammar artifacts.';
comment on column public.adaptive_course_sessions.artifact_json is
  'Complete validated Course payload. Reused after reinstall; Course screens never regenerate it on open.';
comment on table public.grammar_course_sessions is
  'Learner-owned validated Practice Grammar sessions with nested steps.';
