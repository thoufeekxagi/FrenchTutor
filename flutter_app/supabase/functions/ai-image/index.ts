import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Keep the provider boundary aligned with the shared Flutter artwork contract:
// one exact title is allowed, while everything else that looks like UI or
// marketing copy is forbidden.
const BOOK_COVER_INSTRUCTION = `
FINAL BOOK-COVER REQUIREMENT: create a polished portrait literary cover. Render
only the exact supplied title as clean, readable typography. Do not add an
author name, subtitle, labels, logos, watermark, UI, borders, frames, captions,
or any other words. Do not show people, faces, animals, mascots, or named
characters; if the prompt mentions one, make the setting, objects, architecture,
weather, or action the primary subject instead. Keep the title inside safe
margins and make it legible.
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
  if (!prompt || prompt.length > 1_500) return json({ error: "Invalid prompt" }, 400);
  const promptBudget = Math.max(200, 1_500 - BOOK_COVER_INSTRUCTION.length - 1);
  const bookCoverPrompt = `${prompt.slice(0, promptBudget)}\n${BOOK_COVER_INSTRUCTION}`;

  const apiKey = Deno.env.get("MINIMAX_API_KEY");
  if (!apiKey) return json({ error: "MiniMax is not configured" }, 503);

  const requestBody = JSON.stringify({
    model: "image-01",
    prompt: bookCoverPrompt,
    n: 1,
    aspect_ratio: "2:3",
    response_format: "base64",
    prompt_optimizer: false,
    aigc_watermark: false,
  });
  try {
    const response = await fetch("https://api.minimaxi.com/v1/image_generation", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: requestBody,
    });
    if (response.ok) {
      const data = await response.json();
      const encoded = data?.data?.image_base64;
      const imageBase64 = Array.isArray(encoded)
        ? String(encoded[0] ?? "")
        : String(encoded ?? "");
      if (imageBase64) return json({ imageBase64 });
    }
    return json(
      { error: "Image generation failed" },
      response.status === 429 ? 429 : 502,
    );
  } catch (_) {
    return json({ error: "Image generation failed" }, 502);
  }
});
