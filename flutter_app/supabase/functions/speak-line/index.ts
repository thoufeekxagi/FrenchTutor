import { createClient } from "jsr:@supabase/supabase-js@2";

// One short French line, spoken once in a tutor's voice, saved for everyone.
// Cache path: <version>/<voice>/<sha256 of the normalised text>.pcm (24 kHz,
// 16-bit, mono). The phone reads the bucket directly when the clip exists and
// calls this function only to make a missing one.
const BUCKET = "speak-lines";
const VERSION = "tts1";
const MODEL = "gemini-3.8-flash-lite-tts";
const VOICES = new Set(["Aoede", "Puck", "Leda", "Orus"]);
const MAX_CHARS = 200;
const WINDOW_MS = 10 * 60 * 1000;
const MAX_NEW_PER_WINDOW = 120;

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
const recent = new Map<string, { startedAt: number; count: number }>();

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...headers, "Content-Type": "application/json" },
  });
}

function key(name: string): string | undefined {
  const direct = Deno.env.get(name);
  if (direct) return direct;
  if (name === "SUPABASE_ANON_KEY") {
    const publishable = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
    if (publishable) return publishable;
    try {
      const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
      if (typeof keys.default === "string") return keys.default;
    } catch (_) { /* fall through to the configuration error */ }
  }
  if (name === "SUPABASE_SERVICE_ROLE_KEY") {
    return Deno.env.get("SUPABASE_SECRET_KEY");
  }
  return undefined;
}

async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// Gemini returns a WAV. Keep only the raw 16-bit samples.
function wavToPcm(bytes: Uint8Array): Uint8Array | null {
  if (bytes.length < 44) return null;
  const tag = (o: number) => String.fromCharCode(...bytes.slice(o, o + 4));
  if (tag(0) !== "RIFF") return bytes.length % 2 === 0 ? bytes : null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 12;
  while (offset + 8 <= bytes.length) {
    const id = tag(offset);
    const size = view.getUint32(offset + 4, true);
    if (id === "data") {
      const end = Math.min(offset + 8 + size, bytes.length);
      const pcm = bytes.slice(offset + 8, end - ((end - offset - 8) % 2));
      return pcm.length > 0 ? pcm : null;
    }
    offset += 8 + size + (size % 2);
  }
  return null;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json({ error: "POST required" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const publicKey = key("SUPABASE_ANON_KEY");
  const serviceKey = key("SUPABASE_SERVICE_ROLE_KEY");
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  const authHeader = request.headers.get("Authorization");
  if (!url || !publicKey || !serviceKey || !geminiKey) {
    return json({ error: "Audio service is not configured." }, 503);
  }
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "Sign in to hear lines." }, 401);
  }

  try {
    const userClient = createClient(url, publicKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: authError } = await userClient.auth.getUser(
      authHeader.slice("Bearer ".length),
    );
    if (authError || !userData.user) {
      return json({ error: "Sign in to hear lines." }, 401);
    }
    const userId = userData.user.id;

    const input = await request.json();
    const text = String(input.text ?? "").trim().replace(/\s+/g, " ");
    const voice = String(input.voice ?? "");
    if (!text || text.length > MAX_CHARS || !VOICES.has(voice)) {
      return json({ error: "Invalid line or voice." }, 400);
    }

    const path = `${VERSION}/${voice}/${await sha256Hex(text)}.pcm`;
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const octet = { ...headers, "Content-Type": "application/octet-stream" };

    // The phone has already read the bucket directly, so this is a miss.
    // A miss costs money: bound how many one account can make.
    const now = Date.now();
    const seen = recent.get(userId);
    if (!seen || now - seen.startedAt >= WINDOW_MS) {
      recent.set(userId, { startedAt: now, count: 1 });
    } else if (seen.count >= MAX_NEW_PER_WINDOW) {
      return json({ error: "Too many new lines. Try again shortly." }, 429);
    } else {
      seen.count += 1;
    }

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey },
        body: JSON.stringify({
          contents: [{ parts: [{ text }] }],
          generationConfig: {
            responseModalities: ["AUDIO"],
            speechConfig: {
              languageCode: "fr-FR",
              voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } },
            },
          },
        }),
      },
    );
    if (!response.ok) {
      console.error("Gemini TTS failed", response.status);
      return json(
        { error: "Could not make this line." },
        response.status === 429 ? 429 : 502,
      );
    }
    const data = await response.json();
    const b64 = data?.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;
    const pcm = typeof b64 === "string" ? wavToPcm(b64ToBytes(b64)) : null;
    if (!pcm) return json({ error: "Could not make this line." }, 502);

    // Saving happens after the reply is sent; the learner already has audio.
    const save = admin.storage.from(BUCKET).upload(path, pcm, {
      contentType: "application/octet-stream",
      upsert: false,
    }).then(({ error }) => {
      if (error && !/exists|duplicate/i.test(error.message)) {
        console.error("Speak cache save failed", error.message);
      }
    });
    // deno-lint-ignore no-explicit-any
    const runtime = (globalThis as any).EdgeRuntime;
    if (runtime?.waitUntil) runtime.waitUntil(save);
    else await save;
    return new Response(pcm, { headers: { ...octet, "X-Speak-Cache": "miss" } });
  } catch (error) {
    console.error("Speak line failed", error);
    return json({ error: "Audio service is temporarily unavailable." }, 503);
  }
});
