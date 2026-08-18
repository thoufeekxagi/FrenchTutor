import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Best-effort abuse control for the intentionally pre-signup demo. The token
// itself is single-use and expires quickly; this memory window adds a coarse
// per-edge-instance cap without storing a learner identity before signup.
const WINDOW_MS = 15 * 60 * 1000;
const MAX_TOKENS_PER_WINDOW = 5;
const requests = new Map<string, { startedAt: number; count: number }>();

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

function clientKey(request: Request): string {
  return (
    request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    "unknown"
  );
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json({ error: "POST required" }, 405);

  const now = Date.now();
  const key = clientKey(request);
  const previous = requests.get(key);
  if (!previous || now - previous.startedAt >= WINDOW_MS) {
    requests.set(key, { startedAt: now, count: 1 });
  } else {
    if (previous.count >= MAX_TOKENS_PER_WINDOW) {
      return json({ error: "Trial session limit reached. Try again later." }, 429);
    }
    previous.count += 1;
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "Gemini is not configured" }, 503);

  const response = await fetch("https://generativelanguage.googleapis.com/v1alpha/auth_tokens", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify({
      uses: 1,
      expireTime: new Date(now + 5 * 60 * 1000).toISOString(),
      newSessionExpireTime: new Date(now + 60 * 1000).toISOString(),
    }),
  });
  if (!response.ok) {
    console.error("Gemini trial auth token request failed", response.status);
    return json({ error: "Could not create a Gemini trial session" }, 502);
  }
  const data = await response.json();
  const token = String(data?.name ?? "");
  return token ? json({ token }) : json({ error: "Gemini returned no trial token" }, 502);
});
