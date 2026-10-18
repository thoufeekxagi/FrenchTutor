-- Small per-learner settings and story progress for the V3 app that used to
-- live only on the phone (finished stories, reading positions, saved story
-- words, the learner's name). One row per key; the app merges on sign-in so a
-- reinstall or a second device restores them.
create table if not exists public.v3_user_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  state_key text not null check (char_length(state_key) between 1 and 80),
  value jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, state_key)
);

alter table public.v3_user_state enable row level security;
revoke all on table public.v3_user_state from anon, authenticated;
grant select, insert, update on table public.v3_user_state to authenticated;

drop policy if exists v3_user_state_select_own on public.v3_user_state;
create policy v3_user_state_select_own on public.v3_user_state
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists v3_user_state_insert_own on public.v3_user_state;
create policy v3_user_state_insert_own on public.v3_user_state
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists v3_user_state_update_own on public.v3_user_state;
create policy v3_user_state_update_own on public.v3_user_state
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
