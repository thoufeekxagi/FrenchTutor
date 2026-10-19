# Chrome Web Store listing copy reference — source version 0.2.0

The owner confirmed the extension is live in the Chrome Web Store on October 19, 2026. This file is a product-copy reference for future maintenance, not a verified export of the live dashboard listing. The published version and metadata have not been independently checked.

**Name:** ParleSprint Immersion
**Summary:** Live French video captions, translations, sentence replay and vocabulary review for focused listening practice.
**Category:** Education
**Language:** English
**Price:** Free

## Description

Turn French video into active listening practice. ParleSprint Immersion can show available subtitles or create live French captions from a video tab after you choose to start and accept the audio notice.

- Start optional live transcription from the active tab. The video keeps playing; the microphone and video frames are not used.
- Follow the French transcript as you listen, then replay a sentence and review the vocabulary you want to keep.
- Translate selected words or the displayed caption lines with Google Translate.
- Request a short AI explanation of a selected phrase and its nearby caption context. This feature requires connecting a ParleSprint account.
- Save words, phrases, and transcripts in Chrome on your device. Export vocabulary as JSON or Anki-compatible CSV.
- Use available player captions or import an SRT/VTT subtitle file when that works better for the video.

Live audio is off until you accept the separate notice and start it. During a live session, tab audio streams from the browser to Google's Gemini service. Raw audio is not received or stored by ParleSprint. Google may handle submitted content differently on unpaid and paid API services; review Google's terms and the in-extension notice before use. Do not transcribe sensitive or confidential audio.

Google Translate receives the selected French text or displayed caption lines when translation is enabled. If you request an AI explanation, the selected phrase, nearby caption context and learning level are sent to ParleSprint's Supabase service and Google Gemini. The backend uses the account session and daily-limit data to provide that feature. Learning preferences, saved vocabulary, cached captions and transcripts are stored in Chrome's local extension storage. No browsing-history feed, analytics or advertising is used.

ParleSprint Immersion is independently developed and is not affiliated with or endorsed by YouTube or Google. Captions, translations and AI explanations can contain errors. Video audio quality, site restrictions, DRM, muted playback and speech that is not French can affect results.

Privacy policy: https://parlesprint.com/extension/privacy
Support: thoufeekbaber1@gmail.com

## Single purpose

Help people learn French from video using captions, listening practice, phrase support and vocabulary review.

## Permission justifications for the checked-in source

These justifications describe the repository's checked-in manifest. They do not confirm that the live store package has the same permission set. Check the publisher dashboard before changing its privacy declarations.

Source review note: `wxt.config.ts` declares `storage`, `activeTab`, `scripting`, `tabCapture`, and `offscreen`, and host access to Supabase, Google Translate and YouTube. The checked-in source also contains optional Chrome Identity sign-in and a Gemini Live connection, but those permission/host entries are not declared in that manifest. Reconcile the source and manifest before building a future store package. This handoff intentionally leaves extension code and the live package unchanged.

- `storage`: save preferences, consent, cached captions, live transcripts, account session and vocabulary in Chrome on the device.
- `activeTab` and `scripting`: inject the companion into the page after the learner starts the feature for that tab.
- `tabCapture`: capture audio from the active tab only after the learner accepts the audio notice and starts live captions. The microphone and video frames are not captured.
- `offscreen`: keep tab-audio processing and the Gemini transcription connection alive while the popup is closed.
- `https://www.youtube.com/*`: read the current player state and use French captions exposed by the YouTube page when available.
- `https://translate.googleapis.com/*`: send selected or displayed French text to Google Translate when translation is requested or enabled.
- `https://oxfnrsjskdjbroekxdco.supabase.co/*`: request explanations, live-session tokens and service limits. The backend does not receive live audio.
- Remote code: none. All JavaScript ships in the package.

## Reviewer instructions

Use the included offline practice to review captions, phrase meanings, sentence replay and vocabulary without signing in. Live transcription is optional and requires the learner to accept its audio notice before starting. To review it, use an ordinary French video tab with audible French speech, start live captions from the extension popup and stop the session from the popup. Account-backed explanations are optional and require a ParleSprint account.

Do not claim store approval, official YouTube or Google partnership, support for every video, official language scores or guaranteed transcription accuracy. Capture listing screenshots from the current build.
