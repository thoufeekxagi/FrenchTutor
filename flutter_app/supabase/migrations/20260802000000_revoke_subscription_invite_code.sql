-- Admin-only counterpart to redeem_subscription_invite_code. Setting a code's `active`
-- flag to false only blocks *future* redemptions; this claws back access that was already
-- granted to anyone who redeemed the code, without touching users who have since converted
-- to a real (RevenueCat-backed) subscription.
create or replace function public.revoke_subscription_invite_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_code_upper text := upper(trim(p_code));
  v_revoked_count integer;
begin
  update subscription_invite_codes
    set active = false
    where code = v_code_upper;

  if not found then
    return jsonb_build_object('success', false, 'error', 'invalid_code');
  end if;

  with revoked as (
    update profiles
      set subscription_active = false,
          subscription_expires_at = now()
      where subscription_product_id = 'invite:' || v_code_upper
      returning id
  )
  select count(*) into v_revoked_count from revoked;

  return jsonb_build_object('success', true, 'code', v_code_upper, 'users_revoked', v_revoked_count);
end;
$function$;

-- Only callable via service_role (dashboard / SQL editor / admin tooling) — never exposed
-- to the app or authenticated end users.
revoke all on function public.revoke_subscription_invite_code(text) from public, authenticated, anon;
grant execute on function public.revoke_subscription_invite_code(text) to service_role;
