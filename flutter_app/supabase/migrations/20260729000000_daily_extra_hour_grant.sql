-- Self-serve "ask for more quota" perk: a premium learner who hits the 2-hour daily
-- voice cap can grant themselves one extra free hour, once per calendar day, without
-- waiting on a manual reply. Reuses the existing bonus_seconds_balance mechanism
-- (already proven to only extend live-voice-session time, never other AI features)
-- rather than inventing a second balance column, and reuses the existing append-only
-- learner_events log for the audit trail instead of a new table — query it with:
--   select user_id, occurred_at from learner_events
--   where event_type = 'extra_hour_grant' order by occurred_at desc;
create or replace function public.grant_daily_extra_hour()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_already_granted boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Locks the profile row so two rapid taps can't both slip past the check below.
  perform 1 from profiles where id = v_uid for update;

  select exists (
    select 1 from learner_events
    where user_id = v_uid
      and event_type = 'extra_hour_grant'
      and occurred_at >= date_trunc('day', now() at time zone 'utc')
  ) into v_already_granted;

  if v_already_granted then
    return jsonb_build_object('success', false, 'error', 'already_granted_today');
  end if;

  update profiles
    set bonus_seconds_balance = bonus_seconds_balance + 3600
    where id = v_uid;

  insert into learner_events (user_id, event_type, payload)
  values (v_uid, 'extra_hour_grant', jsonb_build_object('seconds_granted', 3600));

  return jsonb_build_object('success', true, 'seconds_granted', 3600);
end;
$function$;
