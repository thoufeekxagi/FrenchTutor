# Chrome Web Store listing draft

**Name:** ParleSprint Immersion

**Summary:** French captions under YouTube videos, with instant word meanings, English translation and a private vocabulary notebook.

**Category:** Education

**Language:** English

**Price:** Free

## Description

Learn French from the videos you already watch. Open a French YouTube video and ParleSprint Immersion shows the French captions right under the player, no setup and no sign-in.

- Captions follow the video, including seeking, pausing, speed changes and ads.
- Tap any word to see its English meaning and alternatives. Press Explain in context for a short grammar note and example. The word being spoken is highlighted in blue as it is said.
- Turn English translation on or off under each line. Hide the French when you want to test your listening.
- Repeat any line. Save words and phrases to a private notebook, then export them as JSON or Anki-compatible CSV.
- Choose your level (A1 to B2). Dark, quiet design that stays out of the way.
- No captions on a video? Optionally start live captions from the extension popup. ParleSprint listens to that tab's audio and transcribes the French.

Privacy: captions are fetched from YouTube the same way the player does. When you tap a word or turn on translation, only that French text is sent to Google Translate. If you press Explain in context, that word, its caption line and your level go to ParleSprint's server and Google Gemini. Live captions are off until you start them and accept a separate notice; then the tab's audio is sent to Google's Gemini service. Vocabulary and preferences stay in your browser. No accounts, no analytics, no ads.

ParleSprint Immersion is independently developed and is not affiliated with or endorsed by YouTube or Google. Captions and translations can contain errors. Do not use live captions with sensitive content.

## Single purpose

Help users learn French while watching YouTube videos by showing French captions, word meanings and translation beside the video.

## Permission justification

- `storage`: save preferences, consent, cached captions and the vocabulary notebook in the browser.
- `activeTab` and `scripting`: when the user starts live captions from the popup, run the caption companion in that tab.
- `tabCapture`: capture the audio of the current tab, only after the user starts live captions and accepts the audio notice. Sound keeps playing. The microphone and video frames are never captured.
- `offscreen`: keep the captured audio stream and the connection to Google's transcription service alive while the popup is closed.
- `https://www.youtube.com/*` (content script on watch and Shorts pages): show captions under the video, read the playback position, and request the video's French caption track from YouTube.
- `https://translate.googleapis.com/*`: send the word, phrase or caption line the user selects to Google Translate and receive the English meaning. Nothing else is sent.
- `https://generativelanguage.googleapis.com/*`: stream tab audio to Google's Gemini live transcription, only while live captions run.
- `https://oxfnrsjskdjbroekxdco.supabase.co/*`: (a) request a short-lived, single-use Google session token for live captions; (b) send the selected word, its caption line and level for Explain in context. Requests carry a random installation ID for a daily limit, never audio, accounts or video URLs.
- Remote code: none. All JavaScript ships in the package.

## Reviewer instructions

1. Open https://www.youtube.com/watch?v=EaNqp4FXh-s (Extra French, episode 1). Press play and skip to 1:02. French captions appear under the player on their own.
2. Tap a word: its English meaning appears. Press Explain in context for grammar and an example (no sign-in). Press EN to show the translation under the line, FR to hide the French.
3. Optional live captions: on a video without captions, open the extension popup, expand "Video has no captions?", accept the audio notice and press Start live captions on this tab. Audio keeps playing, French text appears, Stop releases capture.
4. The popup also has a 41-second bundled sample that works offline.

**Privacy URL:** https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-privacy (same text as `public/privacy.html`; deploy the function before submitting)

**Support / feedback:** thoufeekbaber1@gmail.com

Do not claim store approval, official YouTube or Google partnership, or support for every video. Live screenshots must come from the current build.
