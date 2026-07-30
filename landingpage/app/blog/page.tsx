import type { Metadata } from "next";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";
import { getSortedPosts } from "./data";
import { BlogIndexClient } from "./BlogIndexClient";

const title = "The ParleSprint Blog | French Learning, TEF/TCF, and Immigration French";
const description =
  "Practical, honest writing on learning French as an adult: TEF and TCF Canada prep, Express Entry French requirements, the SLE oral exam, and why speaking is the skill every other method skips.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/blog" },
  openGraph: { type: "website", url: "/blog", siteName: "ParleSprint", title, description },
  twitter: { card: "summary_large_image", title, description },
};

export default function BlogIndexPage() {
  const posts = getSortedPosts();

  return (
    <main className="min-h-screen bg-[#F8F9FA] font-sans">
      <SiteNav />

      <section className="pt-16 pb-10 px-6 max-w-6xl mx-auto">
        <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">The blog</div>
        <h1 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight leading-tight mb-6 max-w-2xl">
          Honest writing on learning French as an adult.
        </h1>
        <p className="text-xl text-[#6b7280] leading-relaxed max-w-2xl">
          No fluency-in-three-months claims. Real breakdowns of TEF and TCF Canada, Express Entry, the SLE oral exam,
          and the actual gap between reading French and speaking it.
        </p>
      </section>

      <section className="px-6 max-w-6xl mx-auto pb-24">
        <BlogIndexClient posts={posts} />
      </section>

      <SiteFooter />
    </main>
  );
}
