create table if not exists public.web_learning_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null check (length(item_id) between 1 and 180),
  payload jsonb not null check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 8192),
  updated_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

alter table public.web_learning_items enable row level security;
revoke all on public.web_learning_items from anon;
grant select, insert, update, delete on public.web_learning_items to authenticated;

drop policy if exists "learners read own website words" on public.web_learning_items;
create policy "learners read own website words" on public.web_learning_items
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "learners add own website words" on public.web_learning_items;
create policy "learners add own website words" on public.web_learning_items
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "learners update own website words" on public.web_learning_items;
create policy "learners update own website words" on public.web_learning_items
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "learners remove own website words" on public.web_learning_items;
create policy "learners remove own website words" on public.web_learning_items
  for delete to authenticated using ((select auth.uid()) = user_id);
