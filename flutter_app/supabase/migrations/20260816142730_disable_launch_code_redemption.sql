-- Launch build: no user-facing referral or invite-code redemption.
-- Keep the historical objects for data/audit retention, but make the code
-- paths unavailable to client roles. Service-role/admin access is unaffected.
do $$
declare
  fn record;
begin
  for fn in
    select n.nspname as schema_name,
           p.proname as function_name,
           pg_get_function_identity_arguments(p.oid) as arguments
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'get_or_create_referral_code',
         'redeem_referral_code',
         'redeem_subscription_invite_code'
       )
  loop
    execute format(
      'revoke all on function %I.%I(%s) from public, anon, authenticated',
      fn.schema_name,
      fn.function_name,
      fn.arguments
    );
  end loop;

  if to_regclass('public.referral_codes') is not null then
    revoke all on table public.referral_codes from public, anon, authenticated;
  end if;

  if to_regclass('public.subscription_invite_codes') is not null then
    revoke all on table public.subscription_invite_codes from public, anon, authenticated;
  end if;

  if to_regclass('public.subscription_invite_redemptions') is not null then
    revoke all on table public.subscription_invite_redemptions from public, anon, authenticated;
  end if;
end
$$;
