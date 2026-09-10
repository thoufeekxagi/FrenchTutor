-- Forward-only protection for the Course/Practice session ledger.
--
-- The app writes one tagged session for every completed Course skill and
-- bounded transcript/material rows beside it.  This migration is deliberately
-- additive: it does not rewrite or backfill stale developer rows.

create table if not exists public.sessions_state (
  id uuid primary key,
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
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
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
drop policy if exists "learners manage their own sessions" on public.sessions_state;
create policy "sessions are owned by the signed-in learner"
  on public.sessions_state for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "chat messages are owned by the signed-in learner" on public.chat_messages_state;
drop policy if exists "learners manage their own chat messages" on public.chat_messages_state;
create policy "chat messages are owned by the signed-in learner"
  on public.chat_messages_state for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Do not expose learner history through the public/anonymous API role.
revoke all on public.sessions_state, public.chat_messages_state from public, anon;
grant select, insert, update, delete on public.sessions_state,
  public.chat_messages_state to authenticated;
