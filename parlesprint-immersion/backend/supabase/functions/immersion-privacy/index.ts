const policy = `ParleSprint Immersion privacy policy
Version 0.2 · Updated October 17, 2026

ParleSprint Immersion helps you practise French from videos in regular browser tabs with live captions, replay, and a local vocabulary notebook.

Live French transcription

Live captions are optional and start only when you open the extension popup, accept the audio notice, and choose Start. Chrome grants access to the current tab for that user action. The extension captures only the active tab's audio, continues routing the sound to your speakers, and does not use your microphone or capture video frames. The extension can inject its companion into that page after you start.

The captured audio is streamed directly from the extension to Google's Gemini Live transcription service. Raw tab audio is not sent to or stored by ParleSprint. The ParleSprint Supabase Edge Function receives your consent and a random installation identifier, hashes that identifier for a daily duration quota, and uses the server-only GEMINI_API_KEY secret to create a constrained, one-use, short-lived Google session token. The extension receives that token; the provider API key never enters the extension bundle. Supabase stores only daily hashed installation quota counters for this service. It does not receive or store audio.

Google's Gemini API terms depend on whether the account uses an unpaid/free service or paid service. Google states that content submitted through unpaid services may be used to provide, improve, and develop Google products and machine-learning technologies, and human reviewers may process that content. Do not use live transcription on sensitive or confidential audio. Google's paid-service terms state that prompts and responses are not used to improve products. See Google's current Gemini API terms and pricing for details.

The transcript and estimated utterance timing are stored in Chrome's local extension storage under a hash of the video page URL. Live transcription does not provide word-level timestamps. You can stop capture at any time from the popup; the live connection closes and the tab stream is released. A session lasts up to eight minutes and may renew while listening. The current service quota reserves up to 30 minutes per installation per UTC day and 60 minutes across all users per UTC day. Sites that block extension access, DRM-protected media, muted tabs, poor audio, or non-French speech may not work as expected.

Local practice and preferences

The extension includes an original short French listening sample and authored translations. Its bundled audio can be played without an account or AI request. Learning preferences, audio/explanation consent, saved vocabulary, transcripts, optional imports, account session and explanation cache are stored in Chrome's local extension storage. Vocabulary can include selected words, phrases, sentences, learning level, saved time, and explanation. Imported subtitle files are processed locally. Signing out removes the session and local explanation cache. Uninstalling the extension removes its local data; export vocabulary you wish to keep first.

Optional account connection and explanations

Local learning works without an account. Existing ParleSprint email/password accounts use the same Supabase service as the app. Your password is sent to Supabase for authentication and is not stored by the extension. Account identifier, email, display name, provider, and session tokens may be stored locally to show and maintain your connection. Google and Apple browser sign-in are currently disabled in this version.

AI explanations use separate consent. When you request an explanation, the selected French text, subtitle sentence, and learning level are sent to the ParleSprint Supabase service, which calls Google's Gemini service. Your account/session identifier and network metadata may be processed for authentication and usage limits. The backend stores cached explanations and account-based daily quota counters. These server records do not currently have automatic expiry. Do not include sensitive personal information in selected text.

Analytics, sale, and sharing

This release contains no analytics events, advertisements, or sale of personal information. The extension does not send a browsing-history feed or video URL. Chrome, websites, Supabase, and Google process service and network data under their own policies.

Your choices and contact

You can stop live captions and withdraw audio consent from the popup. You can remove saved vocabulary with the extension controls. Disabling consent or clearing local data does not remove requests already processed by Google or existing backend explanation records. For privacy questions or account data requests, contact thoufeek@agiventures.ca. Never send an API key or session token.

Provider policies: https://supabase.com/privacy and https://ai.google.dev/gemini-api/terms
Publisher contact: thoufeek@agiventures.ca.
`;

Deno.serve((request: Request) => {
  const headers = {
    "Content-Type": "text/plain; charset=utf-8",
    "Cache-Control": "public, max-age=3600",
    "X-Content-Type-Options": "nosniff",
    Allow: "GET, HEAD",
  };
  if (request.method !== "GET" && request.method !== "HEAD")
    return new Response("Method not allowed", { status: 405, headers });
  return new Response(request.method === "HEAD" ? null : policy, { status: 200, headers });
});
