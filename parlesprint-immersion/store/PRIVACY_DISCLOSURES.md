# Chrome Web Store privacy form worksheet (v0.2.0)

Verify the dashboard's current wording before submitting. This is a worksheet, not a claim that the form has been submitted.

Single purpose: help adults learn French while watching YouTube videos by showing French captions, word meanings and translation beside the video.

## Data the extension handles

| Data | When | Where it goes |
| --- | --- | --- |
| YouTube French caption track | Opening a YouTube watch page | Requested from youtube.com by the page's own origin; cached locally by video ID |
| Selected French word, phrase or caption line | User taps a word or turns on English translation | Google Translate (translate.googleapis.com). Nothing else is attached: no URL, video ID or identity |
| Tab audio | Only after the user accepts the audio notice and starts live captions | Streamed straight to Google Gemini live transcription. Not sent to ParleSprint |
| Selected word/phrase, its caption line and level | User presses Explain in context | ParleSprint Supabase function, then Google Gemini; cached server-side by hash. Random installation ID for a daily limit (20/day). No account |
| Consent flag | Starting live captions | ParleSprint Supabase function, which issues a one-use Google token. No audio |
| Preferences, vocabulary, cached captions, live transcripts, per-video timing | Always | Chrome local extension storage only |

Not collected: microphone audio, video frames, browsing history, YouTube account data, name, email, passwords, payments, analytics, advertising identifiers. No sign-in or accounts exist in this version.

## Dashboard categories

- Website content: yes (captions text and selected text, and tab audio when live captions run). Used only for the stated learning function.
- Personally identifiable information, authentication information: no.
- Do not select "no data collected": selected text goes to Google Translate and audio goes to Google Gemini on explicit user action.
- Certify: not sold, not used for advertising, creditworthiness or lending.

## Permission justifications

Copy from `LISTING.md`. Remote code: none.

## Google terms to mention in reviewer notes

- Translation uses Google's keyless translate endpoint and may be rate limited or change. The extension degrades to "No meaning found" and does not break captions.
- Live transcription uses Google's Gemini API. On Google's unpaid tier submitted audio may be used to improve products and reviewed by people; the consent text says so. Move to a paid key before heavy use.
- Explain in context is limited to 20 per installation per day (server-enforced). Live captions currently have NO server-side daily limit on the deployed token function: add one before public launch.

Public policy: https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-privacy
Support: thoufeekbaber1@gmail.com
