import type {Metadata} from "next";
import {SiteFooter} from "../../SiteFooter";
import {SiteNav} from "../../SiteNav";

export const metadata: Metadata = {
  title: "ParleSprint Immersion Privacy Policy",
  description: "How ParleSprint Immersion handles video captions, audio transcription, translations, explanations, accounts and saved vocabulary.",
  alternates: {canonical: "/extension/privacy"},
};

const sections = [
  {
    title: "Captions and saved learning data",
    body: "When available, captions exposed by a video page can be shown in the extension. Imported SRT/VTT subtitle files are processed locally. Preferences, cached captions, transcripts and saved vocabulary are stored in Chrome's local extension storage. They are not sent to ParleSprint for storage. You can delete local data or uninstall the extension to remove it; export vocabulary first if you want to keep it.",
  },
  {
    title: "Live transcription",
    body: "Live captions are off by default. They start only after you accept the in-extension audio notice and choose to start captions for the active tab. Chrome captures that tab's audio; the microphone and video frames are not used. The audio stream goes directly from the extension to Google's Gemini Live service. ParleSprint does not receive or store the raw audio. A ParleSprint service issues a short-lived, single-use Google session token and applies daily limits using a random installation identifier and network IP address stored only as salted hashes. Google's handling depends on whether the API service is unpaid or paid. Review Google's current terms and the in-extension notice, and do not use the feature with sensitive or confidential audio.",
  },
  {
    title: "Translations and AI explanations",
    body: "When English translation is enabled or you select text for a meaning, the French text or caption lines are sent to Google Translate. When you request an AI explanation, the selected phrase, nearby caption context and learning level are sent to ParleSprint's Supabase service and Google Gemini. This feature requires you to connect a ParleSprint account. The request uses your account session; service limits may also use a random installation identifier and IP address as salted hashes. The service caches generated explanations by a hash of the request to avoid regenerating the same answer. The video URL and raw audio are not sent with an explanation request.",
  },
  {
    title: "Accounts and security",
    body: "You can use local learning features without signing in. If you connect an account for AI explanations, Supabase processes your sign-in information. The extension keeps the session tokens and display-only account details in Chrome's local extension storage so you can stay signed in. Signing out removes the local session. Network requests use HTTPS. Provider services process information under their own terms and privacy policies.",
  },
  {
    title: "What is not collected",
    body: "The extension does not use your microphone, capture video frames, or send a browsing-history feed. It does not use advertising or analytics. The extension is independently developed and is not affiliated with YouTube or Google. Captions, translations and AI responses may be inaccurate.",
  },
  {
    title: "Your choices and contact",
    body: "You can decline or withdraw live-audio consent, stop a live session, turn translation off, sign out, and delete local vocabulary at any time. Data already processed by Google cannot be recalled by ParleSprint. For privacy questions, contact thoufeekbaber1@gmail.com.",
  },
];

export default function ExtensionPrivacyPage() {
  return <><SiteNav/><main id="main-content" className="page-shell site-container"><header className="page-intro"><p className="eyebrow">PARLESPRINT IMMERSION</p><h1>Privacy policy</h1><p>Updated October 19, 2026. This policy explains how the Chrome extension handles learning data and optional live transcription.</p></header><article className="mx-auto max-w-3xl pb-24">{sections.map((section) => <section className="mt-10 border-t border-slate-200 pt-8" key={section.title}><h2 className="text-2xl font-semibold">{section.title}</h2><p className="mt-4 leading-7 text-slate-700">{section.body}</p></section>)}<section className="mt-10 border-t border-slate-200 pt-8"><h2 className="text-2xl font-semibold">Provider policies</h2><p className="mt-4 leading-7 text-slate-700"><a href="https://policies.google.com/privacy">Google Privacy Policy</a> · <a href="https://ai.google.dev/gemini-api/terms">Gemini API terms</a> · <a href="https://supabase.com/privacy">Supabase privacy</a>.</p></section></article></main><SiteFooter/></>;
}
