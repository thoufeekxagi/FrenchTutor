import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, ArrowRight, Target } from "lucide-react";
import { SiteNav } from "../../SiteNav";
import { SiteFooter } from "../../SiteFooter";
import { BlogProse } from "../../blog/BlogProse";
import { getAllStorySlugs, getStoryBySlug, getStoryUpdatesSorted } from "../data";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export function generateStaticParams() {
  return getAllStorySlugs().map((slug) => ({ slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const story = getStoryBySlug(slug);
  if (!story) return {};

  return {
    title: `${story.name}'s French Learning Story | ParleSprint`,
    description: story.description,
    keywords: story.keywords,
    alternates: { canonical: `/stories/${story.slug}` },
    openGraph: {
      type: "profile",
      url: `/stories/${story.slug}`,
      siteName: "ParleSprint",
      title: `${story.name}'s French Learning Story`,
      description: story.description,
    },
    twitter: { card: "summary_large_image", title: `${story.name}'s French Learning Story`, description: story.description },
  };
}

export default async function StoryPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const story = getStoryBySlug(slug);
  if (!story) notFound();

  const updates = getStoryUpdatesSorted(story);
  const latest = updates[0];

  const structuredData = {
    "@context": "https://schema.org",
    "@type": "ProfilePage",
    dateModified: latest?.date,
    mainEntityOfPage: `${siteUrl}/stories/${story.slug}`,
    about: { "@type": "Person", name: story.name, jobTitle: story.role },
    description: story.description,
  };

  return (
    <main className="min-h-screen bg-[#F8F9FA] font-sans">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }}
      />

      <SiteNav />

      <article className="px-6 max-w-3xl mx-auto pt-12 pb-10">
        <Link
          href="/stories"
          className="inline-flex items-center gap-2 text-sm font-bold text-[#007BFF] mb-8 hover:gap-3 transition-all"
        >
          <ArrowLeft className="w-4 h-4" /> Back to learner stories
        </Link>

        <div className="flex flex-wrap items-center gap-3 mb-6 text-xs font-bold uppercase tracking-widest">
          <span className="text-[#007BFF]">{story.category}</span>
          <span className="text-[#9ca3af]">&middot;</span>
          <span className="text-[#9ca3af]">{story.startingPoint} &rarr; {story.targetLevel}</span>
        </div>

        <h1 className="text-3xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight leading-tight mb-3">
          {story.name}
        </h1>
        <p className="text-lg font-semibold text-[#9ca3af] mb-6">{story.role}</p>
        <p className="text-xl text-[#33383F] leading-relaxed mb-8">{story.tagline}</p>

        <div className="rounded-3xl bg-[#1C1E21] text-white p-8 md:p-10 flex flex-col sm:flex-row items-start gap-5 mb-14">
          <div className="w-12 h-12 rounded-2xl bg-[rgba(0,123,255,0.15)] text-[#4da3ff] flex items-center justify-center shrink-0">
            <Target className="w-6 h-6" />
          </div>
          <div>
            <p className="text-xs font-bold uppercase tracking-widest text-[#4da3ff] mb-2">The goal</p>
            <p className="text-lg font-medium text-[#d1d5db] leading-relaxed">{story.goal}</p>
          </div>
        </div>

        <div className="flex flex-col gap-14">
          {updates.map((update) => (
            <div key={update.date}>
              <p className="text-xs font-bold uppercase tracking-widest text-[#9ca3af] mb-3">{update.date}</p>
              <h2 className="text-2xl md:text-3xl font-extrabold text-[#1C1E21] tracking-tight mb-6">{update.title}</h2>
              <BlogProse content={update.content} />
            </div>
          ))}
        </div>

        <div className="mt-14 rounded-3xl bg-white border border-[#e5e7eb] p-8 md:p-10 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
          <p className="text-lg font-medium text-[#33383F] max-w-md">
            Want to learn alongside a story like this one, instead of just reading about it?
          </p>
          <Link
            href="/#join"
            className="shrink-0 bg-[#007BFF] hover:bg-[#0062CC] text-white px-6 py-3 rounded-full font-bold text-sm transition-all flex items-center gap-2"
          >
            Join the early list <ArrowRight className="w-4 h-4" />
          </Link>
        </div>
      </article>

      <SiteFooter />
    </main>
  );
}
