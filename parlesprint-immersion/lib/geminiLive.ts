const LIVE_WEBSOCKET =
  "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained";

export function liveTranscriptionUrl(token: string): string {
  const url = new URL(LIVE_WEBSOCKET);
  url.searchParams.set("access_token", token);
  return url.href;
}

/** Gemini sends Live API server messages in binary WebSocket frames. */
export async function websocketMessageText(data: unknown): Promise<string> {
  if (typeof data === "string") return data;
  if (typeof Blob !== "undefined" && data instanceof Blob) return data.text();
  if (data instanceof ArrayBuffer) return new TextDecoder().decode(data);
  if (ArrayBuffer.isView(data)) {
    return new TextDecoder().decode(
      new Uint8Array(data.buffer, data.byteOffset, data.byteLength),
    );
  }
  throw new TypeError("Unsupported Gemini WebSocket message frame.");
}
