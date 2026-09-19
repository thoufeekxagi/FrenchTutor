import assert from "node:assert/strict";
import test from "node:test";
import { getSafeConfirmationUrl } from "./confirmation-link.ts";

const callback = encodeURIComponent(
  "com.thoufeekx.frenchtutor://auth-callback",
);
const verifyUrl = (query: string) =>
  `${atob("aHR0cHM6Ly9veGZucnNqc2tkamJyb2VreGRjby5zdXBhYmFzZS5jbw==")}/auth/v1/verify?${query}`;

test("reconstructs a Supabase confirmation URL split by email query parsing", () => {
  const link =
    "https://parlesprint.com/confirm-signup?confirmation_url=" +
    encodeURIComponent(verifyUrl("token=secret-token")) +
    `&type=email&redirect_to=${callback}`;

  const result = getSafeConfirmationUrl(link);
  assert.ok(result);
  const parsed = new URL(result);
  assert.equal(parsed.searchParams.get("token"), "secret-token");
  assert.equal(parsed.searchParams.get("type"), "email");
  assert.equal(
    parsed.searchParams.get("redirect_to"),
    "com.thoufeekx.frenchtutor://auth-callback",
  );
});

test("accepts the original complete Supabase confirmation URL", () => {
  const link =
    "https://parlesprint.com/confirm-signup?confirmation_url=" +
    encodeURIComponent(
      verifyUrl(
        "token_hash=secret-hash&type=signup&redirect_to=com.thoufeekx.frenchtutor%3A%2F%2Fauth-callback",
      ),
    );
  assert.ok(getSafeConfirmationUrl(link));
});

test("rejects a foreign verification host, redirect, or duplicated auth value", () => {
  const foreignHost =
    "https://parlesprint.com/confirm-signup?confirmation_url=" +
    encodeURIComponent(
      `https://evil.example/auth/v1/verify?token=secret&type=email&redirect_to=com.thoufeekx.frenchtutor%3A%2F%2Fauth-callback`,
    );
  const foreignRedirect =
    "https://parlesprint.com/confirm-signup?confirmation_url=" +
    encodeURIComponent(
      verifyUrl(
        "token=secret&type=email&redirect_to=https%3A%2F%2Fevil.example%2F",
      ),
    );
  const duplicatedToken =
    "https://parlesprint.com/confirm-signup?confirmation_url=" +
    encodeURIComponent(
      verifyUrl(
        "token=one&type=email&redirect_to=com.thoufeekx.frenchtutor%3A%2F%2Fauth-callback",
      ),
    ) +
    "&token=two";

  assert.equal(getSafeConfirmationUrl(foreignHost), null);
  assert.equal(getSafeConfirmationUrl(foreignRedirect), null);
  assert.equal(getSafeConfirmationUrl(duplicatedToken), null);
});

test("rejects the token handoff on an untrusted page origin", () => {
  const link =
    "https://evil.example/confirm-signup?confirmation_url=" +
    encodeURIComponent(
      verifyUrl(
        "token=secret&type=email&redirect_to=com.thoufeekx.frenchtutor%3A%2F%2Fauth-callback",
      ),
    );
  assert.equal(getSafeConfirmationUrl(link), null);
});
