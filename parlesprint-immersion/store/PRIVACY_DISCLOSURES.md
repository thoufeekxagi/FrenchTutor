# Chrome Web Store privacy form draft

Verify the dashboard's current wording before submitting. This is a disclosure worksheet, not a claim that the form has been submitted.

Single purpose: help adults practise French from videos on regular websites with live captions, sentence replay, and a local vocabulary notebook.

Permissions:
- `storage`: local learning preferences, consent, vocabulary, imported captions, per-video timing, optional account session/account display identity, and explanation cache.
- `activeTab`: on the user's Start action, access the current regular webpage tab for video display and audio capture.
- `scripting`: inject the companion into that current tab after the user starts live captions. The extension does not need persistent access to every website.
- `tabCapture`: capture only the current tab's audio after the user explicitly starts transcription. The audio is routed back to the speakers so video sound continues. No microphone or video frames are captured.
- `offscreen`: process the captured audio stream and maintain the Gemini Live WebSocket while the extension popup is closed.
- Gemini host: connect directly from the extension to Google Live Transcription using a constrained ephemeral token. Supabase receives consent and a random installation ID, enforces duration quotas, and provisions the one-use token; it does not receive audio.
- No `identity` permission in shipped version 0.1. Google/Apple provider sign-in is gated off and unavailable provider controls are hidden. No `getAuthToken`, Chrome profile lookup, or browsing-account enumeration occurs.
- YouTube content script: show the companion on YouTube watch pages. Other pages are injected only on the user's start action. The extension reads the page video's playback position but does not scrape private caption endpoints.
- Supabase host: optional account authentication, explicitly requested explanations, and short-lived live-transcription tokens.

Remote code: none. All JavaScript and the practice audio/video ship in the package. AI JSON explanations are data, never executed. The bundled practice does not call a voice API at playback.

Data handling to disclose:
- Authentication information: optional email/password sign-in and access/refresh session tokens go to Supabase authentication. Passwords are not stored by the extension.
- Personally identifiable information: optional account email/identifier and normal infrastructure network metadata are processed for authentication and quotas. The authenticated account ID, email, display name, and provider may be stored locally to display the connected identity; these display fields are not sent to Gemini.
- Audio and website content: after separate explicit live-transcription consent, the extension sends current-tab audio directly to Google Gemini Live for French speech recognition. It does not send raw audio or video to ParleSprint. The Google API key is held only in Supabase Edge Function secrets; the extension receives a one-use token constrained to the transcription model/configuration. Free/unpaid Google API use may be used to improve Google products, and human reviewers may read/process data. Do not send sensitive or confidential audio. Paid API terms differ.
- Transcripts, saved vocabulary, video page hash, timing and preferences are stored locally. The extension does not send video URLs or a browsing-history feed. Transcript timing is estimated at utterance level; the provider does not return word-level timestamps.
- Separately, after explanation consent, selected French text, its sentence and CEFR level are sent to ParleSprint Supabase and Google Gemini for explanation.
- Backend cache stores generated explanations keyed by a hash of input/model/version. Quota counters contain user UUID/date/count. No automatic database expiry is claimed.
- No analytics, advertising, sale of data, microphone capture, video download, payment, or account vocabulary synchronization.

Do not select “no data collected”: the optional authentication and explanation paths process user data. Review the form's categories for authentication information, personally identifiable information, and website content against the definitions shown there.

Use limitation declarations should reflect the implementation: information is used for the stated learning/authentication function, not sold or used for advertising, creditworthiness, or lending decisions.

Public policy: https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-privacy
Support: thoufeek@agiventures.ca

Provider readiness: the working primary connection is existing ParleSprint
email/password against the same Supabase project/user IDs. Google public settings
are enabled and authorize hands off to Google, but the extension callback was
not accepted; Apple browser authorization reports a missing OAuth secret. Both
provider build gates remain false. No end-to-end Google/Apple sign-in has been
claimed. Do not enter an identity-permission justification for version 0.1 because the
permission is absent. Future provider enablement requires a new build declaring
that permission plus verified secure callback/provider configuration. Do not present either provider as
ready in screenshots, listing copy, or reviewer instructions.
