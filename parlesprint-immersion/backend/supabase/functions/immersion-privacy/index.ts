const policy = `ParleSprint Immersion privacy policy
Version 0.4 · Updated October 18, 2026

ParleSprint Immersion helps you learn French from videos on YouTube. It shows French captions under the video, English meanings for words you tap, and a private vocabulary notebook on your device.

Captions from YouTube

When you open a YouTube video page, the extension asks youtube.com for that video's French caption track, the same captions the YouTube player uses, using your normal browser connection. The captions are shown under the video and are stored in Chrome's local extension storage under the video ID so they load faster next time. They are not sent to ParleSprint.

The extension reads the video's playback position and state (playing, paused, seeking, ad) on the page so captions stay in sync. It does not read your YouTube account, watch history or comments.

Translation and word meanings

When you tap a word or phrase, or turn on English translation, the selected French text or the current caption line is sent to Google Translate (translate.googleapis.com) to get the English meaning. Only that text is sent. The video URL, video ID, your identity and your vocabulary are not sent. Google processes this request under its own terms and privacy policy. Do not select sensitive personal text.

ParleSprint does not run a server for translation and does not receive these requests.

Explain in context (optional)

When you press Explain in context, the selected French word or phrase, the caption line it came from and your chosen level (A1 to B2) are sent to a ParleSprint Supabase function, which asks Google's Gemini service for a short explanation. The request also carries the random installation identifier, which the function hashes to apply a daily limit per installation. No account, name, email, video URL or video ID is sent. The explanation is returned to you, cached on your device, and also cached on the server keyed only by a hash of the text, so the same explanation is not generated twice. Do not select sensitive personal text.

Live captions for videos without captions (optional)

This feature is off unless you open the extension popup, accept a separate audio notice, and choose Start live captions on this tab. Chrome then lets the extension capture the audio of that one tab. The sound keeps playing for you. Your microphone is not used and no video frames are captured.

While live captions run, the tab audio is streamed directly from your browser to Google's Gemini Live transcription service. Raw audio is not sent to or stored by ParleSprint. To start a session, the extension asks a ParleSprint Supabase function for a short-lived, single-use Google session token. That request contains your consent flag. The Google API key stays on the server and never enters the extension. ParleSprint does not receive or store the audio.

Google's Gemini API terms depend on whether a service is unpaid or paid. Content submitted through unpaid services may be used to improve Google products, and people may review it. Do not use live captions with sensitive or confidential audio. Capture stops when you press Stop or close the tab.

Live transcripts are kept in Chrome's local extension storage under a hash of the page address. Daily limits apply per installation and across all users.

What is stored on your device

Preferences, saved vocabulary (words or phrases, the sentence they came from, your level and the save time), cached captions and live transcripts stay in Chrome's local extension storage. You can delete saved words in the extension. Uninstalling the extension removes all of it. Export your vocabulary first if you want to keep it.

No accounts, analytics or ads

This version has no sign-in and no accounts. It contains no analytics, advertising or sale of personal information, and does not send a browsing history feed. Chrome, YouTube, Google and Supabase process network data under their own policies.

Your choices and contact

You can turn captions off on videos, stop live captions, withdraw audio consent and delete saved words at any time from the extension. Requests already processed by Google cannot be recalled by ParleSprint. If you choose Send feedback, your email app opens a message to thoufeekbaber1@gmail.com; nothing is sent automatically. For privacy questions contact thoufeekbaber1@gmail.com.

Provider policies: Google Translate terms (https://policies.google.com/terms), Google privacy policy (https://policies.google.com/privacy), Gemini API terms (https://ai.google.dev/gemini-api/terms), Supabase privacy (https://supabase.com/privacy).
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
