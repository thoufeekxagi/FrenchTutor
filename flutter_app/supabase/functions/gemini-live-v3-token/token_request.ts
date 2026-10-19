export const GEMINI_AUTH_TOKEN_URL =
  "https://generativelanguage.googleapis.com/v1beta/auth_tokens";

export function buildAuthTokenRequest(apiKey: string, now: number): RequestInit {
  return {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify({
      uses: 1,
      expireTime: new Date(now + 30 * 60 * 1000).toISOString(),
      newSessionExpireTime: new Date(now + 60 * 1000).toISOString(),
      // This project's v1beta token endpoint accepts the Live setup field.
      // A field mask locks only the model, leaving the app's full audio setup
      // to be supplied when it opens the socket.
      fieldMask: "model",
      bidiGenerateContentSetup: {
        model: "models/gemini-3.8-live",
      },
    }),
  };
}
