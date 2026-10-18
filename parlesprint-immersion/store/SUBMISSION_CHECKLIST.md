# Submission checklist

Target: October 18, 2026. A build or ZIP is not a submission, and submission is not approval. The publisher must complete account verification and submit through the Chrome Web Store Developer Dashboard.

## Build and product evidence

- [x] Run `npm ci`, `npm run typecheck`, `npm test`, `npm run build`, and `npm run zip` from this portable folder.
- [x] Automated Chromium QA recorded in `VERIFICATION.md`: all 15 extension browser flows pass; real YouTube placement/import/replay/fullscreen pass.
- [ ] Complete the manual live-audio smoke test in `QA.md`: start from Chrome's real toolbar popup, confirm automatic French text and audible video, stop, and repeat on one non-YouTube video page. This is a core release gate.
- [x] Inspect the final ZIP and `manifest.json`. Include only runtime assets; exclude source secrets, environment files, node_modules, backend credentials, and test artifacts.
- [x] Verify the live build declares `storage`, `activeTab`, `scripting`, `tabCapture`, `offscreen`, Supabase and Google Gemini API hosts; no broad persistent all-sites host permission, microphone permission, or remote executable code.
- [x] Inspect the final manifest to confirm the unused `identity` permission is absent and unavailable provider controls are hidden. Do not claim Google/Apple sign-in works.
- [x] Verify public AI endpoint quotas and errors before enabling AI in the submitted build. Confirm privacy wording against actual backend behavior.

## Store assets and policy

- [x] 128×128 extension/store icon: `public/icon-128.png`.
- [x] Actual 1280×800 screenshots: `screenshot-first-practice-1280x800.png` and `screenshot-live-youtube-1280x800.png`. The YouTube screenshot shows a real watch page with the compact empty state; the tested video exposed no French track. Choose final listing images before uploading.
- [x] 440×280 small promotional image: `store/promo-440x280.png`. Optional marquee omitted.
- [x] Listing copy, privacy URL and verified support contact prepared in `LISTING.md`; enter them in the dashboard.
- [x] Privacy policy deployed and verified: https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-privacy
- [ ] Enter privacy URL and support contact in dashboard.
- [ ] Complete the privacy questionnaire accurately. Optional explanation text/context leaves the browser after consent; do not select “no data collected” without reviewing the questionnaire definitions.
- [ ] Explain every permission and the single learning purpose. Match dashboard disclosures to the build and policy.
- [x] Reviewer instructions include the no-account bundled practice, subtitle-import path, and working existing-account email/password connection. Google/Apple are configuration-gated and are not represented as verified sign-in options. Optional AI reviewer credentials are in ignored `.env.review.local` (never upload this file; copy credentials only into the private reviewer form).

## Publisher account and submission

- [ ] Register a developer account and pay the one-time fee shown by Google if not already registered. Confirm actual checkout amount; do not assume a price from a planning document.
- [ ] Enable Google account two-step verification and complete any dashboard-required identity/contact verification.
- [ ] If enabling provider OAuth later, verify exact Chromium callback allowlisting and provider secrets; retain existing app redirect URLs, add the required `identity` manifest permission in a new build, and enable readiness flags only after verification. These provider paths remain gated in the current build.
- [ ] After first draft upload, compare the assigned store extension ID with development ID `ijclgmkoljddlalgcnpodeemcmcipolb`. If different, allowlist the store ID in the backend and use the dashboard public key for development. Rebuild and reverify AI before submission.
- [ ] After the manual live-audio gate passes, upload `release/parlesprint-immersion-0.1.0-live-2026-10-17.zip` through the developer dashboard.
- [ ] Review dashboard warnings, screenshots, privacy declarations, distribution, and visibility.
- [ ] Submit for review. Record the dashboard item URL and actual submission time. Do not report “submitted” until the dashboard confirms it.

## Official references (checked October 17, 2026)

Google's [image requirements](https://developer.chrome.com/docs/webstore/images/) specify the icon, screenshot, and promotional images. The [developer registration guide](https://developer.chrome.com/docs/webstore/register/) describes the one-time registration fee. Google's [two-step verification announcement](https://developer.chrome.com/blog/policy-update-2sv/) describes the publishing requirement. Review the current [publishing guide](https://developer.chrome.com/docs/webstore/publish/) and dashboard before submitting; requirements can change. Review timing is controlled by Google.
