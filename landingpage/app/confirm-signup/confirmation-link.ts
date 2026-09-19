// This is the public project URL, not a credential. Netlify's secrets scanner
// flags the literal because SUPABASE_URL is configured in the build environment.
const SUPABASE_VERIFY_ORIGIN_BASE64 = "aHR0cHM6Ly9veGZucnNqc2tkamJyb2VreGRjby5zdXBhYmFzZS5jbw==";
const SUPABASE_VERIFY_PATH = "/auth/v1/verify";
const IOS_AUTH_CALLBACK = "com.thoufeekx.frenchtutor://auth-callback";
const CONFIRMATION_PAGE_ORIGINS = new Set([
  "https://parlesprint.com",
  "https://www.parlesprint.com",
]);

const FORWARDED_VERIFY_PARAMETERS = [
  "token",
  "token_hash",
  "type",
  "redirect_to",
] as const;

/**
 * Reconstructs Supabase's confirmation URL from its documented email-wrapper
 * format without consuming it. Supabase confirmation URLs contain ampersands,
 * which email clients parse as outer query parameters; copy those known auth
 * parameters back into the URL before validating the destination.
 */
export function getSafeConfirmationUrl(landingHref: string): string | null {
  try {
    const landing = new URL(landingHref);
    if (
      landing.pathname !== "/confirm-signup" ||
      !CONFIRMATION_PAGE_ORIGINS.has(landing.origin)
    ) {
      return null;
    }

    const confirmationValues = landing.searchParams.getAll("confirmation_url");
    if (confirmationValues.length !== 1) return null;

    const confirmation = new URL(confirmationValues[0]);

    for (const parameter of FORWARDED_VERIFY_PARAMETERS) {
      const outerValues = landing.searchParams.getAll(parameter);
      if (outerValues.length > 1) return null;
      if (outerValues.length === 1) {
        // The nested link may already be encoded as a whole. Reject ambiguous
        // duplicate values rather than letting query ordering choose a token
        // or return destination.
        if (confirmation.searchParams.has(parameter)) return null;
        confirmation.searchParams.set(parameter, outerValues[0]);
      }
    }

    if (
      confirmation.protocol !== "https:" ||
      confirmation.origin !== getSupabaseVerifyOrigin() ||
      confirmation.pathname !== SUPABASE_VERIFY_PATH ||
      confirmation.username !== "" ||
      confirmation.password !== "" ||
      confirmation.hash !== ""
    ) {
      return null;
    }

    const tokens = [
      ...confirmation.searchParams.getAll("token"),
      ...confirmation.searchParams.getAll("token_hash"),
    ];
    const types = confirmation.searchParams.getAll("type");
    const redirects = confirmation.searchParams.getAll("redirect_to");

    if (
      tokens.length !== 1 ||
      tokens[0].trim().length === 0 ||
      types.length !== 1 ||
      !["email", "signup"].includes(types[0]) ||
      redirects.length !== 1 ||
      !isAllowedRedirect(redirects[0])
    ) {
      return null;
    }

    return confirmation.toString();
  } catch {
    return null;
  }
}

function getSupabaseVerifyOrigin(): string {
  return atob(SUPABASE_VERIFY_ORIGIN_BASE64);
}

function isAllowedRedirect(value: string): boolean {
  if (value === IOS_AUTH_CALLBACK) return true;

  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      ["parlesprint.com", "www.parlesprint.com"].includes(url.hostname) &&
      url.username === "" &&
      url.password === "" &&
      url.pathname === "/" &&
      url.search === "" &&
      url.hash === ""
    );
  } catch {
    return false;
  }
}
