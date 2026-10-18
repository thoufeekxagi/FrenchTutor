export const LIVE_MODEL = "models/gemini-3.5-transcribe-live";
export const LIVE_SESSION_SECONDS = 180;

export function buildTokenRequest(now = Date.now()) {
  return {
    uses: 1,
    newSessionExpireTime: new Date(now + 60_000).toISOString(),
    expireTime: new Date(now + LIVE_SESSION_SECONDS * 1000).toISOString(),
    bidiGenerateContentSetup: {
      model: LIVE_MODEL,
      generationConfig: { responseModalities: ["TEXT"] },
      inputAudioTranscription: {
        languageCodes: ["fr-FR"],
        mode: "VERBATIM",
      },
    },
  };
}

export function tokenValue(value: unknown): string | undefined {
  if (!value || typeof value !== "object") return;
  const name = (value as Record<string, unknown>).name;
  return typeof name === "string" && name.length > 0 && name.length <= 4096
    ? name
    : undefined;
}
