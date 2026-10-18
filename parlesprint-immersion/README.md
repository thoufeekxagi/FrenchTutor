# ParleSprint Immersion

A free Chrome Manifest V3 extension for studying French from videos on regular websites. It can transcribe audio from the active browser tab in real time, so learners do not need a subtitle file or a site's caption track. Built with WXT, React, TypeScript, Tailwind, and Zustand. This directory is self-contained: copy it anywhere or put it in its own repository. It does not require the Flutter app or its build tools.

## Open it now

On this Mac, double-click `Launch ParleSprint.command`. It builds and opens a dedicated Chrome for Testing window with the extension loaded and a French TV5MONDE YouTube video ready to play. The launcher watches for live captions and saves the first caption screenshot. It uses its own local browser profile; close that window to stop it. The first launch requires Node.js 22.12+ and downloads the official Playwright Chromium browser if missing.

The current runtime ZIP is `release/parlesprint-immersion-0.1.0-live-2026-10-17.zip`; extract it and load its folder through Chrome Developer mode to use your usual Chrome profile.

## Run locally

Use Node.js 22.12 or newer and npm. From this directory:

```sh
npm ci
npm run typecheck
npm test
npm run build
npx playwright install chromium
npm run test:e2e
```

Open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select this directory's `.output/chrome-mv3` folder. Pin ParleSprint Immersion from Chrome's extensions menu. Open any regular video webpage, play the video, click the extension icon, review the live-audio consent, and choose **Start live captions on this tab**. The extension injects its compact companion into the page and shows French speech as the model transcribes it. Open the popup again and choose **Stop live captions** to stop the stream.

For development, run `npm run dev`. For a production upload archive, run `npm run zip`; WXT writes the ZIP beneath `.output/`. Upload the generated extension ZIP, not the source directory.

## First practice session

1. Play a French video in a regular browser tab. On YouTube, use a video with sound; captions do not have to be enabled.
2. Click the extension icon, read the notice, agree to send this tab's audio to Google for live transcription, and choose **Start live captions on this tab**. Video sound continues playing while the tab is captured.
3. French captions appear in the on-page companion while you watch. Choose A1, A2, B1, or B2, select a word or phrase, repeat a sentence, and save vocabulary.
4. Stop from the popup at any time. Final transcript segments are saved locally for that video; timing is estimated at sentence/utterance level, not word level.
5. The bundled original listening practice remains available without transcription, account, or internet. AI explanations are optional and have separate consent.

The subtitle-file and exposed-player-caption options remain available inside **Other subtitle options** for unusual cases. They are optional; automatic tab-audio transcription is the primary path.

## Supported scope and limits

Chrome tab capture can process audio from video sites without accessing private caption endpoints, downloading video files, or using a microphone. Sites that block extension access, protected/DRM media, muted tabs, inaccessible browser pages, poor audio, or non-French speech may not transcribe as expected. Google Live does not provide word-level timestamps, so transcript timing is approximate. A single live connection is limited to eight minutes and renews while active. Quotas currently cap one installation at 30 minutes and the whole service at 60 minutes per UTC day. The free Gemini API tier may use submitted audio to improve Google products and may include human review; review the consent notice before starting. Do not send sensitive audio. Learning levels guide the interface/explanations; the extension does not certify the video's French level. AI output can be wrong.

Saved transcript cues, words, and preferences use Chrome local extension storage. Raw tab audio is sent directly from the extension to Google's Gemini Live API; the ParleSprint backend issues a short-lived, single-use token but does not receive or store the audio. The API key remains in Supabase Edge Function secrets. Saved vocabulary is capped at the latest 2,000 entries. Uninstalling removes local data; export vocabulary you wish to keep before uninstalling. This is a companion learning tool, not an official YouTube or Google product.

## Optional AI backend

The build uses the existing ParleSprint Supabase service. A1/A2 explanations use Gemini 3.1 Flash-Lite; B1/B2 use Gemini 3 Flash. Results are cached, with 20 new generations per account and 500 globally per UTC day. Live transcription uses `immersion-live-token`; Supabase keeps the provider API key and returns a one-use, short-lived token constrained to French transcription. It reserves at most eight minutes at a time, with a 30-minute per-installation and 60-minute global daily cap. Copy `.env.example` to `.env.local` before rebuilding elsewhere; its two values are public browser configuration. The manifest grants access to this project and Google's Gemini API only. Connect an existing email/password account in the popup for optional explanations. No anonymous account sign-in setting was changed.

The privacy policy is hosted at https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-privacy.

The `backend/` directory contains the separately deployable Supabase implementation. Follow its setup documentation and configure public extension connection settings as described there. Provider secrets belong in Supabase Edge Function secrets only. Never copy a Gemini/OpenAI secret key into extension source, settings, build variables, screenshots, or the ZIP. Only public Supabase connection settings are distributed.

Before enabling a public endpoint, verify database migrations, session quotas, request validation, and secret configuration. An unavailable service must leave local practice usable. Review `public/privacy.html` and `store/SUBMISSION_CHECKLIST.md` before publication.

## Release verification

The current standalone Desktop copy passes strict TypeScript, 87 unit tests, and 15 Chromium browser tests. A live YouTube QA run confirms the video loads, the compact companion appears, the player exposes no French text track, and the optional timing fixture syncs/replays and hides in fullscreen. Automatic Gemini transcription is implemented; a real Chrome toolbar-start session is the remaining manual gate in `store/QA.md`, because Chrome requires a real user gesture to grant tab-audio capture. The automated test stopped before requesting a provider token, so it sent no audio and used no transcription quota. See `store/VERIFICATION.md` for the exact status.

Run the automated commands above, then complete `store/QA.md` in real Chrome, including live transcription with actual audio and a non-YouTube page. Automated tests alone do not prove live provider operation. Store copy is in `store/LISTING.md`; the submission checklist separates generated artifacts from the account and publishing steps that remain.

## Current release status

Built and tested October 17, 2026. See `store/VERIFICATION.md` and `store/AI_EVALUATION.md` for measured checks and limits. The extension and source ZIPs are in `release/`. Chrome Web Store submission has not occurred: Google requires the publisher’s passkey verification in the open Codex browser tab. After signing in, complete `store/SUBMISSION_CHECKLIST.md`. No Git push was performed.

The October 17 UI pass matches the app’s blue action palette, cool gray surfaces and bundled Inter. The YouTube companion uses a compact caption layer, keeps the ParleSprint wordmark out of the video view, and puts setup and study controls behind a disclosure. Practice, Notebook and Account tabs support keyboard navigation. Existing ParleSprint email/password accounts are verified; Google/Apple controls are hidden until their browser authentication configuration is complete. Account connection does not synchronize vocabulary.

## Feedback-driven reading improvements

See [competitor research](store/COMPETITOR_RESEARCH.md) and the 30-review paraphrased sample in `store/competitor-feedback.csv`. Selected occurrences are blue; saved vocabulary is green and underlined. Select a phrase by its first and last word or extend a selection with Shift-click. The colors do not claim word-level CEFR difficulty or audio alignment. Reading size, highlighting and left/right placement persist. Previous/next, speed and repeat keep the session focused; a repeated sentence remains visible while paused.

The first install opens the bundled practice once. Live tab-audio transcription is the primary video path; exposed player captions and an optional SRT/VTT file remain fallback choices. Notebook search ignores accents; JSON and Anki CSV exports remain free. Anki CSV follows the documented UTF-8 text-file header format (Anki 2.1.54+) and exports Front, Back and Context. In Anki's import preview, choose a note type with a Context field if you want all three columns; Basic has only Front/Back. If the same phrase was saved in several contexts, review Anki's duplicate/update option before importing. We have validated the downloaded file and header format, not imported it into the user's Anki collection.
