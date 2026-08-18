-- Persist the personalized onboarding inputs and learner-specific adaptive
-- course route. This migration is intentionally self-contained because the
-- earlier profile-preferences migration was present in the client repository
-- but had not been applied to the connected project.

alter table public.profiles
  add column if not exists preferred_days text,
  add column if not exists interests text,
  add column if not exists time_zone text,
  add column if not exists notification_permission_state text not null default 'not_requested',
  add column if not exists onboarding_version text not null default 'v1';

create table if not exists public.adaptive_course_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  goal text not null,
  level text not null check (level in ('A1', 'A2', 'B1', 'B2')),
  profile_fingerprint text not null,
  version integer not null check (version > 0),
  status text not null default 'active'
    check (status in ('active', 'replaced')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_adaptive_course_plans_user_version
  on public.adaptive_course_plans (user_id, version desc, created_at desc);

create index if not exists idx_adaptive_course_plans_user_active
  on public.adaptive_course_plans (user_id, status)
  where deleted_at is null;

create table if not exists public.adaptive_course_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.adaptive_course_plans(id) on delete cascade,
  content_key text not null,
  sequence integer not null check (sequence > 0),
  level text not null check (level in ('A1', 'A2', 'B1', 'B2')),
  unit integer not null check (unit > 0),
  unit_title text not null,
  title text not null,
  subtitle text not null,
  competency text not null,
  context text not null,
  primary_skill text not null,
  supporting_skills_json jsonb not null default '[]'::jsonb,
  grammar_focus_json jsonb not null default '[]'::jsonb,
  success_criteria_json jsonb not null default '[]'::jsonb,
  estimated_minutes integer not null default 10 check (estimated_minutes > 0),
  profile_fingerprint text not null,
  status text not null default 'planned'
    check (status in ('planned', 'active', 'completed', 'replaced')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  deleted_at timestamptz,
  unique (plan_id, sequence)
);

create index if not exists idx_adaptive_course_sessions_user_plan
  on public.adaptive_course_sessions (user_id, plan_id, sequence);

create index if not exists idx_adaptive_course_sessions_user_content
  on public.adaptive_course_sessions (user_id, content_key);

alter table public.adaptive_course_plans enable row level security;
alter table public.adaptive_course_sessions enable row level security;

drop policy if exists "learners manage their own adaptive plans"
  on public.adaptive_course_plans;
create policy "learners manage their own adaptive plans"
  on public.adaptive_course_plans
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "learners manage their own adaptive sessions"
  on public.adaptive_course_sessions;
create policy "learners manage their own adaptive sessions"
  on public.adaptive_course_sessions
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- New public-schema tables are not automatically exposed by the Data API on
-- current Supabase projects. These are private authenticated-client tables;
-- RLS remains the ownership boundary.
revoke all on public.adaptive_course_plans from anon;
grant select, insert, update on public.adaptive_course_plans to authenticated;
revoke all on public.adaptive_course_sessions from anon;
grant select, insert, update on public.adaptive_course_sessions to authenticated;

-- The existing profile policies already restrict writes to auth.uid() = id;
-- grant the newly added fields to the authenticated client explicitly.
grant select, update on public.profiles to authenticated;
