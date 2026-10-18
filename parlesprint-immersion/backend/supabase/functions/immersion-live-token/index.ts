import {
  buildTokenRequest,
  GLOBAL_QUOTA_SECONDS,
  hashInstallation,
  INSTALLATION_QUOTA_SECONDS,
  LIVE_SESSION_SECONDS,
  tokenValue,
  validInstallation,
} from "./core.ts";

const env = (key: string) => Deno.env.get(key) ?? "";
const url = env("SUPABASE_URL");
const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
const anonKey = env("SUPABASE_ANON_KEY");
const googleKey = env("GEMINI_API_KEY");
const extensionOrigin = "chrome-extension://ijclgmkoljddlalgcnpodeemcmcipolb";

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin") ?? "";
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    Vary: "Origin",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (origin === extensionOrigin) headers["Access-Control-Allow-Origin"] = origin;
  const respond = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers });

  if (origin !== extensionOrigin)
    return respond(403, { error: "origin_not_allowed" });
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (request.method !== "POST") return respond(405, { error: "method_not_allowed" });
  if (!url || !serviceKey || !anonKey || !googleKey)
    return respond(503, { error: "transcription_not_configured" });

  const authorization = request.headers.get("authorization") ?? "";
  if (request.headers.get("apikey") !== anonKey || authorization !== `Bearer ${anonKey}`)
    return respond(401, { error: "invalid_client" });

  try {
    const text = await request.text();
    if (text.length > 2048) return respond(413, { error: "request_too_large" });
    const body = JSON.parse(text);
    if (!body || typeof body !== "object" || !validInstallation(body.installationId))
      return respond(400, { error: "invalid_request" });
    if (body.consent !== true) return respond(403, { error: "consent_required" });

    const installationHash = await hashInstallation(body.installationId);
    const headersForDb = {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    };
    const quotaResponse = await fetch(`${url}/rest/v1/rpc/immersion_take_transcription_quota_units`, {
      method: "POST",
      headers: headersForDb,
      body: JSON.stringify({
        p_installation_hash: installationHash,
        p_install_limit: INSTALLATION_QUOTA_SECONDS / 12,
        p_global_limit: GLOBAL_QUOTA_SECONDS / 12,
        p_units: LIVE_SESSION_SECONDS / 12,
      }),
      signal: AbortSignal.timeout(7000),
    });
    if (!quotaResponse.ok) return respond(503, { error: "quota_unavailable" });
    if (await quotaResponse.json() !== true)
      return respond(429, { error: "daily_transcription_limit_reached" });

    const tokenRequest = buildTokenRequest();
    const tokenResponse = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/auth_tokens",
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": googleKey },
        body: JSON.stringify(tokenRequest),
        signal: AbortSignal.timeout(10000),
      },
    );
    if (!tokenResponse.ok) {
      console.error("gemini_live_token_failed", tokenResponse.status);
      return respond(502, { error: "transcription_provider_unavailable" });
    }
    const token = tokenValue(await tokenResponse.json());
    if (!token) return respond(502, { error: "invalid_provider_response" });
    return respond(200, {
      token,
      expiresAt: tokenRequest.expireTime,
      sessionSeconds: LIVE_SESSION_SECONDS,
    });
  } catch {
    return respond(503, { error: "temporarily_unavailable" });
  }
});
