import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Enforce the visual-only contract at the provider boundary as well as in
// Flutter prompts. Generated lesson text belongs in the app's UI, never in
// the bitmap returned by this function.
const IMAGE_ONLY_INSTRUCTION = `
FINAL IMAGE-ONLY REQUIREMENT: render only the visual scene. Do not render or
draw any text, words, letters, numbers, punctuation, symbols, signs, labels,
logos, watermarks, captions, titles, UI, borders, frames, or overlays. Leave
all surfaces free of writing. Communicate through people, objects, actions,
lighting, colour, and composition only.
`;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json({ error: "POST required" }, 405);

  let body: { prompt?: unknown };
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid JSON" }, 400);
  }
  const prompt = String(body.prompt ?? "").trim();
  if (!prompt || prompt.length > 12_000) return json({ error: "Invalid prompt" }, 400);
  const imageOnlyPrompt = `${prompt}\n${IMAGE_ONLY_INSTRUCTION}`;

  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) return json({ error: "OpenRouter is not configured" }, 503);

  const response = await fetch("https://openrouter.ai/api/v1/images", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://frenchtutor.app",
      "X-Title": "ParleSprint",
    },
    body: JSON.stringify({
      model: "black-forest-labs/flux.2-klein-4b",
      prompt: imageOnlyPrompt,
      n: 1,
      aspect_ratio: "2:3",
      output_format: "jpeg",
    }),
  });
  if (!response.ok) return json({ error: "Image generation failed" }, response.status === 429 ? 429 : 502);
  const data = await response.json();
  const imageBase64 = String(data?.data?.[0]?.b64_json ?? "");
  return imageBase64 ? json({ imageBase64 }) : json({ error: "Image provider returned no image" }, 502);
});
