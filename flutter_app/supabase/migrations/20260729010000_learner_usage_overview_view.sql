-- One-stop admin view for "who's using the app the most" — no manual SQL needed,
-- just `select * from learner_usage_overview order by total_voice_seconds desc;`
-- in Supabase Studio's SQL editor, or open it directly under Table Editor > Views.
create or replace view public.learner_usage_overview as
select
  p.id as user_id,
  p.subscription_active,
  p.subscription_product_id,
  p.subscription_expires_at,
  p.bonus_seconds_balance,
  coalesce(cu.total_voice_seconds, 0) as total_voice_seconds,
  coalesce(cu.active_days, 0) as active_days,
  cu.last_active_date,
  coalesce(eh.extra_hour_grants, 0) as extra_hour_grants_used,
  p.created_at as signed_up_at
from public.profiles p
left join (
  select
    user_id,
    sum(seconds_used) as total_voice_seconds,
    count(*) as active_days,
    max(local_date) as last_active_date
  from public.credit_usage_state
  group by user_id
) cu on cu.user_id = p.id
left join (
  select user_id, count(*) as extra_hour_grants
  from public.learner_events
  where event_type = 'extra_hour_grant'
  group by user_id
) eh on eh.user_id = p.id;

comment on view public.learner_usage_overview is 'Admin-facing rollup: total voice seconds, active days, subscription status, and extra-hour-grant count per learner. Query directly in Supabase Studio to see the most active users and who has used their self-serve bonus hour.';
