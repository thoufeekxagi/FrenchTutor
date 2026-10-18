# Release verification · October 17, 2026

Version 0.1.0. Browser: Playwright Chrome for Testing 156.0.8078.4, macOS ARM64. No Flutter application files changed by this work.

| Check | Result |
|---|---|
| TypeScript strict typecheck | Pass |
| SRT/VTT parsing, sanitization, validation, timing boundaries | 21 parser unit tests pass |
| Loaded real MV3 extension | Pass |
| Caption timing, sentence seek/replay and automatic stopping | Pass on local 35-second media fixture |
| Selection, save/remove/export, reload persistence | Pass |
| Cross-tab preferences and concurrent vocabulary writes | Pass |
| A1/A2/B1/B2 selection, native French TextTrack import | Pass on controlled browser fixture |
| Hide/reveal, subtitle timing offset, minimize and narrow viewport | Pass |
| Invalid subtitles, unavailable native captions, missing AI account | Pass |
| YouTube navigation restores per-video imports | Pass |
| Live YouTube video loads with companion | Pass: https://www.youtube.com/watch?v=qkBf1pshW8E |
| Imported timing sample on live YouTube | Pass: seeking to 6 seconds shows second cue, replay seeks back |
| Fullscreen | Companion deliberately hides; exiting restores it, verified on live YouTube |
| Native captions on that live video | No browser French TextTrack exposed; live audio transcription is the primary path and import is optional |
| Existing account password sign-in → extension background → Supabase → real Gemini | Pass with temporary test account, deleted afterward |
| AI cache, offline cached result, sign-out clears session/cache | Pass |
| 20 curated AI cases | Schema20/20; initial linguistic errors identified, corrected and retested as documented in AI_EVALUATION.md |
| Server quota and table/RPC access checks | Pass, detailed in backend README |
| Public privacy endpoint | GET/HEAD 200 without auth; POST 405 |
| npm audit | Zero known vulnerabilities |
| ZIP security | Runtime-only files, known provider/service secrets absent, exact permissions inspected |
| Independent portability | Source archive extracted outside FrenchTutor; npm ci/typecheck/unit tests/build pass |
| AI model routing | A1/A2 Flash-Lite; B1/B2 Gemini3Flash; prompt/cache3. Five targeted cases schema-pass, four linguistic checklist passes and one partial uncertainty limitation; see AI_EVALUATION.md |
| One-click launcher | Opens dedicated Chrome for Testing on French TV5MONDE YouTube and watches for the first live caption |

The sample subtitle text is original test material, not a transcript of the TV5MONDE video. No automatic public-video transcript download is claimed.

Remaining publisher work: complete Google passkey verification, inspect account registration/2SV status, upload the ZIP/assets, enter disclosures, check the assigned store extension ID and backend origin allowlist, and submit. No submission or approval has occurred. Full manual accessibility/200% zoom and longer real matching subtitle sessions remain recommended before public release; the automated checks above do not certify every video or account type.

The passkey challenge is open in the Codex browser. The Mac was locked during native-surface discovery; unlock it to view the launched browser window.

Git checkpoint: source files remain uncommitted because the repository already has `.git/index.lock` dated October 15. No Git process was shown during the check. The lock was left untouched under the repository’s no-delete rule; the standalone source ZIP preserves the implementation.

## Submission audit follow-up

Final audit: 55 Vitest tests, 10 real Chromium browser tests, and 8 Deno backend tests pass. Production strict TypeScript checking and real YouTube checks pass. The deployed explanation handler is version 5 (prompt/cache 3); the public privacy handler is version 4.

Fixed issues:
- Invalid SRT/VTT separators and invalid native cue values.
- Manual seek, disabling, clear/import, or timing edits leaving a stale replay stop armed; short-cue stopping now checked at animation-frame precision (tested at 2× speed).
- Subtitle import completing after navigation; restoration/import generations now guard stale results.
- Timing offsets leaking between videos; timing is stored per video.
- Long transcripts limited to a fixed slice; all pages are now reachable.
- French reveal and AI meaning reveal sharing state; these are now independent.
- Storage failures silently hiding the interface or causing unhandled errors; failures are actionable, malformed persisted data is sanitized.
- Concurrent refresh and late auth/AI responses after sign-out or consent withdrawal; generation guards prevent session/cache resurrection, refresh is deduplicated, offline sign-out clears locally.
- AI cache persistence failure discarding a valid paid explanation; cache writes are best effort. Auth outages return retryable errors, and upstream deadlines fit the client timeout.

A one-click offline first practice now includes a 41-second original spoken French sample, matched subtitles, authored translations and grammar, replay and saving without an account. All seven spoken lines were checked against a developer-only audio transcription; no missing or additional words were found. A human has not certified the synthetic pronunciation. The voice disclosure is visible. The sample ships locally, does not call a voice API at playback and can be used entirely offline.

Keyboard operation, actual Chrome 200% zoom via tabs.setZoom, narrow windows, a 3,500-character word, 250-cue paging, every sample cue/translation, per-video offset restoration, interrupted imports, and manual replay cancellation are tested. The actual UI account-connection button opens the intended extension page without extra permissions. The unsupported email-code UI is hidden; the verified existing email/password path remains.

Reviewer access for optional AI was prepared and tested without a paid generation. Credentials are retained only in ignored `.env.review.local` with mode 0600; they must be copied only into the store's private reviewer instructions, never included in ZIPs/screenshots/source control. The no-account practice remains the primary reviewer path.

Known product limits remain: imported subtitles are required when YouTube exposes no French TextTrack; the companion hides in fullscreen and restores afterward; AI may still mishandle ambiguous damaged captions. No universal transcription, Netflix support, mic capture, vocabulary account sync, or analytics is claimed. Public submission still requires the publisher's passkey verification and dashboard completion.

Final artifact audit: the rebuilt Chrome ZIP is 529,552 bytes with 19 runtime files; only storage plus the exact Supabase host permission. Provider/service secrets and private reviewer credentials were absent from both archives. The final source archive installed, passed all 34 unit tests, and built in a new directory outside FrenchTutor. The revised first-practice launcher was restarted successfully.

## Premium UI and account verification follow-up

The extension now matches the actual app’s Inter family, #2563EB primary actions, #F5F6F8 canvas, #14171C ink, and rounded white surfaces. The offline practice uses a responsive two-column layout; the popup uses keyboard-accessible Practice, Notebook and Account tabs. Original blue listening artwork and icons replace the earlier green styling. Mobbin Babbel references informed spacing only; no reference images are shipped.

The rebuilt release passed strict TypeScript, 55 unit tests (21 parser, 30 background and 4 store), 10 Chromium flows, and 8 backend tests. The new browser test verifies loaded local Inter, actual primary blue, and no horizontal overflow at 390 pixels. An initial font test compared Chrome’s quoted family serialization literally; the corrected assertion confirms the loaded family. Live YouTube import/replay/fullscreen passed again. Live existing-account sign-in, matching account ID, Gemini response, learner UI, offline cache and sign-out passed using the dedicated reviewer account without a service key. Reviewer credentials were not shown or archived.

The Account button opens directly to the Account tab. Exact sender checks allow only popup.html and popup.html#account. Google’s extension callback is not allowlisted and Apple web authorization lacks its provider secret, so neither is offered in this release. The unused identity permission is omitted. Email/password uses the app’s existing Supabase identities. Vocabulary remains local; no synchronization is claimed.

Fresh screenshots were captured using actual controls and saved vocabulary, with animation transitions completed. Store primary screenshot is the real bundled listening sample. Public privacy policy version 4 covers account identity and the shipped storage-only permission. Publisher sign-in still stops at Google’s passkey challenge; no store submission is claimed.

The updated source ZIP was again extracted into an unrelated /tmp directory: fresh npm ci, strict typecheck, all 55 unit tests, and production build passed with only the portable public .env.example settings. The source archive does not depend on the FrenchTutor parent folder. Final runtime ZIP: 23 files, 840,191 bytes, SHA-256 96b549c957f68b625e0ce958872818411b895a260604d34430dd4b03698f94f3. Manifest requests storage only; provider/service secret pattern scan passed.

## October 17 quiet watch-page follow-up

The user asked that the watching experience keep the video primary, use the ParleSprint blue/white palette, and feel quiet rather than promotional. The YouTube companion now omits the visible wordmark, sits over the player as a compact French caption layer, and keeps subtitle setup, phrase study, replay navigation, reading preferences and transcript tools behind small controls. It measures both the player and panel so the header remains reachable on short videos, and the expanded panel respects the saved left/right choice. The separate bundled practice page retains the ParleSprint identity.

Fresh verification after this UI change: strict TypeScript passes, all 81 unit tests pass, and all 15 Chromium extension tests pass. The live YouTube page at https://www.youtube.com/watch?v=qkBf1pshW8E loads and shows the compact setup state. The video exposes no French browser TextTrack in this run, so this screenshot proves placement and injection only; imported matching SRT/VTT remains the supported route. The live test also imports a clearly disclosed timing fixture, checks synchronization and replay, verifies the host layer remains clickable, and confirms fullscreen hides/restores the companion. The local practice screenshot uses the bundled original audio with its matched captions; it is not a transcript of the TV5MONDE video.

Screenshots were recaptured from the running extension: `screenshot-first-practice-1280x800.png` and `screenshot-live-youtube-1280x800.png`. A separate 1280×1000 capture, `artifacts/highlighting-practice.png`, shows blue selection and green saved-phrase highlighting in the local sample. The reference image supplied by the user was treated as the brand/palette source; Mobbin was only used for spacing comparison, and no reference screen assets were copied into the build.

Final package and move test: runtime ZIP has 23 files, 850,100 bytes, SHA-256 `73cfef96db4bef10b988da55e26dd7b985b28bded306ff44998120ccb6087c01`; its manifest contains only the `storage` permission and the exact existing Supabase host. The 80-file source archive was extracted into `/Users/thoufeekx/Desktop/ParleSprint-Immersion`, outside the FrenchTutor project. A clean `npm ci` found no known vulnerabilities; with the launcher's public `.env.example` setup applied, typecheck, all 81 unit tests, production build and all 15 browser tests passed from that new folder. The launcher is running the independent copy with its bundled first practice open.

The real email/password account flow and a Gemini explanation were retested after the UI change. Consent, structured response, cached offline result and sign-out all passed; reviewer credentials and service keys were not included in either archive. Publisher passkey verification and Chrome Web Store dashboard submission remain incomplete, so this is a release candidate, not a submitted listing.

## October 17 live-audio implementation follow-up

The previous “supported import fallback required” note above describes the earlier subtitle-only build and is superseded: the extension now captures audio from the active video tab after a real toolbar action and streams it to Google's French Live transcription model. The Supabase token function and quota migration are deployed. The extension ZIP contains no provider secret value; the provider key is the server-only `GEMINI_API_KEY` Supabase Edge Function secret, and the extension receives only a constrained one-use token.

Current verification: `npm run check` passes strict TypeScript, 87 unit tests, and the production build; `npm run test:e2e` passes all 15 browser flows. `npm run test:youtube` passes against the real TV5MONDE YouTube page for injection, layout, optional imported timing/replay, and fullscreen. That video has no browser French TextTrack. The safe endpoint denial returns 403 when consent is false, and the deployed privacy endpoint returns 200. The earlier runtime ZIP is 857,678 bytes, 26 files, SHA-256 `8f0ebe9232c9c0cca94828847c10376c4f57d09007cb6f02cf94d275f2b4a5e9`; no provider/service key values or `.env` files are present.

The separate source ZIP (`release/parlesprint-immersion-source-live-2026-10-17.zip`) was extracted into a new temporary folder outside the app. Fresh `npm ci` found zero vulnerabilities; strict typecheck, all 84 unit tests, and production build passed there too. It includes `.env.example` only, never the local `.env.local` or review credentials.

**Still unverified:** an actual user-triggered tab capture and successful interim/final model caption, preserved audible video output during capture, Stop releasing the stream, and a non-YouTube capture. The dedicated test Chrome is open on the TV5MONDE video and its launcher watches for captions. Playwright can load the action popup programmatically but cannot grant Chrome's user-gesture `activeTab` permission, so the automated live test stopped before any provider-token request; it sent no video audio and consumed no transcription quota. Do not submit the store listing until the manual live start/stop QA in `store/QA.md` passes.

### Standalone copy check — October 17, 2026

Synced the latest extension source to `~/Desktop/ParleSprint-Immersion` without overwriting its `.env.local`, user data, or prior release artifacts. The existing public Supabase settings match the source copy. In that standalone folder, fresh `npm ci` reported zero vulnerabilities, `npm run check` passed strict TypeScript, 87 unit tests and production build, `npm run test:e2e` passed all 15 flows, and `npm run test:youtube` passed with no exposed French text track. A new dedicated Chrome for Testing window is open from this folder. **Manual live transcription has not yet reached the watcher**: start it from the extension toolbar in that window, verify the actual French text and audible playback, then stop and repeat on a regular non-YouTube video site before submission.

## October 18 ad, seek, and mute robustness follow-up

Playback captions follow the YouTube video clock, not elapsed wall time. The content script tracks play/pause, seek start/completion, playback rate, mute/volume, video navigation, and YouTube's `#movie_player.ad-showing` state. It also detects an unexpected large clock jump if the seek event is missed. Seeks, ad transitions, mute changes, and video navigation invalidate the current speech segment; audio is not sent during ads, seeks, pauses, or muted playback, and delayed model text from an older segment is discarded. Short live captions appear immediately and estimated cue timing scales with playback speed.

Verification on October 18: strict typecheck, 98 unit tests, production build, and all 19 Chromium tests pass. The browser suite checks 10s/15s forward seeks and YouTube-style ad suppression; two real French YouTube pages (`UwqQbIDVSgE`, `D4dpRjd_rYo`) pass placement, fixture timing/replay, theater mode, fullscreen restore, and ad-marker UI checks. The ad marker was simulated, no actual ad was served, and these smoke tests did not run live audio transcription. Actual toolbar-started capture across a real ad still requires the manual check in `store/QA.md`.
