-- Reuse the existing anonymous transcription quota rows. A live token reserves
-- 40 twelve-second units (8 minutes) atomically against the same daily caps.
create or replace function public.immersion_take_transcription_quota_units(
  p_installation_hash text,
  p_install_limit integer,
  p_global_limit integer,
  p_units integer
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  today_utc date := (timezone('utc', now()))::date;
  global_count integer;
  install_count integer;
begin
  if p_installation_hash !~ '^[0-9a-f]{64}$'
     or p_install_limit < 1 or p_install_limit > 150
     or p_global_limit < 1 or p_global_limit > 300
     or p_units < 1 or p_units > 40 then
    return false;
  end if;

  delete from public.immersion_transcription_usage
  where usage_date < today_utc - 30;
  insert into public.immersion_transcription_usage(scope, subject, usage_date)
  values ('global', 'global', today_utc), ('install', p_installation_hash, today_utc)
  on conflict do nothing;

  select segments into global_count
  from public.immersion_transcription_usage
  where scope = 'global' and subject = 'global' and usage_date = today_utc
  for update;
  select segments into install_count
  from public.immersion_transcription_usage
  where scope = 'install' and subject = p_installation_hash and usage_date = today_utc
  for update;
  if global_count + p_units > p_global_limit or install_count + p_units > p_install_limit then
    return false;
  end if;

  update public.immersion_transcription_usage set segments = segments + p_units
  where scope = 'global' and subject = 'global' and usage_date = today_utc;
  update public.immersion_transcription_usage set segments = segments + p_units
  where scope = 'install' and subject = p_installation_hash and usage_date = today_utc;
  return true;
end;
$$;
revoke all on function public.immersion_take_transcription_quota_units(text, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.immersion_take_transcription_quota_units(text, integer, integer, integer)
  to service_role;
