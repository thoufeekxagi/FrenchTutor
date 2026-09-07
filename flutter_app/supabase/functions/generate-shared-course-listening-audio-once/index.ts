import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// One-time script: renders Unit 2's fixed Listening narration exactly once
// through the same Gemini TTS call prepare-course-lesson/index.ts uses for
// personalized listening lessons, then uploads it to a single shared,
// publicly-readable storage object. Every learner's Unit 2 Listening row
// can point at this same object from now on instead of triggering its own
// redundant render. Re-run this (it's idempotent, upsert: true) whenever
// _unitTwoListeningSegments in lib/data/database/adaptive_course_store.dart
// changes.
const NARRATION =
  "Le soir, le marché est calme. Une dernière cliente achète encore des pommes. La vendeuse compte le prix de chaque fruit. Elle range les pommes fraîches. Demain, un nouveau marché ouvre tôt.";
const SHARED_PATH = "course-shared/unit-two-listening.wav";

function pcm16ToWav(pcm: Uint8Array, sampleRate = 24000): Uint8Array {
  const channels = 1;
  const bitsPerSample = 16;
  const headerSize = 44;
  const wav = new Uint8Array(headerSize + pcm.length);
  const view = new DataView(wav.buffer);
  const ascii = (offset: number, value: string) => {
    for (let index = 0; index < value.length; index += 1) {
      wav[offset + index] = value.charCodeAt(index);
    }
  };
  ascii(0, "RIFF");
  view.setUint32(4, 36 + pcm.length, true);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * channels * bitsPerSample / 8, true);
  view.setUint16(32, channels * bitsPerSample / 8, true);
  view.setUint16(34, bitsPerSample, true);
  ascii(36, "data");
  view.setUint32(40, pcm.length, true);
  wav.set(pcm, headerSize);
  return wav;
}

function isValidPcmWav(bytes: Uint8Array): boolean {
  if (bytes.length <= 44) return false;
  const ascii = (start: number, end: number) =>
    String.fromCharCode(...bytes.slice(start, end));
  if (ascii(0, 4) !== "RIFF" || ascii(8, 12) !== "WAVE") return false;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const declaredDataBytes = view.getUint32(40, true);
  return declaredDataBytes > 0 &&
    declaredDataBytes % 2 === 0 &&
    declaredDataBytes <= bytes.length - 44;
}

Deno.serve(async (_request: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!openRouterKey) {
    return new Response(JSON.stringify({ error: "OPENROUTER_API_KEY is not configured" }), { status: 500 });
  }
  const admin = createClient(supabaseUrl, serviceRoleKey);

  const audioResponse = await fetch("https://openrouter.ai/api/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openRouterKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://parlesprint.com",
      "X-Title": "ParleSprint course listening (shared Unit 2 asset)",
    },
    body: JSON.stringify({
      model: "google/gemini-3.1-flash-tts-preview",
      input: NARRATION,
      voice: "Aoede",
      response_format: "pcm",
    }),
  });
  if (!audioResponse.ok) {
    const errorBody = await audioResponse.text();
    return new Response(JSON.stringify({ error: `TTS failed (${audioResponse.status}): ${errorBody.slice(0, 300)}` }), { status: 502 });
  }
  const pcm = new Uint8Array(await audioResponse.arrayBuffer());
  if (pcm.length === 0 || pcm.length % 2 !== 0) {
    return new Response(JSON.stringify({ error: "TTS returned invalid PCM" }), { status: 502 });
  }
  const bytes = pcm16ToWav(pcm);

  const { error: uploadError } = await admin.storage.from("listening-audio").upload(
    SHARED_PATH,
    bytes,
    { contentType: "audio/wav", upsert: true },
  );
  if (uploadError) {
    return new Response(JSON.stringify({ error: `Upload failed: ${uploadError.message}` }), { status: 500 });
  }

  const { data: stored, error: verifyError } = await admin.storage.from("listening-audio").download(SHARED_PATH);
  if (verifyError || !stored) {
    return new Response(JSON.stringify({ error: `Verify failed: ${verifyError?.message ?? "missing object"}` }), { status: 500 });
  }
  const storedBytes = new Uint8Array(await stored.arrayBuffer());
  if (!isValidPcmWav(storedBytes)) {
    return new Response(JSON.stringify({ error: "Uploaded object failed WAV validation" }), { status: 500 });
  }

  return new Response(JSON.stringify({
    ok: true,
    path: SHARED_PATH,
    bytes: storedBytes.length,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
