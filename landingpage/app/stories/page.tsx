import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";
import { stories, getLatestUpdate } from "./data";

const title = "Learner Stories | ParleSprint";
const description =
  "Real, ongoing stories from people learning French with ParleSprint, starting with the founder's own public bet: reach French B2 using only the app he's building.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/stories" },
  openGraph: { type: "website", url: "/stories", siteName: "ParleSprint", title, description },
  twitter: { card: "summary_large_image", title, description },
};

export default function StoriesIndexPage() {
  return (
    <main className="min-h-screen bg-[#F8F9FA] font-sans">
      <SiteNav />

      <section className="pt-16 pb-10 px-6 max-w-6xl mx-auto">
        <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">Learner stories</div>
        <h1 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight leading-tight mb-6 max-w-2xl">
          Real people, learning French, in public.
        </h1>
        <p className="text-xl text-[#6b7280] leading-relaxed max-w-2xl">
          Ongoing, dated progress from real learners, including ParleSprint's own founder, updated as it happens, not
          polished after the fact.
        </p>
      </section>

      <section className="px-6 max-w-6xl mx-auto pb-24">
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6 justify-center">
          {stories.map((story) => {
            const latest = getLatestUpdate(story);
            return (
              <Link
                key={story.slug}
                href={`/stories/${story.slug}`}
                className="group flex flex-col rounded-3xl bg-white border border-[#e5e7eb] p-7 hover:border-[#007BFF]/40 hover:shadow-md transition-all"
              >
                <div className="flex flex-wrap items-center gap-2 mb-4 text-xs font-bold uppercase tracking-widest">
                  <span className="text-[#007BFF]">{story.category}</span>
                  <span className="text-[#9ca3af]">&middot;</span>
                  <span className="text-[#9ca3af]">{story.startingPoint} &rarr; {story.targetLevel}</span>
                </div>
                <h2 className="text-lg font-extrabold text-[#1C1E21] tracking-tight mb-1 group-hover:text-[#007BFF] transition-colors">
                  {story.name}
                </h2>
                <p className="text-sm font-semibold text-[#9ca3af] mb-4">{story.role}</p>
                <p className="text-[#6b7280] leading-relaxed mb-4 flex-1">{story.tagline}</p>
                {latest && (
                  <p className="text-xs font-bold uppercase tracking-widest text-[#9ca3af] mb-4">
                    Latest update: {latest.date}
                  </p>
                )}
                <span className="inline-flex items-center gap-2 text-sm font-bold text-[#007BFF]">
                  Follow the story <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                </span>
              </Link>
            );
          })}
        </div>
      </section>

      <SiteFooter />
    </main>
  );
}
