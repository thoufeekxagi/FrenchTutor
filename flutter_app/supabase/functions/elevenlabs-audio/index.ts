import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// ElevenLabs stays behind this authenticated Supabase boundary. The Flutter
// client receives audio only; it never receives the provider credential.
const ELEVENLABS_API = "https://api.elevenlabs.io";
const NARRATION_MODEL = "eleven_multilingual_v2";
const DEFAULT_NARRATION_VOICE = "21m00Tcm4TlvDq8ikWAM";
const DEFAULT_GUEST_VOICE = "pNInz6obpgDQGcFmaJgB";
const MAX_TEXT_LENGTH = 12_000;
const MAX_DIALOGUE_TURNS = 8;
const MAX_DIALOGUE_CHARACTERS = 2_000;
const MAX_MUSIC_LENGTH_MS = 120_000;

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

function providerErrorMessage(data: unknown): string {
  if (!data || typeof data !== "object") return "ElevenLabs request failed";
  const detail = (data as { detail?: unknown }).detail;
  if (detail && typeof detail === "object") {
    const message = (detail as { message?: unknown }).message;
    const status = (detail as { status?: unknown }).status;
    if (typeof status === "string" && status.length > 0) return status;
    if (typeof message === "string" && message.length > 0) return message;
  }
  const message = (data as { message?: unknown }).message;
  return typeof message === "string" && message.length > 0
    ? message
    : "ElevenLabs request failed";
}

function providerStatus(status: number): number {
  if (status === 402) return 402;
  if (status === 401 || status === 403) return 502;
  if (status === 429) return 429;
  return status >= 500 ? 502 : 400;
}

function providerKey(): string | null {
  return (
    Deno.env.get("ELEVEN_LABS_API_KEY")?.trim() ||
    Deno.env.get("ELEVENLABS_API_KEY")?.trim() ||
    null
  );
}

function voiceId(value: unknown, fallback: string): string {
  const candidate = typeof value === "string" ? value.trim() : "";
  return (candidate || fallback).slice(0, 100);
}

function boundedText(value: unknown, max = MAX_TEXT_LENGTH): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  if (!text || text.length > max) return null;
  return text;
}

async function callElevenLabs(
  path: string,
  body: Record<string, unknown>,
  output: "json" | "audio",
): Promise<Response> {
  const apiKey = providerKey();
  if (!apiKey) return json({ error: "ElevenLabs is not configured" }, 503);

  let response: Response;
  try {
    response = await fetch(`${ELEVENLABS_API}${path}`, {
      method: "POST",
      headers: {
        "xi-api-key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
  } catch (_) {
    return json({ error: "ElevenLabs could not be reached" }, 502);
  }

  if (!response.ok) {
    const details = await response.json().catch(() => ({}));
    const message = providerErrorMessage(details);
    console.error("ElevenLabs provider error", response.status, message);
    return json({ error: message }, providerStatus(response.status));
  }

  if (output === "audio") {
    return new Response(await response.arrayBuffer(), {
      status: 200,
      headers: {
        "Content-Type": "application/octet-stream",
        "Cache-Control": "no-store",
        "X-Audio-Format": "audio/mpeg",
      },
    });
  }

  return response;
}

async function narration(body: Record<string, unknown>) {
  const text = boundedText(body.text);
  if (!text) return json({ error: "Narration text is required" }, 400);

  const response = await callElevenLabs(
    `/v1/text-to-speech/${voiceId(
      body.voiceId,
      Deno.env.get("ELEVENLABS_NARRATION_VOICE_ID") ?? DEFAULT_NARRATION_VOICE,
    )}/with-timestamps?output_format=mp3_44100_128`,
    {
      text,
      model_id: NARRATION_MODEL,
      ...(body.voiceSettings && typeof body.voiceSettings === "object"
        ? { voice_settings: body.voiceSettings }
        : {}),
    },
    "json",
  );
  if (response.status !== 200) return response;
  const data = await response.json();
  return json({
    mode: body.mode,
    provider: "elevenlabs",
    model: NARRATION_MODEL,
    mimeType: "audio/mpeg",
    audioBase64: data.audio_base64 ?? "",
    alignment: data.normalized_alignment ?? data.alignment ?? null,
  });
}

async function dialogue(body: Record<string, unknown>) {
  if (!Array.isArray(body.inputs) || body.inputs.length < 2 || body.inputs.length > MAX_DIALOGUE_TURNS) {
    return json({ error: `Podcast dialogue needs 2-${MAX_DIALOGUE_TURNS} turns` }, 400);
  }

  const hostVoice = voiceId(
    body.hostVoiceId,
    Deno.env.get("ELEVENLABS_HOST_VOICE_ID") ?? DEFAULT_NARRATION_VOICE,
  );
  const guestVoice = voiceId(
    body.guestVoiceId,
    Deno.env.get("ELEVENLABS_GUEST_VOICE_ID") ?? DEFAULT_GUEST_VOICE,
  );
  const inputs: Array<{ text: string; voice_id: string }> = [];
  let totalCharacters = 0;
  for (let index = 0; index < body.inputs.length; index += 1) {
    const raw = body.inputs[index];
    const text = raw && typeof raw === "object"
      ? boundedText((raw as { text?: unknown }).text, 2_500)
      : boundedText(raw, 2_500);
    if (!text) return json({ error: "Every podcast turn needs text" }, 400);
    totalCharacters += text.length;
    if (totalCharacters > MAX_DIALOGUE_CHARACTERS) {
      return json({ error: "Podcast dialogue is limited to 2,000 characters" }, 400);
    }
    const requestedVoice = raw && typeof raw === "object"
      ? (raw as { voiceId?: unknown }).voiceId
      : null;
    inputs.push({
      text,
      voice_id: voiceId(requestedVoice, index % 2 === 0 ? hostVoice : guestVoice),
    });
  }

  const response = await callElevenLabs(
    "/v1/text-to-dialogue/with-timestamps?output_format=mp3_44100_128",
    { inputs, model_id: "eleven_v3" },
    "json",
  );
  if (response.status !== 200) return response;
  const data = await response.json();
  return json({
    mode: "podcast",
    provider: "elevenlabs",
    model: NARRATION_MODEL,
    mimeType: "audio/mpeg",
    audioBase64: data.audio_base64 ?? "",
    voiceSegments: data.voice_segments ?? [],
    alignment: data.normalized_alignment ?? data.alignment ?? null,
  });
}

async function music(body: Record<string, unknown>) {
  const prompt = boundedText(body.prompt, 4_100);
  if (!prompt) return json({ error: "Music prompt is required" }, 400);
  const requestedLength = Number(body.musicLengthMs ?? 30_000);
  if (!Number.isFinite(requestedLength)) return json({ error: "Invalid music length" }, 400);
  const musicLengthMs = Math.min(Math.max(Math.round(requestedLength), 3_000), MAX_MUSIC_LENGTH_MS);

  return await callElevenLabs(
    "/v1/music?output_format=mp3_44100_128",
    {
      prompt,
      music_length_ms: musicLengthMs,
      force_instrumental: body.forceInstrumental === true,
      model_id: "music_v1",
    },
    "audio",
  );
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json({ error: "POST required" }, 405);
  if (!request.headers.get("Authorization")) return json({ error: "Authentication required" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid JSON" }, 400);
  }

  switch (body.mode) {
    case "narration":
    case "story":
    case "educational":
      return await narration(body);
    case "podcast":
      return await dialogue(body);
    case "music":
      return await music(body);
    default:
      return json({ error: "Unsupported audio mode" }, 400);
  }
});
