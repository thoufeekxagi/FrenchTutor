-- Existing invite-code records remain for audit/history, but they must not
-- continue to unlock paid digital content in the App Store build.
update public.profiles
   set subscription_active = false,
       subscription_product_id = null,
       subscription_expires_at = null
 where subscription_product_id ilike 'invite:%';
