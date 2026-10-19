# Chrome Web Store privacy form worksheet (version 0.2.0)

The owner confirmed the extension is live in the Chrome Web Store on October 19, 2026. This is a disclosure worksheet, not a snapshot of the live dashboard form. Verify the publisher dashboard's current questions and package permissions before changing any store declarations. The current public policy page is `https://parlesprint.com/extension/privacy` once the website deploy completes.

## Single purpose

Help people learn French from video using captions, listening practice, phrase support and vocabulary review.

## Data the extension handles

| Data | When | Where it goes |
| --- | --- | --- |
| Captions exposed by a page or subtitles imported by the learner | When selected or opened | Page captions are read in the browser; imported files are processed locally; both may be cached in Chrome local extension storage |
| Selected French text or caption lines | When the learner taps a word/phrase or English translation is on | Google Translate for an English meaning; no video URL or video ID is attached |
| Tab audio | Only after the learner accepts the audio notice and starts live captions | Streamed from the browser directly to Google Gemini; not received or stored by ParleSprint |
| Selected phrase, nearby caption context and learning level | When the learner requests an AI explanation | Authenticated ParleSprint Supabase function, then Google Gemini; the response is cached server-side using a request hash |
| Email/password credentials or supported provider response, account ID and session tokens | Only when the learner chooses to connect an account for explanations | Supabase processes sign-in; session tokens and display-only account information are kept in Chrome local extension storage |
| Random installation identifier and network IP address | When requesting a token or explanation, for service limits | The server stores salted hashes for daily limits; raw live audio is never sent to this service |
| Preferences, cached captions, transcripts and saved vocabulary | During use | Chrome local extension storage on the learner's device |

Not collected by the extension: microphone audio, video frames, a browsing-history feed, advertising identifiers or analytics. No information is sold or used for advertising. The extension can process account information when the learner elects to sign in; do not select a disclosure claiming that no data is collected.

## Dashboard categories to review

- Website content: yes. Caption text and selected text are used for translations/explanations; tab audio is used only after a separate consent and explicit start action.
- Personal information: email and account identifier may be handled when the learner signs in.
- Authentication information: account credentials are sent to Supabase for sign-in; session tokens are stored locally to maintain the session.
- Audio: tab audio is sent directly to Google Gemini only after the learner consents and starts live transcription. It does not go to ParleSprint.
- Confirm that data is used for the extension's disclosed learning purpose, is not sold and is not used for advertising, creditworthiness or lending.

## Permission justifications

Use the checked-in permission list in `LISTING.md` as a source-code reference only. The live store package's permissions have not been independently verified in this task. This task leaves the live package and listing untouched.

## Google terms to mention in reviewer notes

- Translation uses Google's Translate endpoint. Results may be limited or change; caption practice remains available.
- Live transcription uses the Gemini API. Google's terms vary by service tier; content sent through unpaid services may be used to improve products or reviewed by people. The extension shows an audio notice before capture. Do not use it with sensitive audio.
- Service rate limits are enforced by the backend. Check the current Supabase deployment and environment values before publishing; limits documented in historical verification notes may be stale.

Support: thoufeekbaber1@gmail.com
