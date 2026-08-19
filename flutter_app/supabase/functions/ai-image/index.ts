import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Keep the provider boundary aligned with the shared Flutter artwork contract:
// artwork is image-only and the app renders titles and controls separately.
const BOOK_COVER_INSTRUCTION = `
FINAL ARTWORK REQUIREMENT: create a polished text-free learning scene. Do not
render a title, author name, subtitle, labels, logos, watermark, UI, borders,
frames, captions, or any other words. A single visible character is allowed when
the scene calls for one; keep the face and body inside the central 70% safe area.
`;

const ALLOWED_ASPECT_RATIOS = new Set([
  "1:1",
  "16:9",
  "4:3",
  "3:2",
  "2:3",
  "3:4",
  "9:16",
  "21:9",
]);

function validDimension(value: unknown): value is number {
  return typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 512 &&
    value <= 2048 &&
    value % 8 === 0;
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

// MiniMax has separate Global and Mainland API hosts, and an API key only
// works against the host for the region where it was created. The app uses
// the Global account by default; MINIMAX_API_HOST can override this for a
// Mainland key without putting either the host or the key in the app binary.
const DEFAULT_MINIMAX_API_HOST = "https://api.minimax.io";
const ALLOWED_MINIMAX_API_HOSTS = new Set([
  "https://api.minimax.io",
  "https://api.minimaxi.com",
]);

function minimaxImageEndpoints(): string[] | null {
  const configured = (Deno.env.get("MINIMAX_API_HOST") ?? "").trim();
  const host = (configured || DEFAULT_MINIMAX_API_HOST).replace(/\/+$/, "");
  if (!ALLOWED_MINIMAX_API_HOSTS.has(host)) return null;
  const otherHost = host === "https://api.minimax.io"
    ? "https://api.minimaxi.com"
    : "https://api.minimax.io";
  return [
    `${host}/v1/image_generation`,
    `${otherHost}/v1/image_generation`,
  ];
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json({ error: "POST required" }, 405);

  let body: {
    prompt?: unknown;
    aspectRatio?: unknown;
    width?: unknown;
    height?: unknown;
  };
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid JSON" }, 400);
  }
  const prompt = String(body.prompt ?? "").trim();
  if (!prompt || prompt.length > 1_500) return json({ error: "Invalid prompt" }, 400);
  const aspectRatio = String(body.aspectRatio ?? "4:3");
  if (!ALLOWED_ASPECT_RATIOS.has(aspectRatio)) {
    return json({ error: "Invalid aspect ratio" }, 400);
  }
  const hasWidth = body.width !== undefined || body.height !== undefined;
  if (hasWidth && (!validDimension(body.width) || !validDimension(body.height))) {
    return json({ error: "Invalid image dimensions" }, 400);
  }
  const promptBudget = Math.max(200, 1_500 - BOOK_COVER_INSTRUCTION.length - 1);
  const bookCoverPrompt = `${prompt.slice(0, promptBudget)}\n${BOOK_COVER_INSTRUCTION}`;

  const apiKey = Deno.env.get("MINIMAX_API_KEY");
  if (!apiKey) return json({ error: "MiniMax is not configured" }, 503);
  const endpoints = minimaxImageEndpoints();
  if (!endpoints) return json({ error: "MiniMax host is not configured" }, 503);

  const request: Record<string, unknown> = {
    model: "image-01",
    prompt: bookCoverPrompt,
    n: 1,
    aspect_ratio: aspectRatio,
    response_format: "base64",
    prompt_optimizer: false,
    aigc_watermark: false,
  };
  if (hasWidth) {
    request.width = body.width;
    request.height = body.height;
  }
  const requestBody = JSON.stringify(request);
  let lastStatus = 502;
  for (const endpoint of endpoints) {
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: requestBody,
      });
      lastStatus = response.status;
      const raw = await response.text();
      let data: any = null;
      try {
        data = JSON.parse(raw);
      } catch (_) {
        // Keep the provider's raw response out of logs and out of the client.
      }
      if (response.ok) {
        const encoded = data?.data?.image_base64;
        const imageBase64 = Array.isArray(encoded)
          ? String(encoded[0] ?? "")
          : String(encoded ?? "");
        if (imageBase64) return json({ imageBase64 });
      }
      console.error(
        JSON.stringify({
          provider: "minimax",
          host: new URL(endpoint).host,
          status: response.status,
          code: data?.base_resp?.status_code ?? null,
          message: String(data?.base_resp?.status_msg ?? "").slice(0, 160),
        }),
      );
      // A regional key mismatch is unauthorized on one host. Try the other
      // official host once; never retry a paid generation after a normal API
      // error because that could charge twice.
      if (response.status !== 401 && response.status !== 403) break;
    } catch (_) {
      lastStatus = 502;
      break;
    }
  }
  return json({ error: "Image generation failed" }, lastStatus === 429 ? 429 : 502);
});
