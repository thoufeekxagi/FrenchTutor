export const LIVE_MODEL = "models/gemini-3.5-transcribe-live";
export const LIVE_SESSION_SECONDS = 480;
export const INSTALLATION_QUOTA_SECONDS = 1800;
export const GLOBAL_QUOTA_SECONDS = 3600;

export function validInstallation(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

export async function hashInstallation(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export function buildTokenRequest(now = Date.now()) {
  return {
    uses: 1,
    newSessionExpireTime: new Date(now + 60_000).toISOString(),
    expireTime: new Date(now + LIVE_SESSION_SECONDS * 1000).toISOString(),
    liveConnectConstraints: {
      model: LIVE_MODEL,
      config: {
        responseModalities: ["TEXT"],
        inputAudioTranscription: {
          languageCodes: ["fr-FR"],
          mode: "VERBATIM",
        },
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
