import { assertEquals, assertMatch, assertNotMatch } from "jsr:@std/assert@1";
import {
  buildTokenRequest,
  hashInstallation,
  LIVE_MODEL,
  LIVE_SESSION_SECONDS,
  tokenValue,
  validInstallation,
} from "./core.ts";

Deno.test("live token is locked to one short French transcription session", () => {
  const now = Date.UTC(2026, 9, 17, 12);
  const request = buildTokenRequest(now);
  assertEquals(request.uses, 1);
  assertEquals(request.liveConnectConstraints.model, LIVE_MODEL);
  assertEquals(
    request.liveConnectConstraints.config.inputAudioTranscription.languageCodes,
    ["fr-FR"],
  );
  assertEquals(
    Date.parse(request.expireTime) - now,
    LIVE_SESSION_SECONDS * 1000,
  );
  assertEquals(Date.parse(request.newSessionExpireTime) - now, 60_000);
});

Deno.test("installation id validation and hashing do not retain raw id", async () => {
  const id = "3f814934-ef71-4e91-bebf-249035bd254a";
  assertEquals(validInstallation(id), true);
  assertEquals(validInstallation("not-a-uuid"), false);
  const hash = await hashInstallation(id);
  assertMatch(hash, /^[0-9a-f]{64}$/);
  assertNotMatch(hash, new RegExp(id));
});

Deno.test("provider token parser accepts Google's token.name", () => {
  assertEquals(tokenValue({ name: "one-use-token" }), "one-use-token");
  assertEquals(tokenValue({ token: "wrong-field" }), undefined);
  assertEquals(tokenValue({ name: "" }), undefined);
});
