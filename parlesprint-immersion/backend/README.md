# Immersion explanation backend

This folder moves with the extension; it has no dependency on the Flutter app.
The deployed endpoint is:
`https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-explain`

The live audio token endpoint is:
`https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-live-token`

## Protocol

POST JSON `{ "text": "bonjour", "sentence": "Bonjour Marie.", "level": "A1" }`
with `Authorization: Bearer <Supabase user access token>`, `apikey: <public anon key>`,
and `Content-Type: application/json`.
Returns `{ meaning, grammar, example, exampleTranslation }` as strings.

Send `"mode":"translation"` to get the sentence-only response
`{ "translation": "Hello Marie." }`. This uses Gemini Flash-Lite with a
short one-field response. Explanation and translation results are cached
separately by input.

Only explicit learner requests call Gemini. Identical input, CEFR level, mode,
model, and prompt version share a server cache. This endpoint has no
application-level daily explanation or translation cap; Google and Supabase
may still return ordinary provider rate limits.

The existing project has anonymous sign-in **disabled**. Use the existing
ParleSprint email/password account. Anonymous auth is supported if an operator
chooses to enable it later; this project configuration was not changed.
A public anon key alone is never authorization for AI generation.
Email/password sign-in is verified. Email OTP verification requires the hosted
project email template to include `{{ .Token }}`; the default magic-link template
may provide only a link. No authentication email or template change was made.

## Security and privacy

- Gemini and service-role secrets stay in Edge Function environment secrets.
- Frontend `.env.local` has only the public project URL and anon key.
- JWT verification is on; the handler additionally calls Auth `getUser`.
- The cache table enables RLS and grants access only to `service_role`.
- Word/phrase explanations are limited to 240 selected characters. Sentence
  translations accept up to 1,600 characters; subtitle context is capped at
  1,600 characters and the request body at 8,192 bytes. Model output is
  schema-validated and bounded.
- No video URLs, browsing history, account email, or subtitle text is logged.
- Explicitly requested selected text and sentence context go to Google Gemini.
  The database stores a hash of the input and its generated result. Account linking does not sync
  local vocabulary in version 0.1.
- Live transcription uses a separate, explicit consent. Chrome captures only the
  active tab's audio after a popup action; audio is streamed directly from the
  extension to Google Gemini Live and never passes through this backend. The
  token endpoint receives a random installation ID and consent flag, stores
  only a SHA-256 installation hash and reserved duration, then mints a one-use
  token constrained to French Live transcription. The `GEMINI_API_KEY` remains
  only in Edge Function secrets. Audio/transcript text is not written to server
  logs or database by this endpoint.
- The stable extension origin
  `chrome-extension://ijclgmkoljddlalgcnpodeemcmcipolb` is allowlisted in source.
  Additional origins can be allowed by comma-separated `IMMERSION_ALLOWED_ORIGINS`
  (for example `chrome-extension://<published-id>`). Requests without an Origin
  header are accepted because Chrome background network requests can omit it;
  they still require a valid user token. CORS is not an authorization mechanism.

## Reproduce / deploy

1. Read `supabase --help` and the subcommand help for your installed CLI.
2. In a fresh target project, execute the SQL in `supabase/migrations/` using
   Supabase SQL editor or your authenticated database tooling. These objects
   were already installed in the ParleSprint project on October 17, 2026.
   Do not replay the CREATE TABLE statements against that project.
3. Set `GEMINI_API_KEY` in Supabase secrets, never in a WXT public variable.
   The bundled stable extension ID is already allowed; set
   `IMMERSION_ALLOWED_ORIGINS` only for additional approved IDs.
   The existing project already had a working Gemini secret; it was reused
   without changing its value.
4. Optional secret `IMMERSION_GEMINI_MODEL` defaults to
   `gemini-3.1-flash-lite` for A1/A2 and sentence translation. B1/B2 use
   `IMMERSION_GEMINI_CAREFUL_MODEL`, default `gemini-3-flash-preview`, for more
   complex grammar and idioms. Both are verified against the real API. The
   careful route uses minimal thinking and a 1,200-token output cap; the Lite
   explanation route uses 600 tokens and translation uses 256. Cache version 4
   separates translation responses from explanations.
5. From this directory run
   `supabase functions deploy immersion-explain --project-ref <ref>`.
   Keep JWT verification enabled. Do not deploy other project functions.
6. Put only URL and public anon key in extension `.env.local`, then rebuild.

## Live audio transcription

The token endpoint is intentionally public (`verify_jwt = false`) because a
Chrome extension has no ParleSprint account requirement for live captions. It
still requires the extension's public Supabase key, exact extension Origin,
explicit consent, a valid random installation UUID, and an atomic database
quota reservation. It cannot return an arbitrary model or configuration. One
token authorizes one French transcription session for up to eight minutes. It
reserves eight minutes from a 30-minute per-installation and 60-minute global
UTC daily limit; unused session time is not refunded. Google Live supplies
interim and final utterance text, not word-level timestamps.

Before deploying the endpoint, apply the new migration
`20261017220457_immersion_live_transcription_quota.sql`, then deploy only:

```sh
supabase functions deploy immersion-live-token --project-ref oxfnrsjskdjbroekxdco
```

The existing server-side `GEMINI_API_KEY` is reused; do not copy it to the
extension, local frontend environment, or another service. The Edge Function
creates a token at Google's `auth_tokens` API with fixed model/config limits.
Google's unpaid API tier may use submitted audio to improve its products and may
include human review. Keep that disclosure visible before Start.

## Verification

`deno check supabase/functions/immersion-explain/index.ts`

`deno test --allow-env supabase/functions/immersion-explain/`

The initial deployment was checked with a temporary confirmed user: sign-in 200,
a real French explanation 200, and temporary-user deletion 200. Version 2 also
verified cached and uncached requests with the explicit stable extension Origin:
both returned 200 and the matching Access-Control-Allow-Origin header. The
translation route is covered by mocked provider tests. Security advisors reported informational
RLS-without-policies notices for the deliberately service-only extension tables.
Existing unrelated project advisories were left unchanged.

Errors are intentionally non-sensitive: 400 `invalid_input`, 401
`sign_in_required`, 403 `origin_not_allowed`, 413 `input_too_large`, 502
`ai_unavailable` / `invalid_ai_response`, or 503 configuration/storage/
temporary failure. There is no application-level daily quota on explanations
or translations; the live-audio token endpoint retains its separate
installation/global transcription caps. The extension retains local learning
features and shows a retryable AI error.

## Portable live browser QA

Run `node tests/live-ai.mjs` from the extension root after building. Supply
`IMMERSION_QA_SERVICE_KEY` (or `SUPABASE_SERVICE_ROLE_KEY`) through your shell
environment or ignored `.env.qa.local`. The public URL and anon key can come
from `.env.local`. Shell environment takes precedence. The test creates and
deletes one temporary confirmed account and checks real popup password sign-in,
AI generation, local/offline cache, and sign-out. The test is a Node-only script
outside all extension entrypoints. Never use a `WXT_PUBLIC_` variable for a
service key or copy QA secrets into the extension bundle. No parent folder
configuration is required.

## Public privacy policy

`https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-privacy`
serves the bundled privacy policy as readable UTF-8 text over HTTPS. It is a
separate static Edge Function accepting only GET/HEAD, without JWT verification.
It has no database access or AI calls. To update it, synchronize its static
policy literal with `public/privacy.html`, then deploy only `immersion-privacy`
using its `verify_jwt = false` configuration. The public policy support contact
is `thoufeek@agiventures.ca`.

## Submission-readiness reliability audit

The Edge handler now gives the complete upstream request path a 22-second
deadline (inside the extension's 25-second timeout). A cache write has at most
1.5 seconds and cannot turn an already-generated explanation into an error if
the cache service times out or loses network connectivity. Auth outages and
rate limits return retryable 503 `authentication_unavailable`; invalid tokens
remain 401. No provider retries are automatic. Cache hits avoid repeat model
calls; uncached calls can still be subject to Google or Supabase rate limits.

Ten Deno tests cover input bounds and the real handler with mocked upstream
responses: long subtitle translation is accepted, cache-network failure
preserves HTTP 200, Auth outage is 503, invalid auth stops before generation,
translation makes no quota RPC, and model timeout/rate-limit responses stay
bounded, sanitized, and do not trigger retries. No real
secrets or paid requests are used by these tests. The test-only standard-library
assert dependency is version pinned and does not enter the deployed function.
A rolled-back remote SQL test verified the live-transcription global
499→500 boundary and rejection at 500. Table/RPC permission checks confirmed no
anon/authenticated quota mutation/cache access; the live-transcription quota
function remains SECURITY INVOKER.

## Private store-review credentials

The dedicated Chrome Web Store reviewer account is retained for private review
instructions. Its credentials live only in extension-root `.env.review.local`
(owner read/write, mode 0600), which is ignored by `.env*` and must never enter
a source archive, production bundle, screenshot, or public documentation. Reuse
that account rather than creating duplicates. The operator can copy its email
and password into the store's private reviewer-access field. Local practice
requires no login; the reviewer account enables optional AI under the same
20-per-user/day and 500-global/day generation limits. Password sign-in and a
cached explanation were verified, then the test session was signed out. No
email was sent, existing users were not changed, and the account was retained.

## Same-account Google / Apple connection

The extension uses the same Supabase project as the native ParleSprint app.
Email/password sign-in therefore authenticates existing app user IDs. OAuth
connects through that project's providers; it does not create a separate
extension account database or sync vocabulary automatically.

The background accepts popup-only `{type: "oauth", provider: "google" | "apple"}`,
uses Chrome `identity.launchWebAuthFlow`, and exchanges a one-use Supabase code
with SHA-256 PKCE. A cryptographically random state must match the exact expected
HTTPS callback origin/path. Fragments, duplicate codes, foreign parameters,
expired flows, concurrent windows, and callbacks after sign-out are rejected.
The verifier remains in background memory and is never exposed to a page or
provider URL. Closing/cancelling the provider window returns a friendly error.
A worker restart safely loses the pending flow, requiring a new sign-in.

`{type: "auth-capabilities"}` reports effective `google` / `apple` booleans and
configuration reasons. `{type: "auth-status"}` returns `linked` plus safe account
`id`, `email`, `displayName`, and `provider` to the exact extension popup. It never
returns access/refresh tokens. Display metadata is not used for authorization
and is never part of AI explanation input.

Current observed readiness on October 17, 2026:

- Public Auth settings enable both Google and Apple.
- Google `/authorize` returns 302 to `accounts.google.com`, but our probe's
  server-side flow referrer fell back to `https://parlesprint.com`. The extension
  callback was not on the redirect allowlist at inspection time.
- Apple browser `/authorize` returns 400: missing OAuth secret. Native Apple
  ID-token sign-in can work without a configured browser OAuth secret; the
  native provider setting alone does not establish extension readiness.
- No real Google/Apple user consent or end-to-end provider sign-in was claimed.
  Password authentication was independently verified with a real session.

The operator must preserve all existing Supabase redirect URLs and add only
`https://ijclgmkoljddlalgcnpodeemcmcipolb.chromiumapp.org/oauth?state=*` (or the
exact same callback path with supported query matching), then verify a new probe
stores the chromiumapp referrer rather than silently falling back to Site URL.
Only after this check, set public build flag
`WXT_PUBLIC_GOOGLE_OAUTH_ENABLED=true` and rebuild. For Apple, configure its
server-side web OAuth secret first, verify provider handoff/callback readiness,
then set `WXT_PUBLIC_APPLE_OAUTH_ENABLED=true`. These are public readiness flags,
not secrets. A new provider-enabled build must explicitly add Chrome `identity`
permission; shipped version 0.1 omits that unused permission and hides disabled
provider controls. Defaults keep incomplete provider integrations disabled. Never put
provider secrets or private Apple keys in the extension.

The current publisher dashboard session could not access the French project, so
no redirect allowlist or provider secrets were changed. Both public readiness
flags remain off. The bundled/public policy and store disclosure worksheet
explicitly describe the absence of `identity` permission in shipped 0.1, local account display fields,
working email/password connection, and disabled provider paths. Store permission
declarations must match the submitted build; do not mark provider sign-in as
verified based only on the mocked tests or initial Google handoff.
