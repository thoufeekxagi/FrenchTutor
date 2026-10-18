import { describe, expect, it } from "vitest";
import { liveTranscriptionUrl, websocketMessageText } from "./geminiLive";

describe("Gemini constrained live transcription", () => {
  it("uses the constrained endpoint for an ephemeral token", () => {
    const url = new URL(liveTranscriptionUrl("short-lived-test-token"));

    expect(url.protocol).toBe("wss:");
    expect(url.pathname).toContain("BidiGenerateContentConstrained");
    expect(url.searchParams.get("access_token")).toBe("short-lived-test-token");
  });

  it("decodes Gemini's binary WebSocket server messages", async () => {
    const json = JSON.stringify({ setupComplete: {} });
    const bytes = new TextEncoder().encode(json);
    await expect(websocketMessageText(json)).resolves.toBe(json);
    await expect(websocketMessageText(new Blob([bytes]))).resolves.toBe(json);
    await expect(websocketMessageText(bytes.buffer)).resolves.toBe(json);
    await expect(websocketMessageText(bytes)).resolves.toBe(json);
  });
});
