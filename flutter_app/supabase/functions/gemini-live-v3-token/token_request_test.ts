import {
  buildAuthTokenRequest,
  GEMINI_AUTH_TOKEN_URL,
} from "./token_request.ts";

Deno.test("v3 token is restricted to Gemini 3.8 Live on v1beta", () => {
  const now = Date.UTC(2026, 9, 15, 12);
  const request = buildAuthTokenRequest("test-key", now);
  const body = JSON.parse(request.body as string);
  if (!GEMINI_AUTH_TOKEN_URL.endsWith("/v1beta/auth_tokens")) {
    throw new Error("wrong token API version");
  }
  if (body.liveConnectConstraints.model !== "models/gemini-3.8-live") {
    throw new Error("wrong model constraint");
  }
  if (body.uses !== 1) throw new Error("token must be single-use");
  if (Date.parse(body.newSessionExpireTime) - now !== 60_000) {
    throw new Error("new-session window changed");
  }
  if (Date.parse(body.expireTime) - now !== 1_800_000) {
    throw new Error("session lifetime changed");
  }
});
