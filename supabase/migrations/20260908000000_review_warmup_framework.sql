-- Review/Warm-up provenance and resumability.
-- The Flutter client stores these rows locally first and uploads them after
-- sign-in. Raw learning evidence remains in the existing session/transcript
-- tables; these rows only freeze the bounded planner input and attempt state.

create table if not exists public.review_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('review', 'warmup')),
  requested_mode text not null,
  resolved_mode text not null,
  level_band text not null,
  goal text not null default '',
  duration_minutes integer not null default 10,
  topic text not null default '',
  source_fingerprint text not null,
  brief_json jsonb not null default '{}'::jsonb,
  generated_json jsonb,
  status text not null default 'planned',
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create index if not exists review_plans_user_kind_created_idx
  on public.review_plans (user_id, kind, created_at desc)
  where deleted_at is null;

create table if not exists public.review_plan_targets (
  id uuid primary key,
  plan_id uuid not null references public.review_plans(id) on delete cascade,
  target_key text not null,
  target_type text not null,
  display_text text not null,
  reason text not null,
  priority double precision not null default 0,
  source_ids_json jsonb not null default '[]'::jsonb,
  evidence_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create index if not exists review_plan_targets_plan_priority_idx
  on public.review_plan_targets (plan_id, priority desc)
  where deleted_at is null;

create table if not exists public.review_attempts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.review_plans(id) on delete cascade,
  activity_id text,
  session_id text,
  mode text not null,
  status text not null default 'started',
  score double precision,
  result_json jsonb,
  started_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create index if not exists review_attempts_user_started_idx
  on public.review_attempts (user_id, started_at desc)
  where deleted_at is null;

alter table public.review_plans enable row level security;
alter table public.review_plan_targets enable row level security;
alter table public.review_attempts enable row level security;

create policy "review plans are owned by the signed-in learner"
  on public.review_plans for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "review targets follow their owned plan"
  on public.review_plan_targets for all to authenticated
  using (exists (
    select 1 from public.review_plans p
    where p.id = plan_id and p.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.review_plans p
    where p.id = plan_id and p.user_id = (select auth.uid())
  ));

create policy "review attempts are owned by the signed-in learner"
  on public.review_attempts for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
