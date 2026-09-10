import type { Metadata } from "next";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";

export const metadata: Metadata = {
  title: "Support | ParleSprint",
  description: "Get help with your ParleSprint account, learning data, privacy, or subscription.",
  alternates: { canonical: "/support" },
};

const CONTACT_EMAIL = "thoufeek@agiventures.ca";

export default function SupportPage() {
  return (
    <main className="min-h-screen bg-[#F8F9FA] font-sans">
      <SiteNav />
      <section className="pt-16 pb-24 px-6 max-w-3xl mx-auto">
        <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">Support</div>
        <h1 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight leading-tight mb-4">We&apos;re here to help.</h1>
        <p className="text-lg text-[#33383F] leading-relaxed">Contact us for account help, a privacy or deletion request, a subscription question, or a problem with a lesson. Please include the email address on your account and a short description of what happened.</p>
        <a className="mt-8 inline-flex rounded-full bg-[#007BFF] px-6 py-3 text-lg font-bold text-white hover:bg-[#0062CC]" href={"mailto:" + CONTACT_EMAIL}>Email {CONTACT_EMAIL}</a>
        <p className="mt-8 text-lg text-[#33383F] leading-relaxed">Read the <a className="text-[#007BFF] font-semibold hover:underline" href="/privacy">Privacy Policy</a> or <a className="text-[#007BFF] font-semibold hover:underline" href="/terms">Terms of Service</a> for more information.</p>
      </section>
      <SiteFooter />
    </main>
  );
}
