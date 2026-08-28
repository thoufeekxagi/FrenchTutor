import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Keep the provider boundary aligned with the shared Flutter artwork contract:
// artwork is image-only and the app renders titles and controls separately.
const BOOK_COVER_INSTRUCTION = `
FINAL ARTWORK REQUIREMENT: create one simple, ordinary, text-free illustration
based only on the visual anchor. Show one setting or one/two concrete objects.
No poster, generic hero, unrelated landmark, or invented character. Never render
text, letters, words, numbers, symbols, Chinese characters, signs, labels, logos,
captions, watermarks, UI, borders, or frames. Keep the subject near the center.
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
// the Global endpoint by default, matching the provider's global docs.
// MINIMAX_API_HOST can override this for a Mainland key without putting either
// the host or the key in the app binary.
const DEFAULT_MINIMAX_API_HOST = "https://api.minimax.io";
const ALLOWED_MINIMAX_API_HOSTS = new Set([
  "https://api.minimax.io",
  "https://api.minimaxi.com",
]);

function normalizeMinimaxHost(value: string): string | null {
  const candidate = value.trim().replace(/\/+$/, "");
  if (ALLOWED_MINIMAX_API_HOSTS.has(candidate)) return candidate;
  try {
    const url = new URL(candidate);
    const host = `${url.protocol}//${url.host}`;
    const path = url.pathname.replace(/\/+$/, "");
    if (ALLOWED_MINIMAX_API_HOSTS.has(host) && (path === "" || path === "/v1")) {
      return host;
    }
  } catch (_) {
    // Treat malformed configuration as disabled rather than making a request
    // to an unexpected host.
  }
  return null;
}

function firstString(value: unknown): string | null {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = firstString(item);
      if (found) return found;
    }
  }
  return null;
}

function bytesToBase64(bytes: Uint8Array): string {
  let result = "";
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    result += btoa(
      String.fromCharCode(...bytes.subarray(offset, offset + chunkSize)),
    );
  }
  return result;
}

async function readImagePayload(data: any): Promise<string | null> {
  const encoded = firstString(
    data?.data?.image_base64 ?? data?.image_base64,
  );
  if (encoded) return encoded;

  // MiniMax documents URL responses as another valid response format. Keep
  // the Edge Function's client contract as base64 by downloading that one
  // provider URL before returning it to Flutter.
  const imageUrl = firstString(data?.data?.image_urls ?? data?.image_urls);
  if (!imageUrl || !/^https?:\/\//i.test(imageUrl)) return null;
  const imageResponse = await fetch(imageUrl);
  if (!imageResponse.ok) return null;
  return bytesToBase64(new Uint8Array(await imageResponse.arrayBuffer()));
}

function minimaxImageEndpoints(): string[] | null {
  const configured = (Deno.env.get("MINIMAX_API_HOST") ?? "").trim();
  const host = normalizeMinimaxHost(configured || DEFAULT_MINIMAX_API_HOST);
  if (!host) return null;
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

  const apiKey = Deno.env.get("MINIMAX_API_KEY")?.trim();
  if (!apiKey) return json({ error: "MiniMax is not configured" }, 503);
  const endpoints = minimaxImageEndpoints();
  if (!endpoints) return json({ error: "MiniMax host is not configured" }, 503);

  // MiniMax selects the generated canvas from aspect_ratio. Keep this payload
  // to the documented fields; local storage optimization owns the final
  // display dimensions and byte limit.
  const providerRequest: Record<string, unknown> = {
    model: "image-01",
    prompt: bookCoverPrompt,
    aspect_ratio: aspectRatio,
    response_format: "base64",
  };
  const requestBody = JSON.stringify(providerRequest);
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
        const imageBase64 = await readImagePayload(data);
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
      // A regional key mismatch or endpoint mismatch can be retried once on
      // the other official host. A successful response without an image is a
      // provider response, not a reason to issue a second paid generation.
      if (response.status === 429) break;
      if (response.ok) break;
      if (
        response.status !== 401 &&
        response.status !== 403 &&
        response.status !== 404 &&
        !response.ok
      ) break;
    } catch (_) {
      lastStatus = 502;
      break;
    }
  }
  return json({ error: "Image generation failed" }, lastStatus === 429 ? 429 : 502);
});
