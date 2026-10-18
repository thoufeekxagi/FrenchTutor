# Chrome Web Store listing draft

**Name:** ParleSprint Immersion

**Summary:** Watch videos with live French captions, study phrases, replay sentences, and save words in a private notebook.

**Category:** Education

**Language:** English

**Price:** Free

## Description

Keep the video in view while a quiet French caption layer follows along. When matching subtitles are available, tap a word to study it or repeat the sentence.

Try the bundled 41-second French listening sample with synchronized captions, authored English translations, grammar notes, sentence replay, and vocabulary saving. The sample works offline without signup. Its voice is synthetic and clearly disclosed.

Play a French video on a regular webpage and start live captions from the extension popup. ParleSprint transcribes the current tab's audio directly with Google Gemini Live; no subtitle upload, player caption track, or microphone is needed. Choose A1, A2, B1, or B2, select words or phrases, repeat a sentence, and save vocabulary in your browser. Blue marks your current selection; green underlines saved vocabulary. Search your notebook and export JSON or Anki-compatible CSV.

Core practice works without signup. Vocabulary and preferences stay in local Chrome extension storage. Connect your existing ParleSprint email/password account for optional AI explanations. These offer meaning, grammar, and an example when you explicitly enable the connected service.

The extension captures audio only from the active browser tab after you start it and accept a separate consent notice. The sound continues playing. Audio is sent directly to Google's Gemini Live API; it is not sent to or stored by ParleSprint. Google's free API tier may use submitted audio to improve its products and may include human review. Transcript timing is approximate at utterance level, not word-level. Sites that block extension access or protect media may not work. Do not use with sensitive content.

This version does not use your microphone, download video files, synchronize vocabulary across devices, or guarantee protected media support. AI explanations and speech recognition may contain errors. ParleSprint Immersion is independently developed and is not affiliated with YouTube or Google.

## Single purpose

Help users study French from live captions while watching a video in a regular browser tab.

## Permission justification

- `storage`: save learning preferences, consent, and vocabulary locally.
- `activeTab`, `scripting`, and `tabCapture`: inject the companion and capture the active tab's audio only after the user starts it.
- Offscreen document: maintain the audio stream while the popup closes and connect to Google's live transcription service.
- `https://oxfnrsjskdjbroekxdco.supabase.co/*`: authenticate the optional account connection and send explicitly requested explanations after consent.

## Reviewer instructions

Open the extension popup and choose **Try your first practice**. Play the bundled video, reveal a sentence translation, select a word, repeat, and save it. This fully working local path needs no account or imported file.

Load a French video with clear speech. In the extension popup, accept the live-audio disclosure and press **Start live captions on this tab**. Confirm audio remains audible, interim/final captions appear, sentence replay and study work, and Stop releases capture. Repeat on YouTube and a second public video site. Local notebook features require no account. Explain the quota and Google's free-tier data use in reviewer instructions and consent copy.

**Privacy URL:** https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-privacy

**Support:** thoufeek@agiventures.ca (existing ParleSprint support contact).

Enter these in the dashboard. Do not claim backend verification, store approval, automatic captions, or live screenshots until evidenced.
