// Receives RevenueCat webhook events (purchase/renewal/cancellation) and
// syncs subscription state into Supabase `profiles`, which is the one place
// the app reads entitlement state from (see PilotAccessService).
//
// Inert until a RevenueCat project exists: configure this function's URL as
// the webhook endpoint in the RevenueCat dashboard, and set the
// REVENUECAT_WEBHOOK_SECRET env var (via `supabase secrets set`) to match
// the "Authorization header" value you configure there. Until that secret
// is set, every request is rejected — safe by default, nothing to disable.
//
// RevenueCat sets `event.app_user_id` to whatever was passed as `appUserID`
// in RevenueCatService.configure() — that's the Supabase user id, so no
// separate mapping table is needed.
import { createClient } from "jsr:@supabase/supabase-js@2";

const ACTIVE_EVENT_TYPES = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
]);

const INACTIVE_EVENT_TYPES = new Set([
  "CANCELLATION",
  "EXPIRATION",
  "BILLING_ISSUE",
]);

Deno.serve(async (req: Request) => {
  const expectedSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  const authHeader = req.headers.get("Authorization");
  if (!expectedSecret || authHeader !== `Bearer ${expectedSecret}`) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const payload = await req.json();
  const event = payload?.event;
  if (!event?.app_user_id || !event?.type) {
    return new Response(JSON.stringify({ error: "Malformed payload" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  const isActive = ACTIVE_EVENT_TYPES.has(event.type);
  const isInactive = INACTIVE_EVENT_TYPES.has(event.type);
  if (!isActive && !isInactive) {
    // An event type we don't act on (e.g. TRANSFER, TEST) — acknowledge and skip.
    return new Response(JSON.stringify({ success: true, skipped: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { error } = await admin
    .from("profiles")
    .update({
      subscription_active: isActive,
      subscription_product_id: event.product_id ?? null,
      subscription_expires_at: event.expiration_at_ms
        ? new Date(event.expiration_at_ms).toISOString()
        : null,
    })
    .eq("id", event.app_user_id);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
