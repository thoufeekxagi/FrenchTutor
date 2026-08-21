import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// ElevenLabs stays behind this authenticated Supabase boundary. The Flutter
// client receives audio only; it never receives the provider credential.
const ELEVENLABS_API = "https://api.elevenlabs.io";
const NARRATION_MODEL = "eleven_v3";
const EDUCATIONAL_MODEL = "eleven_multilingual_v2";
const DEFAULT_NARRATION_VOICE = "21m00Tcm4TlvDq8ikWAM";
const DEFAULT_GUEST_VOICE = "pNInz6obpgDQGcFmaJgB";
const MAX_TEXT_LENGTH = 12_000;
const MAX_DIALOGUE_TURNS = 8;
const MAX_DIALOGUE_CHARACTERS = 2_000;
const MAX_MUSIC_LENGTH_MS = 120_000;
const MAX_MUSIC_LYRIC_LINES = 16;
const MAX_MUSIC_LYRIC_CHARACTERS = 2_400;
// Music is nondeterministic; allow one extra bounded regeneration when the
// generated vocals do not preserve the canonical French lyrics.
const MUSIC_VALIDATION_ATTEMPTS = 3;
const DEFAULT_MUSIC_STYLES = [
  "warm acoustic pop",
  "French vocals",
  "clear pronunciation",
  "playful melody",
];

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

function configuredVoice(name: string, fallback: string): string {
  return Deno.env.get(name)?.trim() || fallback;
}

function boundedText(value: unknown, max = MAX_TEXT_LENGTH): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  if (!text || text.length > max) return null;
  return text;
}

function renderDeliveryText(text: string, mode: unknown): string {
  if (mode === "educational") return text;
  // Eleven v3 reads short audio tags as performance direction. These are
  // renderer-only instructions; the canonical French text stays unchanged
  // for the learner and for validation.
  return mode === "story"
    ? `[calm, measured documentary narration] ${text}`
    : `[warm, expressive narration] ${text}`;
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
        ...headers,
        "Content-Type": "application/octet-stream",
        "Cache-Control": "no-store",
        "X-Audio-Format": "audio/mpeg",
      },
    });
  }

  return response;
}

async function providerResponse(
  path: string,
  body: BodyInit,
  contentType?: string,
): Promise<Response> {
  const apiKey = providerKey();
  if (!apiKey) return json({ error: "ElevenLabs is not configured" }, 503);

  let response: Response;
  try {
    response = await fetch(`${ELEVENLABS_API}${path}`, {
      method: "POST",
      headers: {
        "xi-api-key": apiKey,
        ...(contentType ? { "Content-Type": contentType } : {}),
      },
      body,
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
  return response;
}

async function narration(body: Record<string, unknown>) {
  const text = boundedText(body.text);
  if (!text) return json({ error: "Narration text is required" }, 400);
  const model = body.mode === "educational" ? EDUCATIONAL_MODEL : NARRATION_MODEL;
  const renderText = renderDeliveryText(text, body.mode);

  const response = await callElevenLabs(
    `/v1/text-to-speech/${voiceId(
      body.voiceId,
      configuredVoice("ELEVENLABS_NARRATION_VOICE_ID", DEFAULT_NARRATION_VOICE),
    )}/with-timestamps?output_format=mp3_44100_128`,
    {
      text: renderText,
      model_id: model,
      voice_settings: body.voiceSettings && typeof body.voiceSettings === "object"
        ? body.voiceSettings
        : {
            stability: body.mode === "educational" ? 0.72 : 0.58,
            similarity_boost: 0.82,
            style: body.mode === "story" ? 0.18 : 0.08,
            use_speaker_boost: true,
            // A deliberately slower render keeps beginner French intelligible.
            // The player still has its own independent speed control.
            speed: body.mode === "educational" ? 0.78 : 0.76,
          },
    },
    "json",
  );
  if (response.status !== 200) return response;
  const data = await response.json();
  return json({
    mode: body.mode,
    provider: "elevenlabs",
    model,
    mimeType: "audio/mpeg",
    audioBase64: data.audio_base64 ?? "",
    alignment: data.normalized_alignment ?? data.alignment ?? null,
    validation: {
      accepted: true,
      method: "exact_input_with_timestamps",
      expectedText: text,
      score: 1,
    },
  });
}

async function dialogue(body: Record<string, unknown>) {
  if (!Array.isArray(body.inputs) || body.inputs.length < 2 || body.inputs.length > MAX_DIALOGUE_TURNS) {
    return json({ error: `Podcast dialogue needs 2-${MAX_DIALOGUE_TURNS} turns` }, 400);
  }

  const hostVoice = voiceId(
    body.hostVoiceId,
    configuredVoice("ELEVENLABS_HOST_VOICE_ID", DEFAULT_NARRATION_VOICE),
  );
  const guestVoice = voiceId(
    body.guestVoiceId,
    configuredVoice("ELEVENLABS_GUEST_VOICE_ID", DEFAULT_GUEST_VOICE),
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
    const deliveryTag = index % 2 === 0
      ? (index === 0 ? "[brightly]" : "[curiously]")
      : (index === 1 ? "[warmly]" : "[thoughtfully]");
    inputs.push({
      text: `${deliveryTag} ${text}`,
      voice_id: voiceId(requestedVoice, index % 2 === 0 ? hostVoice : guestVoice),
    });
  }

  const response = await callElevenLabs(
    "/v1/text-to-dialogue/with-timestamps?output_format=mp3_44100_128",
    { inputs, model_id: "eleven_v3", language_code: "fr" },
    "json",
  );
  if (response.status !== 200) return response;
  const data = await response.json();
  return json({
    mode: "podcast",
    provider: "elevenlabs",
    model: "eleven_v3",
    mimeType: "audio/mpeg",
    audioBase64: data.audio_base64 ?? "",
    voiceSegments: data.voice_segments ?? [],
    alignment: data.normalized_alignment ?? data.alignment ?? null,
    validation: {
      accepted: true,
      method: "exact_dialogue_inputs_with_timestamps",
      expectedText: inputs.map((input) => input.text.replace(/^\[[^\]]+\]\s*/, "")).join(" "),
      score: 1,
    },
  });
}

function boundedLyrics(value: unknown): string[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_MUSIC_LYRIC_LINES) {
    return null;
  }
  const lines = value.map((line) => boundedText(line, 300));
  if (lines.some((line) => line == null)) return null;
  const resolved = lines as string[];
  const totalCharacters = resolved.reduce((total, line) => total + line.length, 0);
  return totalCharacters > MAX_MUSIC_LYRIC_CHARACTERS ? null : resolved;
}

// ElevenLabs expects short style tags inside a composition plan. The client
// also sends the story title, summary, and keywords for context; forwarding
// that whole prose string as one style tag causes bad_composition_plan.
function musicStyleTags(value: unknown): string[] {
  const raw = boundedText(value, 500) ?? "";
  const requested = raw
    .split(/[.,;:!?|]+/)
    .map((item) => item.trim().replace(/\s+/g, " "))
    .filter((item) => {
      const wordCount = item.split(" ").filter(Boolean).length;
      const lower = item.toLowerCase();
      const unsafeReference = ["in the style", "copyright", "spotify", "justin bieber", "attenborough"]
        .some((marker) => lower.includes(marker));
      const englishStyleText = /^[a-z0-9 ()+/'-]+$/i.test(item);
      return !unsafeReference && englishStyleText && item.length >= 2 && item.length <= 48 && wordCount <= 6;
    });
  return [...new Set([...DEFAULT_MUSIC_STYLES, ...requested])].slice(0, 8);
}

function musicSections(lyrics: string[], totalDurationMs: number, styles: string[]) {
  const count = lyrics.length;
  const firstEnd = Math.max(1, Math.ceil(count * 0.34));
  const secondEnd = Math.min(count, firstEnd + Math.max(1, Math.ceil(count * 0.28)));
  const groups = [
    {
      name: "Verse 1",
      lines: lyrics.slice(0, firstEnd),
      local: ["intimate verse", "clear French vocals", "light fingerpicked guitar"],
    },
    {
      name: "Refrain",
      lines: lyrics.slice(firstEnd, secondEnd),
      local: ["memorable melodic refrain", "lift in energy", "warm layered vocals"],
    },
    {
      name: "Verse 2 and outro",
      lines: lyrics.slice(secondEnd),
      local: ["gentle resolution", "polished studio production", "soft rhythmic ending"],
    },
  ].filter((group) => group.lines.length > 0);
  const duration = Math.max(3_000, Math.floor(totalDurationMs / groups.length));
  return groups.map((group, index) => ({
    section_name: group.name,
    duration_ms: index === groups.length - 1
      ? totalDurationMs - duration * (groups.length - 1)
      : duration,
    lines: group.lines,
    positive_local_styles: [...styles.slice(0, 3), ...group.local],
    negative_local_styles: ["spoken delivery", "distorted vocals", "English lyrics"],
  }));
}

function normalizeTokens(value: string): string[] {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[’']/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

function editDistance(left: string[], right: string[]): number {
  const previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    let diagonal = previous[0];
    previous[0] = leftIndex;
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      const above = previous[rightIndex];
      const substitution = diagonal + (left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1);
      previous[rightIndex] = Math.min(
        previous[rightIndex] + 1,
        previous[rightIndex - 1] + 1,
        substitution,
      );
      diagonal = above;
    }
  }
  return previous[right.length];
}

function transcriptValidation(expectedText: string, actualText: string) {
  const expected = normalizeTokens(expectedText);
  const actual = normalizeTokens(actualText);
  if (expected.length === 0 || actual.length === 0) {
    return { accepted: false, score: 0 };
  }
  const distance = editDistance(expected, actual);
  const score = Math.max(0, 1 - distance / Math.max(expected.length, actual.length));
  const accepted = score >= 0.84 && actual.length <= Math.ceil(expected.length * 1.35);
  return { accepted, score: Number(score.toFixed(3)) };
}

function byteIndexOf(haystack: Uint8Array, needle: Uint8Array, start = 0): number {
  outer: for (let index = start; index <= haystack.length - needle.length; index += 1) {
    for (let offset = 0; offset < needle.length; offset += 1) {
      if (haystack[index + offset] !== needle[offset]) continue outer;
    }
    return index;
  }
  return -1;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

async function parseMultipartMusic(response: Response): Promise<{ audio: Uint8Array; metadata: Record<string, unknown> } | null> {
  const contentType = response.headers.get("content-type") ?? "";
  const boundaryMatch = contentType.match(/boundary="?([^";]+)"?/i);
  if (!boundaryMatch) return null;
  const bytes = new Uint8Array(await response.arrayBuffer());
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const boundary = encoder.encode(`--${boundaryMatch[1]}`);
  const separator = encoder.encode("\r\n\r\n");
  let cursor = byteIndexOf(bytes, boundary);
  let audio: Uint8Array | null = null;
  let metadata: Record<string, unknown> = {};

  while (cursor >= 0) {
    let partStart = cursor + boundary.length;
    if (bytes[partStart] === 45 && bytes[partStart + 1] === 45) break;
    if (bytes[partStart] === 13 && bytes[partStart + 1] === 10) partStart += 2;
    const headerEnd = byteIndexOf(bytes, separator, partStart);
    if (headerEnd < 0) break;
    const nextBoundary = byteIndexOf(bytes, boundary, headerEnd + separator.length);
    if (nextBoundary < 0) break;
    const partHeaders = decoder.decode(bytes.slice(partStart, headerEnd)).toLowerCase();
    let contentEnd = nextBoundary;
    if (bytes[contentEnd - 2] === 13 && bytes[contentEnd - 1] === 10) contentEnd -= 2;
    const part = bytes.slice(headerEnd + separator.length, contentEnd);
    if (partHeaders.includes("application/json")) {
      try {
        const parsed = JSON.parse(decoder.decode(part));
        if (parsed && typeof parsed === "object") metadata = parsed as Record<string, unknown>;
      } catch (_) {
        // A malformed metadata part does not make the audio bytes unsafe to use;
        // the caller still requires the separate transcript validation below.
      }
    } else if (part.length > 0) {
      audio = part;
    }
    cursor = nextBoundary;
  }

  return audio == null ? null : { audio, metadata };
}

async function transcribeMusic(audio: Uint8Array): Promise<string | null> {
  const apiKey = providerKey();
  if (!apiKey) return null;
  const form = new FormData();
  form.append("file", new Blob([audio], { type: "audio/mpeg" }), "lesson.mp3");
  form.append("model_id", "scribe_v2");
  form.append("language_code", "fr");
  form.append("timestamps_granularity", "word");
  form.append("tag_audio_events", "false");
  form.append("no_verbatim", "true");

  const response = await providerResponse(
    "/v1/speech-to-text",
    form,
    undefined,
  );
  if (response.status !== 200) return null;
  const data = await response.json().catch(() => ({}));
  return typeof data.text === "string" ? data.text : null;
}

async function music(body: Record<string, unknown>) {
  const lyrics = boundedLyrics(body.lyrics);
  if (!lyrics) {
    return json({ error: "Music needs 1-16 canonical lyric lines under 2,400 characters" }, 400);
  }
  const requestedLength = Number(body.musicLengthMs ?? 30_000);
  if (!Number.isFinite(requestedLength)) return json({ error: "Invalid music length" }, 400);
  const musicLengthMs = Math.min(Math.max(Math.round(requestedLength), 3_000), MAX_MUSIC_LENGTH_MS);
  const styleTags = musicStyleTags(body.style);
  // Give longer canonical lyric sets enough room to be sung clearly. The
  // requested duration remains the floor so callers can still ask for a
  // longer track explicitly.
  const lyricDurationMs = Math.min(
    MAX_MUSIC_LENGTH_MS,
    Math.max(45_000, Math.ceil(lyrics.join(" ").length / 6) * 1_000),
  );
  const sectionDurationMs = Math.max(musicLengthMs, lyricDurationMs);
  const expectedText = lyrics.join(" ");
  let lastValidation: Record<string, unknown> = {
    accepted: false,
    expectedText,
    actualText: "",
    score: 0,
  };

  for (let attempt = 1; attempt <= MUSIC_VALIDATION_ATTEMPTS; attempt += 1) {
    const response = await providerResponse(
      "/v1/music/detailed?output_format=mp3_44100_128",
      JSON.stringify({
        composition_plan: {
          positive_global_styles: attempt === 1
            ? styleTags
            : [
                "warm acoustic pop",
                "French vocals",
                "clear pronunciation",
                "playful melody",
                "polished studio production",
              ],
          negative_global_styles: ["explicit content", "distorted vocals"],
          sections: musicSections(
            lyrics,
            sectionDurationMs,
            attempt === 1
              ? styleTags
              : ["warm acoustic pop", "French vocals", "clear pronunciation"],
          ),
        },
        model_id: "music_v1",
        with_timestamps: true,
        respect_sections_durations: true,
      }),
      "application/json",
    );
    if (response.status !== 200) {
      // bad_composition_plan is recoverable: retry once with the provider's
      // conservative English style vocabulary instead of surfacing a raw
      // provider failure to the learner.
      if (response.status === 422 && attempt < MUSIC_VALIDATION_ATTEMPTS) continue;
      return response;
    }
    const parsed = await parseMultipartMusic(response);
    if (!parsed) return json({ error: "ElevenLabs returned an unreadable music response" }, 502);
    const actualText = await transcribeMusic(parsed.audio);
    const comparison = transcriptValidation(expectedText, actualText ?? "");
    lastValidation = {
      accepted: comparison.accepted,
      expectedText,
      actualText: actualText ?? "",
      score: comparison.score,
      method: "elevenlabs_music_then_scribe_v2",
      attempt,
    };
    if (!comparison.accepted) continue;
    return json({
      mode: "music",
      provider: "elevenlabs",
      model: "music_v1",
      mimeType: "audio/mpeg",
      audioBase64: bytesToBase64(parsed.audio),
      alignment: parsed.metadata.words_timestamps ??
        parsed.metadata.alignment ??
        parsed.metadata.normalized_alignment ??
        null,
      validation: lastValidation,
    });
  }

  return json({
    error: "ElevenLabs music did not preserve the canonical French lyrics after bounded validation attempts",
    code: "audio_validation_failed",
    validation: lastValidation,
  }, 422);
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
