-- Admin-issued invite codes that grant a paid subscription period (distinct from the
-- existing user-to-user referral_codes system, which only grants bonus speaking minutes).
create table public.subscription_invite_codes (
  code text primary key,
  grants_months integer not null check (grants_months > 0),
  max_redemptions integer not null default 1 check (max_redemptions > 0),
  successful_redemptions integer not null default 0,
  active boolean not null default true,
  label text,
  created_at timestamptz not null default now()
);
comment on table public.subscription_invite_codes is 'Admin-created codes that grant N months of full subscription access when redeemed. Separate from referral_codes (which only grants bonus speaking minutes).';

-- One row per (code, user) redemption. A user may redeem multiple *different* codes over
-- time (e.g. a renewal grant), but never the same code twice.
create table public.subscription_invite_redemptions (
  id uuid primary key default gen_random_uuid(),
  code text not null references public.subscription_invite_codes(code),
  redeemed_by_user_id uuid not null references auth.users(id),
  months_granted integer not null,
  redeemed_at timestamptz not null default now(),
  unique (code, redeemed_by_user_id)
);
comment on table public.subscription_invite_redemptions is 'Audit log of subscription invite code redemptions. Unique on (code, user) so the same code cannot be redeemed twice by the same account.';

alter table public.subscription_invite_codes enable row level security;
alter table public.subscription_invite_redemptions enable row level security;

-- No public policies: all access goes through the SECURITY DEFINER RPC below, or the
-- dashboard/service role for admin code creation.

create or replace function public.redeem_subscription_invite_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_code_upper text := upper(trim(p_code));
  v_months integer;
  v_max integer;
  v_used integer;
  v_active boolean;
  v_new_expiry timestamptz;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  if exists (
    select 1 from subscription_invite_redemptions
    where code = v_code_upper and redeemed_by_user_id = v_uid
  ) then
    return jsonb_build_object('success', false, 'error', 'already_redeemed');
  end if;

  select grants_months, max_redemptions, successful_redemptions, active
    into v_months, v_max, v_used, v_active
    from subscription_invite_codes
    where code = v_code_upper
    for update;

  if v_months is null then
    return jsonb_build_object('success', false, 'error', 'invalid_code');
  end if;

  if not v_active then
    return jsonb_build_object('success', false, 'error', 'code_inactive');
  end if;

  if v_used >= v_max then
    return jsonb_build_object('success', false, 'error', 'code_limit_reached');
  end if;

  insert into subscription_invite_redemptions (code, redeemed_by_user_id, months_granted)
  values (v_code_upper, v_uid, v_months);

  update subscription_invite_codes
    set successful_redemptions = successful_redemptions + 1
    where code = v_code_upper;

  select greatest(coalesce(subscription_expires_at, now()), now()) + (v_months || ' months')::interval
    into v_new_expiry
    from profiles
    where id = v_uid;

  update profiles
    set subscription_active = true,
        subscription_product_id = 'invite:' || v_code_upper,
        subscription_expires_at = v_new_expiry
    where id = v_uid;

  return jsonb_build_object('success', true, 'months_granted', v_months, 'expires_at', v_new_expiry);
end;
$function$;
