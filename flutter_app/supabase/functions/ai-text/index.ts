import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Gemini fallback for callers that explicitly request Gemini. Course lesson
// authoring uses the same OpenRouter route as Practice; it must not silently
// switch Reading/Listening into a separate Gemini billing path. The current
// 3-series low-cost Gemini text model is 3.1 Flash-Lite. Live audio uses the
// separate 3.1 Flash Live model in the Live services.
const GEMINI_MODEL = "gemini-3.1-flash-lite";
const OPENROUTER_MODEL = "openai/gpt-5.6-luna";
const MAX_MESSAGES = 40;
const MAX_TEXT_LENGTH = 12_000;
// Image/audio inlineData is sent as base64 in the Gemini contents. Keep a
// generous request ceiling while the client still enforces normal per-field
// limits and the function never accepts a provider URL or credential.
const MAX_TOTAL_LENGTH = 8_000_000;

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

function errorMessage(value: unknown): string {
  if (value && typeof value === "object" && "error" in value) {
    const error = (value as { error?: unknown }).error;
    if (error && typeof error === "object" && "message" in error) {
      return String((error as { message?: unknown }).message);
    }
    return String(error);
  }
  return "AI provider request failed";
}

function providerStatus(response: Response): number {
  return response.status === 429 ? 429 : response.status >= 500 ? 502 : 400;
}

function validateContents(contents: unknown): contents is unknown[] {
  if (!Array.isArray(contents) || contents.length === 0 || contents.length > MAX_MESSAGES) {
    return false;
  }
  const serialized = JSON.stringify(contents);
  return serialized.length <= MAX_TOTAL_LENGTH;
}

// The Flutter client uses the camelCase shape used by Google's SDK examples,
// while the REST generateContent endpoint requires snake_case field names.
// Normalize at this server boundary so image understanding cannot fail just
// because the client and REST wire formats use different casing.
function normalizeGeminiContents(contents: unknown[]): unknown[] {
  return contents.map((content) => {
    if (!content || typeof content !== "object") return content;
    const contentRecord = content as Record<string, unknown>;
    if (!Array.isArray(contentRecord.parts)) return content;
    const parts = contentRecord.parts.map((part) => {
      if (!part || typeof part !== "object") return part;
      const partRecord = part as Record<string, unknown>;
      const inline = partRecord.inlineData ?? partRecord.inline_data;
      if (!inline || typeof inline !== "object") return part;
      const inlineRecord = inline as Record<string, unknown>;
      const mimeType = inlineRecord.mimeType ?? inlineRecord.mime_type;
      const data = inlineRecord.data;
      if (typeof mimeType !== "string" || typeof data !== "string") return part;
      const normalizedPart = { ...partRecord };
      delete normalizedPart.inlineData;
      normalizedPart.inline_data = {
        mime_type: mimeType,
        data,
      };
      return normalizedPart;
    });
    return { ...contentRecord, parts };
  });
}

function buildGeminiContents(messages: unknown[]): unknown[] | null {
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
    return null;
  }
  const contents: unknown[] = [];
  for (const message of messages) {
    if (!message || typeof message !== "object") return null;
    const role = String((message as { role?: unknown }).role ?? "");
    const content = String((message as { content?: unknown }).content ?? "");
    if (!content || content.length > MAX_TEXT_LENGTH) return null;
    if (role === "system") continue;
    contents.push({
      role: role === "assistant" ? "model" : "user",
      parts: [{ text: content }],
    });
  }
  return contents.length > 0 ? contents : null;
}

function systemInstruction(messages: unknown[]): unknown | undefined {
  if (!Array.isArray(messages)) return undefined;
  const text = messages
    .filter((message) => message && typeof message === "object" && (message as { role?: unknown }).role === "system")
    .map((message) => String((message as { content?: unknown }).content ?? ""))
    .filter(Boolean)
    .join("\n\n");
  return text ? { parts: [{ text }] } : undefined;
}

function extractGeminiText(data: unknown): string {
  const candidates = data && typeof data === "object" ? (data as { candidates?: unknown }).candidates : null;
  if (!Array.isArray(candidates) || candidates.length === 0) return "";
  const content = candidates[0] && typeof candidates[0] === "object"
    ? (candidates[0] as { content?: unknown }).content
    : null;
  const parts = content && typeof content === "object" ? (content as { parts?: unknown }).parts : null;
  if (!Array.isArray(parts)) return "";
  return parts
    .map((part) => part && typeof part === "object" ? String((part as { text?: unknown }).text ?? "") : "")
    .join("")
    .trim();
}

async function callGemini(
  body: Record<string, unknown>,
  options: { traceFeature?: unknown; retryPolicy?: unknown } = {},
) {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "Gemini is not configured" }, 503);
  const traceFeature = String(options.traceFeature ?? "ai-text").slice(0, 80);
  let lastResponse: Response | null = null;
  // Course passes retryPolicy=none. Practice keeps the existing transient
  // retry behavior, but a Course generation must be exactly one provider
  // attempt so an invalid/failed response cannot silently multiply spend.
  const maxAttempts = options.retryPolicy === "none" ? 1 : 2;
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      },
    );
    if (response.ok) {
      const data = await response.json();
      const text = extractGeminiText(data);
      const usage = data?.usageMetadata ?? null;
      console.info(JSON.stringify({
        event: "ai_provider_call",
        feature: traceFeature,
        provider: "gemini",
        model: GEMINI_MODEL,
        promptTokens: usage?.promptTokenCount ?? null,
        outputTokens: usage?.candidatesTokenCount ?? null,
        totalTokens: usage?.totalTokenCount ?? null,
      }));
      return text
        ? json({
          text,
          provider: "gemini",
          model: GEMINI_MODEL,
          usage: usage ? {
            inputTokens: usage.promptTokenCount ?? 0,
            outputTokens: usage.candidatesTokenCount ?? 0,
            totalTokens: usage.totalTokenCount ?? 0,
          } : null,
        })
        : json({ error: "Gemini returned no text" }, 502);
    }
    lastResponse = response;
    if (response.status < 500 && response.status !== 429) break;
    if (attempt + 1 < maxAttempts) {
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
  }
  const response = lastResponse!;
  const details = await response.json().catch(() => ({}));
  return json({ error: errorMessage(details), retryAfter: response.headers.get("retry-after") }, providerStatus(response));
}

async function callOpenRouter(
  body: Record<string, unknown>,
  options: { traceFeature?: unknown } = {},
) {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) return json({ error: "OpenRouter is not configured" }, 503);
  const traceFeature = String(options.traceFeature ?? "ai-text").slice(0, 80);
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://frenchtutor.app",
      "X-Title": "ParleSprint",
    },
    body: JSON.stringify({
      model: OPENROUTER_MODEL,
      messages: body.messages,
      temperature: body.temperature,
      max_tokens: body.max_tokens,
      reasoning: { effort: "none", exclude: true },
      ...(body.response_format ? { response_format: body.response_format } : {}),
    }),
  });
  if (!response.ok) {
    const details = await response.json().catch(() => ({}));
    return json({ error: errorMessage(details), retryAfter: response.headers.get("retry-after") }, providerStatus(response));
  }
  const data = await response.json();
  const choices = data?.choices;
  const text = Array.isArray(choices) ? String(choices[0]?.message?.content ?? "").trim() : "";
  const usage = data?.usage ?? null;
  console.info(JSON.stringify({
    event: "ai_provider_call",
    feature: traceFeature,
    provider: "openrouter",
    model: OPENROUTER_MODEL,
    promptTokens: usage?.prompt_tokens ?? null,
    outputTokens: usage?.completion_tokens ?? null,
    totalTokens: usage?.total_tokens ?? null,
  }));
  return text
    ? json({
      text,
      provider: "openrouter",
      model: OPENROUTER_MODEL,
      usage: usage ? {
        inputTokens: usage.prompt_tokens ?? 0,
        outputTokens: usage.completion_tokens ?? 0,
        totalTokens: usage.total_tokens ?? 0,
      } : null,
    })
    : json({ error: "OpenRouter returned no text" }, 502);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json({ error: "POST required" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid JSON" }, 400);
  }

  const requestedProvider = String(body.provider ?? "gemini");
  if (requestedProvider !== "gemini" && requestedProvider !== "openrouter") {
    return json({ error: "Unsupported AI provider" }, 400);
  }
  const provider = requestedProvider;
  const messages = body.messages;

  const maxTokens = Math.min(Math.max(Number(body.maxTokens ?? 1024), 32), 4096);
  const temperature = Math.min(Math.max(Number(body.temperature ?? 0.4), 0), 1.5);

  if (provider === "openrouter") {
    if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
      return json({ error: "Invalid messages" }, 400);
    }
    if (JSON.stringify(messages).length > MAX_TOTAL_LENGTH) {
      return json({ error: "Request is too large" }, 413);
    }
    const safeMessages = messages.filter((message) => message && typeof message === "object").map((message) => ({
      role: String((message as { role?: unknown }).role ?? "user"),
      content: String((message as { content?: unknown }).content ?? ""),
    }));
    if (safeMessages.some((message) => !message.content || message.content.length > MAX_TEXT_LENGTH)) {
      return json({ error: "Invalid message content" }, 400);
    }
    const responseFormat = body.responseFormat && typeof body.responseFormat === "object"
      ? body.responseFormat
      : undefined;
    const providerBody = {
      messages: safeMessages,
      temperature,
      max_tokens: maxTokens,
      ...(responseFormat ? { response_format: responseFormat } : {}),
    };
    return await callOpenRouter(providerBody, {
      traceFeature: body.traceFeature,
    });
  }

  const rawContents = body.contents;
  // Gemini supports two valid request shapes: ordinary text calls use
  // `messages`, while audio/image transcription sends raw `contents` with
  // inline_data. Do not require messages for the latter path.
  if (rawContents === undefined &&
      (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES)) {
    return json({ error: "Invalid messages" }, 400);
  }
  const contents = rawContents === undefined ? buildGeminiContents(messages) : rawContents;
  if (!validateContents(contents)) return json({ error: "Invalid Gemini contents" }, 400);
  const generationConfig = { temperature, maxOutputTokens: maxTokens };
  const geminiBody: Record<string, unknown> = {
    contents: normalizeGeminiContents(contents),
    generationConfig,
  };
  const instruction = body.systemInstruction ?? systemInstruction(messages);
  if (instruction !== undefined) geminiBody.systemInstruction = instruction;
  return await callGemini(geminiBody, {
    traceFeature: body.traceFeature,
    retryPolicy: body.retryPolicy,
  });
});
