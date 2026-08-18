import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const GEMINI_MODEL = "gemini-3.1-flash-lite";
const OPENROUTER_MODEL = "nvidia/nemotron-3-super-120b-a12b:free";
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

async function callGemini(body: Record<string, unknown>) {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "Gemini is not configured" }, 503);
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  if (!response.ok) {
    const details = await response.json().catch(() => ({}));
    return json({ error: errorMessage(details), retryAfter: response.headers.get("retry-after") }, providerStatus(response));
  }
  const data = await response.json();
  const text = extractGeminiText(data);
  return text ? json({ text, provider: "gemini", model: GEMINI_MODEL }) : json({ error: "Gemini returned no text" }, 502);
}

async function callOpenRouter(body: Record<string, unknown>) {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) return json({ error: "OpenRouter is not configured" }, 503);
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
    }),
  });
  if (!response.ok) {
    const details = await response.json().catch(() => ({}));
    return json({ error: errorMessage(details), retryAfter: response.headers.get("retry-after") }, providerStatus(response));
  }
  const data = await response.json();
  const choices = data?.choices;
  const text = Array.isArray(choices) ? String(choices[0]?.message?.content ?? "").trim() : "";
  return text ? json({ text, provider: "openrouter", model: OPENROUTER_MODEL }) : json({ error: "OpenRouter returned no text" }, 502);
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

  const provider = body.provider === "openrouter" ? "openrouter" : "gemini";
  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
    return json({ error: "Invalid messages" }, 400);
  }
  if (JSON.stringify(messages).length > MAX_TOTAL_LENGTH) return json({ error: "Request is too large" }, 413);

  const maxTokens = Math.min(Math.max(Number(body.maxTokens ?? 1024), 32), 4096);
  const temperature = Math.min(Math.max(Number(body.temperature ?? 0.4), 0), 1.5);

  if (provider === "openrouter") {
    const safeMessages = messages.filter((message) => message && typeof message === "object").map((message) => ({
      role: String((message as { role?: unknown }).role ?? "user"),
      content: String((message as { content?: unknown }).content ?? ""),
    }));
    if (safeMessages.some((message) => !message.content || message.content.length > MAX_TEXT_LENGTH)) {
      return json({ error: "Invalid message content" }, 400);
    }
    return await callOpenRouter({ messages: safeMessages, temperature, max_tokens: maxTokens });
  }

  const rawContents = body.contents;
  const contents = rawContents === undefined ? buildGeminiContents(messages) : rawContents;
  if (!validateContents(contents)) return json({ error: "Invalid Gemini contents" }, 400);
  const generationConfig = { temperature, maxOutputTokens: maxTokens };
  const geminiBody: Record<string, unknown> = { contents, generationConfig };
  const instruction = body.systemInstruction ?? systemInstruction(messages);
  if (instruction !== undefined) geminiBody.systemInstruction = instruction;
  return await callGemini(geminiBody);
});
