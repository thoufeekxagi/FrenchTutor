import { assertEquals } from "jsr:@std/assert@1";
import { buildTokenRequest, LIVE_MODEL, LIVE_SESSION_SECONDS, tokenValue } from "./core.ts";
import { clientIp, hmacHex, INSTALLATION_ID } from "../_shared/usage.ts";

Deno.test("live token is locked to one short French transcription session", () => {
  const now = Date.UTC(2026, 9, 17, 12);
  const request = buildTokenRequest(now);
  assertEquals(request.uses, 1);
  assertEquals(request.bidiGenerateContentSetup.model, LIVE_MODEL);
  assertEquals(request.bidiGenerateContentSetup.inputAudioTranscription.languageCodes, ["fr-FR"]);
  assertEquals(Date.parse(request.expireTime) - now, LIVE_SESSION_SECONDS * 1000);
  assertEquals(Date.parse(request.newSessionExpireTime) - now, 60_000);
});

Deno.test("provider token parser accepts Google's token.name", () => {
  assertEquals(tokenValue({ name: "one-use-token" }), "one-use-token");
  assertEquals(tokenValue({ token: "wrong-field" }), undefined);
  assertEquals(tokenValue({ name: "" }), undefined);
});

Deno.test("installation ids are validated and hashed without retaining the raw value", async () => {
  assertEquals(INSTALLATION_ID.test("3f814934-ef71-4e91-bebf-249035bd254a"), true);
  assertEquals(INSTALLATION_ID.test("not-a-uuid"), false);
  const hash = await hmacHex("salt", "install:3f814934");
  assertEquals(/^[0-9a-f]{64}$/.test(hash), true);
  assertEquals(hash, await hmacHex("salt", "install:3f814934"));
  assertEquals(hash === (await hmacHex("other", "install:3f814934")), false);
});

Deno.test("client IP prefers the validated Cloudflare header and ignores caller-supplied forwarded entries", () => {
  const request = (headers: Record<string, string>) => new Request("https://x.invalid", { headers });
  assertEquals(clientIp(request({ "cf-connecting-ip": "203.0.113.9", "x-forwarded-for": "1.1.1.1, 2.2.2.2" })), "203.0.113.9");
  assertEquals(clientIp(request({ "x-forwarded-for": "6.6.6.6, 203.0.113.9" })), "203.0.113.9");
  assertEquals(clientIp(request({})), "unknown");
});
