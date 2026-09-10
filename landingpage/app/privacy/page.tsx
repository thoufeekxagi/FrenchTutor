import type { Metadata } from "next";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";

const title = "Privacy Policy | ParleSprint";
const description = "How ParleSprint collects, uses, protects, and deletes information used to provide personalized French learning.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/privacy" },
  openGraph: { type: "website", url: "/privacy", siteName: "ParleSprint", title, description },
};

const LAST_UPDATED = "September 9, 2026";
const CONTACT_EMAIL = "thoufeek@agiventures.ca";

function H2({ children }: { children: React.ReactNode }) {
  return <h2 className="mt-12 text-2xl md:text-3xl font-extrabold text-[#1C1E21] tracking-tight">{children}</h2>;
}

function P({ children }: { children: React.ReactNode }) {
  return <p className="mt-4 text-lg text-[#33383F] leading-relaxed">{children}</p>;
}

function Ul({ children }: { children: React.ReactNode }) {
  return <ul className="mt-4 flex flex-col gap-3 pl-1">{children}</ul>;
}

function Li({ children }: { children: React.ReactNode }) {
  return (
    <li className="flex items-start gap-3 text-lg text-[#33383F] leading-relaxed">
      <span className="mt-3 h-1.5 w-1.5 rounded-full bg-[#007BFF] shrink-0" />
      <span>{children}</span>
    </li>
  );
}

export default function PrivacyPolicyPage() {
  return (
    <main className="min-h-screen bg-[#F8F9FA] font-sans">
      <SiteNav />
      <section className="pt-16 pb-24 px-6 max-w-3xl mx-auto">
        <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">Privacy policy</div>
        <h1 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight leading-tight mb-4">How ParleSprint handles your data.</h1>
        <p className="text-lg text-[#6b7280] font-medium">Last updated: {LAST_UPDATED}</p>

        <P>
          ParleSprint (&ldquo;ParleSprint,&rdquo; &ldquo;we,&rdquo; &ldquo;us&rdquo;) is a personalized French-learning
          app and website. This policy explains what information we use, why we use it, which service providers help
          us, how long we keep it, and how you can ask us to delete it. We do not sell your personal information or
          use it for advertising profiles.
        </P>

        <H2>The short version</H2>
        <Ul>
          <Li>We use your account, learning activity, and selected practice content to provide and personalize ParleSprint.</Li>
          <Li>When you choose voice, text, photo, document, or generated-image features, the relevant content is sent to the provider needed for that feature.</Li>
          <Li>We use service analytics and diagnostics to understand reliability and feature use, not to sell advertising profiles.</Li>
          <Li>You can delete your account in the app or contact us. We will complete the request within 30 days, subject to limited legal or security retention.</Li>
        </Ul>

        <H2>Information we collect</H2>
        <P><strong>Account and profile information.</strong> This may include your email address, name if you choose to share it, sign-in method, language level, goals, tutor preferences, and settings. Apple, Google, or email sign-in helps us create and secure your account; we do not receive your Apple or Google password.</P>
        <P><strong>Learning activity.</strong> We save lessons, answers, written work, vocabulary and grammar progress, review history, transcripts, feedback, generated lesson content, streaks, and related completion details so ParleSprint can remember what you have studied and make future practice relevant.</P>
        <P><strong>Voice, photos, and documents.</strong> If you use speaking or live tutor features, microphone audio is sent during the session to provide the requested response and may be transcribed into a practice record. If you choose a photo, scan, or PDF, we process that item only to provide the explanation or exercise you requested. We do not access your photo library or microphone without the relevant device permission and your action.</P>
        <P><strong>Generated media.</strong> Some lessons may include generated illustrations or audio. The lesson instructions and limited context needed to create that media may be sent to an image or audio-generation provider. We do not send your entire account or unrelated history for media generation.</P>
        <P><strong>Device, usage, and diagnostics.</strong> We may receive basic device, app-version, crash, security, and feature-use information. The app may use product analytics when configured, and the website may use optional analytics measurement. These tools help us improve reliability and understand which features are useful; they are not used to create advertising profiles.</P>

        <H2>How we use information</H2>
        <Ul>
          <Li>Provide lessons, speaking practice, reading, listening, writing, vocabulary, grammar, reviews, and feedback.</Li>
          <Li>Remember your progress and personalize future lessons, warm-ups, and reviews.</Li>
          <Li>Process voice, text, images, documents, and generated media when you choose those features.</Li>
          <Li>Secure accounts, prevent abuse, troubleshoot failures, respond to support requests, and maintain the service.</Li>
          <Li>Process subscriptions and restore purchases through the relevant app store and billing services.</Li>
        </Ul>

        <H2>Service providers we use</H2>
        <P>We share only the information needed for a requested feature with service providers that help us operate ParleSprint. They process information on our instructions, under contracts or service terms that require appropriate confidentiality and security protections consistent with this policy and applicable law.</P>
        <Ul>
          <Li><strong>Google Gemini and Gemini Live</strong> help provide text, voice, transcription, image-understanding, and live tutor responses.</Li>
          <Li><strong>OpenRouter and the model providers it routes to, including OpenAI where applicable,</strong> help provide selected lesson, review, grading, and language-generation features.</Li>
          <Li><strong>ElevenLabs</strong> may provide selected narration or audio-generation features when those features are enabled.</Li>
          <Li><strong>MiniMax or another designated image-generation provider</strong> may receive a short lesson description or image prompt to create an illustration requested by the app.</Li>
          <Li><strong>Supabase</strong> provides account authentication, secure storage, and synchronization of account and learning data.</Li>
          <Li><strong>Apple, Google, and billing providers such as RevenueCat when enabled</strong> help with sign-in, subscriptions, payments, and purchase restoration.</Li>
          <Li><strong>PostHog and optional website analytics</strong> may receive limited app interaction and technical data when enabled, to measure performance and improve the product.</Li>
        </Ul>
        <P>We do not sell your information, share it with data brokers, or authorize service providers to use your learning content for advertising or unrelated profiling. We do not use your learning content to train our own general-purpose model. Third-party providers may retain limited request data for security, abuse prevention, billing, or legal compliance under their applicable terms; we do not authorize unrelated model training. If a feature requires a materially different use, we will explain it before the content is sent.</P>

        <H2>International processing</H2>
        <P>Our providers and their infrastructure may process information in Canada, the United States, the European Union, or other countries where they operate. When information leaves your country, we use contractual, technical, and organizational safeguards required by applicable privacy law and require providers to protect it consistently with this policy.</P>

        <H2>How long we keep information</H2>
        <P>We keep account and learning records while your account is active so the app can remember your progress. We keep transcripts, answers, feedback, and generated lesson history until you delete them or delete your account, unless a longer period is needed for security, fraud prevention, legal obligations, or dispute resolution. Provider requests may remain temporarily in provider logs or safety systems under their service terms, after which they are deleted or de-identified according to those terms.</P>

        <H2>Deletion and your choices</H2>
        <Ul>
          <Li><strong>Delete your account:</strong> in the app, open Settings &rarr; Account &rarr; Delete Account. This starts deletion of your account, synced learning data, and associated records.</Li>
          <Li><strong>Ask by email:</strong> contact <a className="text-[#007BFF] font-semibold hover:underline" href={"mailto:" + CONTACT_EMAIL}>{CONTACT_EMAIL}</a> from the account email where possible. We will verify the request and complete it within 30 days.</Li>
          <Li><strong>Control optional features:</strong> you can decline microphone, camera, photo, or document permissions and choose not to use the related features. Some features cannot work without the content needed to provide them.</Li>
          <Li><strong>Privacy rights:</strong> depending on where you live, you may have rights to access, correct, delete, restrict, object to, or receive a copy of your personal information. Contact us to exercise them.</Li>
        </Ul>
        <P>Deletion may not remove information that we must keep by law or that remains in encrypted backups until the normal backup cycle expires. We do not restore deleted learning records to an active account.</P>

        <H2>Children</H2>
        <P>ParleSprint is not directed to children under 13, and we do not knowingly collect personal information from children under 13. If you believe a child has created an account, contact us and we will investigate and delete the account where appropriate.</P>

        <H2>Security</H2>
        <P>We use access controls, authentication, encryption in transit, and other reasonable safeguards designed to protect information. No internet service can guarantee absolute security, so please use a unique password and contact us promptly if you believe your account is at risk.</P>

        <H2>Changes to this policy</H2>
        <P>We may update this policy as ParleSprint changes. If we materially change what information is sent to an AI or other service provider, we will update this page and provide an in-app notice or consent request when required.</P>

        <H2>Contact</H2>
        <P>Questions, privacy requests, or deletion requests: <a className="text-[#007BFF] font-semibold hover:underline" href={"mailto:" + CONTACT_EMAIL}>{CONTACT_EMAIL}</a>. You can also visit our <a className="text-[#007BFF] font-semibold hover:underline" href="/support">support page</a>.</P>
      </section>
      <SiteFooter />
    </main>
  );
}
