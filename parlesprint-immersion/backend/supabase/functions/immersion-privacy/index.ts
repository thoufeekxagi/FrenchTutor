const policy = `ParleSprint Immersion privacy policy
Version 0.5 · Updated October 19, 2026

ParleSprint Immersion helps people learn French from video using captions, translations, listening practice and vocabulary review. The current public policy is available at https://parlesprint.com/extension/privacy.

Captions and local learning data

When a video page exposes a caption track, the extension can display it. Imported SRT/VTT files are processed locally. Preferences, cached captions, live transcripts and saved vocabulary stay in Chrome's local extension storage. They are not sent to ParleSprint for storage. Export vocabulary before deleting local data or uninstalling if you want to keep it.

Translation

When English translation is enabled or you select text for a meaning, the selected French text or caption lines are sent to Google Translate. Google processes that request under its own terms and privacy policy. Do not select sensitive personal text.

AI explanations

When you request an explanation, the selected French phrase, nearby caption context and learning level are sent to ParleSprint's Supabase service and Google's Gemini service. You must connect a ParleSprint account for this feature. The request uses your account session. Service limits use a random installation identifier and network IP address as salted hashes. The service caches generated explanations by a hash of the request to avoid regenerating the same answer. The video URL, video ID and raw audio are not sent with an explanation request.

Live captions

Live captions are off until you accept the separate audio notice and choose to start them for the active tab. Chrome captures that tab's audio. The microphone and video frames are not used. The audio stream goes directly from the browser to Google's Gemini Live transcription service. ParleSprint does not receive or store the raw audio. A ParleSprint service issues a short-lived, single-use Google session token; the token request includes the consent flag and random installation identifier. Network IP and installation identifiers are stored only as salted hashes for daily limits. Google's handling depends on the API service used; review the in-extension notice and Google's current terms. Do not use live captions with sensitive or confidential audio.

Accounts and security

Local learning features work without sign-in. If you connect an account for AI explanations, Supabase processes your sign-in information. The extension stores session tokens and display-only account details in Chrome's local extension storage. Signing out removes the local session. Requests use HTTPS. Supabase, Google and Chrome process network information under their own policies.

What we do not collect

The extension does not use your microphone, capture video frames, or send a browsing-history feed. It does not use advertising or analytics. ParleSprint Immersion is independently developed and is not affiliated with YouTube or Google. Captions, translations and AI responses may contain errors.

Your choices and contact

You can decline or withdraw live-audio consent, stop a session, turn translation off, sign out and delete local vocabulary. Data already processed by Google cannot be recalled by ParleSprint. For privacy questions, contact thoufeekbaber1@gmail.com.

Provider policies: Google Translate terms (https://policies.google.com/terms), Google privacy policy (https://policies.google.com/privacy), Gemini API terms (https://ai.google.dev/gemini-api/terms), and Supabase privacy (https://supabase.com/privacy).
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
  return new Response(request.method === "HEAD" ? null : policy, {
    status: 200,
    headers,
  });
});
