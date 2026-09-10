import type { Metadata } from "next";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";

const title = "Terms of Service | ParleSprint";
const description = "The terms that govern your use of ParleSprint, the personalized French-learning service.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/terms" },
  openGraph: { type: "website", url: "/terms", siteName: "ParleSprint", title, description },
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

export default function TermsPage() {
  return (
    <main className="min-h-screen bg-[#F8F9FA] font-sans">
      <SiteNav />
      <section className="pt-16 pb-24 px-6 max-w-3xl mx-auto">
        <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">Terms of service</div>
        <h1 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight leading-tight mb-4">The terms for using ParleSprint.</h1>
        <p className="text-lg text-[#6b7280] font-medium">Last updated: {LAST_UPDATED}</p>

        <P>These terms govern your use of the ParleSprint app and website (&ldquo;ParleSprint,&rdquo; &ldquo;we,&rdquo; &ldquo;us&rdquo;). By creating an account or using the service, you agree to these terms. Our <a className="text-[#007BFF] font-semibold hover:underline" href="/privacy">Privacy Policy</a> explains how we handle information.</P>

        <H2>The service</H2>
        <P>ParleSprint provides personalized French lessons and practice, including speaking, listening, reading, writing, vocabulary, grammar, reviews, and generated learning material. Some responses, feedback, audio, and images are created with third-party AI services. AI content can be incomplete, incorrect, or unsuitable for a particular situation, so use your judgment and report problems to us.</P>

        <H2>Your account</H2>
        <Ul>
          <Li>You must be at least 13 years old to create an account or use an account created for you.</Li>
          <Li>You are responsible for keeping your account access secure and for activity under your account.</Li>
          <Li>Information in your profile and learning history should be accurate enough for the service to personalize your practice.</Li>
          <Li>You may delete your account at any time as described in our Privacy Policy.</Li>
        </Ul>

        <H2>Your content</H2>
        <P>You retain rights to the text, audio, images, documents, and other material you submit. You give us a limited, non-exclusive permission to process that material only as needed to provide, secure, support, and improve ParleSprint, including sending it to the service providers described in our Privacy Policy. We do not sell your content.</P>
        <P>Do not submit material that you do not have permission to use, confidential information that should not be processed by an online service, or personal information about another person without a lawful reason and their permission.</P>

        <H2>AI-generated learning content</H2>
        <P>ParleSprint is a learning and practice tool, not a certified language instructor, official TEF or TCF authority, immigration adviser, legal adviser, medical adviser, or guarantee of an exam or immigration result. Check important language, exam, professional, or legal information with an appropriate human or official source.</P>

        <H2>Acceptable use</H2>
        <P>You agree not to:</P>
        <Ul>
          <Li>Use ParleSprint unlawfully, to harm another person, or to generate exploitative or abusive content.</Li>
          <Li>Attempt to extract, abuse, resell, or reverse-engineer access to the service or its underlying AI services.</Li>
          <Li>Interfere with the service, bypass limits, probe security, or access another user&apos;s account or data.</Li>
          <Li>Upload malware or content that infringes another person&apos;s rights.</Li>
        </Ul>
        <P>We may limit or suspend access when reasonably necessary to protect users, providers, the service, or legal compliance. If the AI tutor produces an inappropriate result, use the in-app report option or email <a className="text-[#007BFF] font-semibold hover:underline" href={"mailto:" + CONTACT_EMAIL}>{CONTACT_EMAIL}</a>.</P>

        <H2>Subscriptions and purchases</H2>
        <P>Some features may be free and others may require a subscription or purchase. Prices, duration, renewal, and trial terms are shown before purchase. Apple App Store or Google Play manages the transaction, billing, renewal, cancellation, and refunds according to its terms and policies. You are responsible for reviewing those terms before purchasing.</P>

        <H2>Permissions and third-party services</H2>
        <P>Features such as speaking, live tutoring, photo understanding, document explanation, and generated audio or images may require device permissions and third-party services. You control whether to grant those permissions. If you decline a permission, the related feature may not work. Our Privacy Policy describes the categories of providers and information used.</P>

        <H2>Availability and disclaimers</H2>
        <P>We work to keep ParleSprint useful and available, but the service may change, be interrupted, or depend on third-party networks and providers. To the extent permitted by law, ParleSprint is provided on an &ldquo;as is&rdquo; and &ldquo;as available&rdquo; basis without a promise of uninterrupted service, error-free content, or a particular learning outcome.</P>

        <H2>Changes and termination</H2>
        <P>We may update these terms as the service changes. We will post the updated terms and, when a change is material, provide an in-app or other appropriate notice before it takes effect. You may stop using the service at any time. We may suspend or terminate access for a serious or repeated violation of these terms, legal requirements, or security reasons.</P>

        <H2>Contact</H2>
        <P>Questions about these terms: <a className="text-[#007BFF] font-semibold hover:underline" href={"mailto:" + CONTACT_EMAIL}>{CONTACT_EMAIL}</a>. For account, privacy, or deletion requests, visit our <a className="text-[#007BFF] font-semibold hover:underline" href="/support">support page</a>.</P>
      </section>
      <SiteFooter />
    </main>
  );
}
