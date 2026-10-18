import type { Metadata } from "next";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";
import { getSortedPosts } from "./data";
import { BlogIndexClient } from "./BlogIndexClient";

const title = "The ParleSprint Journal | French Learning, TEF/TCF, and Canadian Life";
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
    <main id="main-content" className="journal-page">
      <SiteNav />

      <section className="journal-hero">
        <div className="journal-hero-copy">
          <p className="eyebrow">THE PARLESPRINT JOURNAL</p>
          <h1>
          Honest writing on learning French as an adult.
          </h1>
          <p>
          No fluency-in-three-months claims. Real breakdowns of TEF and TCF Canada, Express Entry, the SLE oral exam,
          and the actual gap between reading French and speaking it.
          </p>
        </div>
        <div className="journal-hero-aside"><span>READ · NOTICE · USE</span><strong>Useful French ideas, explained with care.</strong><p>Language, learning and life in Canada, one clear article at a time.</p></div>
      </section>

      <section className="journal-content">
        <BlogIndexClient posts={posts} />
      </section>

      <SiteFooter />
    </main>
  );
}
