import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { buildAuthTokenRequest, GEMINI_AUTH_TOKEN_URL } from "./token_request.ts";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json({ error: "POST required" }, 405);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "Gemini is not configured" }, 503);

  const now = Date.now();
  const response = await fetch(
    GEMINI_AUTH_TOKEN_URL,
    buildAuthTokenRequest(apiKey, now),
  );
  if (!response.ok) {
    const failure = await response.json().catch(() => null);
    const providerMessage = String(failure?.error?.message ?? "unknown error")
      .replaceAll(apiKey, "[redacted]")
      .slice(0, 500);
    console.error("Gemini auth token request failed", response.status, providerMessage);
    return json({ error: "Could not create a Gemini Live session" }, 502);
  }
  const data = await response.json();
  const token = String(data?.name ?? "");
  return token ? json({ token }) : json({ error: "Gemini returned no session token" }, 502);
});
