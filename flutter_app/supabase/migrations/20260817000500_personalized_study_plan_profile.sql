-- Personalized onboarding preferences used by the Flutter study-plan layer.
-- The local SQLite migration is V26; these columns keep signed-in profiles
-- consistent across reinstalls and devices.
alter table public.profiles
  add column if not exists preferred_days text,
  add column if not exists interests text,
  add column if not exists time_zone text,
  add column if not exists notification_permission_state text not null default 'not_requested',
  add column if not exists onboarding_version text not null default 'v1';
