import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, ArrowRight } from "lucide-react";
import { SiteNav } from "../../SiteNav";
import { SiteFooter } from "../../SiteFooter";
import { BlogProse } from "../BlogProse";
import { PostFeedback } from "../PostFeedback";
import { getAllSlugs, getPostBySlug, getSortedPosts } from "../data";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export function generateStaticParams() {
  return getAllSlugs().map((slug) => ({ slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const post = getPostBySlug(slug);
  if (!post) return {};

  return {
    title: `${post.title} | ParleSprint`,
    description: post.description,
    keywords: post.keywords,
    alternates: { canonical: `/blog/${post.slug}` },
    openGraph: {
      type: "article",
      url: `/blog/${post.slug}`,
      siteName: "ParleSprint",
      title: post.title,
      description: post.description,
      publishedTime: post.date,
    },
    twitter: { card: "summary_large_image", title: post.title, description: post.description },
  };
}

export default async function BlogPostPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = getPostBySlug(slug);
  if (!post) notFound();

  const related = getSortedPosts()
    .filter((p) => p.slug !== post.slug)
    .slice(0, 2);

  const structuredData = {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: post.title,
    description: post.description,
    datePublished: post.date,
    dateModified: post.date,
    author: { "@type": "Organization", name: "ParleSprint", url: siteUrl },
    publisher: { "@type": "Organization", name: "ParleSprint", url: siteUrl, logo: `${siteUrl}/icon-512.png` },
    mainEntityOfPage: `${siteUrl}/blog/${post.slug}`,
  };

  return (
    <main id="main-content" className="journal-page">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }}
      />

      <SiteNav />

      <article className="journal-article">
        <Link
          href="/blog"
          className="inline-flex items-center gap-2 text-sm font-bold text-[#007BFF] mb-8 hover:gap-3 transition-all"
        >
          <ArrowLeft className="w-4 h-4" /> Back to the blog
        </Link>

        <div className="journal-meta">
          <span className="text-[#007BFF]">{post.category}</span>
          <span>{new Intl.DateTimeFormat("en-CA", { month: "short", day: "numeric", year: "numeric" }).format(new Date(`${post.date}T12:00:00`))}</span>
          <span>{post.readingTime}</span>
        </div>

        <h1>{post.title}</h1>

        <BlogProse content={post.content} />

        <div className="journal-article-cta mt-14 rounded-3xl p-8 md:p-10 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
          <p className="text-lg font-medium text-[#d1d5db] max-w-md">
            Ready to put one useful French idea into practice today?
          </p>
          <Link
            href="/today"
            className="shrink-0 bg-[#007BFF] hover:bg-[#0062CC] text-white px-6 py-3 rounded-full font-bold text-sm transition-all flex items-center gap-2"
          >
            Try free practice <ArrowRight className="w-4 h-4" />
          </Link>
        </div>

        <PostFeedback slug={post.slug} />
      </article>

      {related.length > 0 && (
        <section className="px-6 max-w-3xl mx-auto pb-24">
          <h2 className="text-sm font-bold uppercase tracking-widest text-[#9ca3af] mb-6">Keep reading</h2>
          <div className="grid gap-4">
            {related.map((r) => (
              <Link
                key={r.slug}
                href={`/blog/${r.slug}`}
                className="group block rounded-2xl bg-white border border-[#e5e7eb] p-6 hover:border-[#007BFF]/40 transition-all"
              >
                <h3 className="text-lg font-bold text-[#1C1E21] group-hover:text-[#007BFF] transition-colors">
                  {r.title}
                </h3>
                <p className="text-sm text-[#6b7280] mt-1">{r.description}</p>
              </Link>
            ))}
          </div>
        </section>
      )}

      <SiteFooter />
    </main>
  );
}
