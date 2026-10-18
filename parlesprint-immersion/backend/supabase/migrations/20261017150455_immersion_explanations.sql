-- Dedicated extension data; no changes to ParleSprint app tables.
create table public.immersion_ai_usage (
  bucket text not null,
  day date not null default current_date,
  requests integer not null check (requests >= 0),
  primary key (bucket, day)
);
alter table public.immersion_ai_usage enable row level security;
revoke all on public.immersion_ai_usage from public, anon, authenticated;
grant all on public.immersion_ai_usage to service_role;

create table public.immersion_ai_cache (
  cache_key text primary key,
  explanation jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.immersion_ai_cache enable row level security;
revoke all on public.immersion_ai_cache from public, anon, authenticated;
grant all on public.immersion_ai_cache to service_role;

-- Invoker privilege: only service_role can execute. Both counters are in one
-- transaction; concurrent requests lock the global bucket in the same order.
create or replace function public.immersion_take_quota(p_user uuid)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare n integer;
begin
  insert into public.immersion_ai_usage(bucket, day, requests)
  values ('global', current_date, 0) on conflict do nothing;
  select requests into n from public.immersion_ai_usage
  where bucket = 'global' and day = current_date for update;
  if n >= 500 then return false; end if;
  insert into public.immersion_ai_usage(bucket, day, requests)
  values (p_user::text, current_date, 0) on conflict do nothing;
  select requests into n from public.immersion_ai_usage
  where bucket = p_user::text and day = current_date for update;
  if n >= 20 then return false; end if;
  update public.immersion_ai_usage set requests = requests + 1
  where bucket in ('global', p_user::text) and day = current_date;
  return true;
end;
$$;
revoke all on function public.immersion_take_quota(uuid) from public, anon, authenticated;
grant execute on function public.immersion_take_quota(uuid) to service_role;
