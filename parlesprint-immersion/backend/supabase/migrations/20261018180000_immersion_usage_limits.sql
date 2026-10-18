-- Anonymous free-tier limits for the extension. Counters per UTC day (plus a
-- per-minute burst bucket) for the installation, the salted-hash IP, and everyone.
-- Dedicated extension data; no changes to ParleSprint app tables.
create table if not exists public.immersion_usage (
  bucket text not null,
  scope text not null check (scope in ('global', 'ip', 'install', 'burst')),
  subject text not null,
  units integer not null default 0 check (units >= 0),
  created_at timestamptz not null default now(),
  primary key (bucket, scope, subject)
);
create index if not exists immersion_usage_created_at on public.immersion_usage (created_at);
alter table public.immersion_usage enable row level security;
revoke all on public.immersion_usage from public, anon, authenticated;
grant all on public.immersion_usage to service_role;

-- Returns 'ok' or the name of the limit that blocked the request. Nothing is
-- counted unless every limit passes. Locks are taken in a fixed order.
create or replace function public.immersion_take_usage(
  p_kind text,
  p_install text,
  p_ip text,
  p_units integer,
  p_install_limit integer,
  p_ip_limit integer,
  p_global_limit integer,
  p_burst_limit integer
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  now_utc timestamp := timezone('utc', now());
  day_bucket text := p_kind || ':' || to_char(now_utc, 'YYYYMMDD');
  minute_bucket text := p_kind || ':' || to_char(now_utc, 'YYYYMMDDHH24MI');
  g integer; i integer; n integer; b integer;
begin
  if p_kind !~ '^[a-z_]{1,16}$' or p_install !~ '^[0-9a-f]{64}$' or p_ip !~ '^[0-9a-f]{64}$'
     or p_units < 1 or p_units > 60 then
    return 'invalid';
  end if;
  delete from public.immersion_usage where created_at < now() - interval '8 days';
  insert into public.immersion_usage(bucket, scope, subject) values
    (day_bucket, 'global', 'all'), (day_bucket, 'ip', p_ip),
    (day_bucket, 'install', p_install), (minute_bucket, 'burst', p_ip)
  on conflict do nothing;
  select units into g from public.immersion_usage where bucket = day_bucket and scope = 'global' and subject = 'all' for update;
  select units into i from public.immersion_usage where bucket = day_bucket and scope = 'ip' and subject = p_ip for update;
  select units into n from public.immersion_usage where bucket = day_bucket and scope = 'install' and subject = p_install for update;
  select units into b from public.immersion_usage where bucket = minute_bucket and scope = 'burst' and subject = p_ip for update;
  if g + p_units > p_global_limit then return 'global'; end if;
  if b + 1 > p_burst_limit then return 'burst'; end if;
  if i + p_units > p_ip_limit then return 'ip'; end if;
  if n + p_units > p_install_limit then return 'install'; end if;
  update public.immersion_usage set units = units + p_units
    where (bucket = day_bucket and ((scope = 'global' and subject = 'all') or (scope = 'ip' and subject = p_ip) or (scope = 'install' and subject = p_install)));
  update public.immersion_usage set units = units + 1
    where bucket = minute_bucket and scope = 'burst' and subject = p_ip;
  return 'ok';
end;
$$;
revoke all on function public.immersion_take_usage(text, text, text, integer, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.immersion_take_usage(text, text, text, integer, integer, integer, integer, integer) to service_role;
