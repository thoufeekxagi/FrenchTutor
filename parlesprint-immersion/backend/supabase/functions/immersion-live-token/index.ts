import {
  buildTokenRequest,
  LIVE_SESSION_SECONDS,
  tokenValue,
} from "./core.ts";

import { INSTALLATION_ID, isExtensionOrigin, limitsFromEnv, takeUsage } from "../_shared/usage.ts";

const env = (key: string) => Deno.env.get(key) ?? "";
const url = env("SUPABASE_URL");
const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
const anonKey = env("SUPABASE_ANON_KEY");
// A dedicated key keeps the extension's spend and rate limits separate from the app.
const googleKey = env("IMMERSION_GEMINI_API_KEY") || env("GEMINI_API_KEY");
const ipSalt = env("IMMERSION_IP_SALT");
// Units are minutes of live captions. One token reserves LIVE_SESSION_SECONDS / 60.
const liveLimits = limitsFromEnv("IMMERSION_LIVE_LIMIT", { install: 30, ip: 40, global: 360, burst: 4 });

function safeProviderError(value: unknown): string {
  if (!value || typeof value !== "object") return "unknown_provider_error";
  const error = (value as Record<string, unknown>).error;
  if (!error || typeof error !== "object") return "unknown_provider_error";
  const details = error as Record<string, unknown>;
  const status = typeof details.status === "string" ? details.status : "";
  const code = Number.isInteger(details.code) ? String(details.code) : "";
  const message = typeof details.message === "string"
    ? details.message.replace(/\s+/g, " ").trim().slice(0, 300)
    : "";
  return [status, code, message]
    .filter(Boolean)
    .join(" ")
    .replaceAll(googleKey, "[redacted]")
    .replace(/AIza[0-9A-Za-z_-]{20,}/g, "[redacted]");
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin") ?? "";
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    Vary: "Origin",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (isExtensionOrigin(origin)) headers["Access-Control-Allow-Origin"] = origin;
  const respond = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers });

  if (!isExtensionOrigin(origin))
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
    if (!body || typeof body !== "object")
      return respond(400, { error: "invalid_request" });
    if (body.consent !== true) return respond(403, { error: "consent_required" });
    if (typeof body.installationId !== "string" || !INSTALLATION_ID.test(body.installationId))
      return respond(400, { error: "invalid_request" });
    const usage = await takeUsage({
      url, serviceKey, salt: ipSalt, kind: "live", installationId: body.installationId,
      request, units: Math.ceil(LIVE_SESSION_SECONDS / 60), limits: liveLimits,
    });
    if (usage === "unavailable" || usage === "invalid") return respond(503, { error: "quota_unavailable" });
    if (usage !== "ok") return respond(429, { error: "daily_transcription_limit_reached", limit: usage });

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
      const providerBody = await tokenResponse.json().catch(() => null);
      console.error(
        "gemini_live_token_failed",
        tokenResponse.status,
        safeProviderError(providerBody),
      );
      return respond(502, { error: "transcription_provider_unavailable" });
    }
    const token = tokenValue(await tokenResponse.json());
    if (!token) {
      return respond(502, { error: "invalid_provider_response" });
    }
    return respond(200, {
      token,
      expiresAt: tokenRequest.expireTime,
      sessionSeconds: LIVE_SESSION_SECONDS,
    });
  } catch {
    return respond(503, { error: "temporarily_unavailable" });
  }
});
