"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { ArrowRight, Search } from "lucide-react";
import type { BlogPost } from "./data";

export function BlogIndexClient({ posts }: { posts: BlogPost[] }) {
  const [query, setQuery] = useState("");
  const [activeCategory, setActiveCategory] = useState<string | null>(null);

  const categories = useMemo(() => Array.from(new Set(posts.map((p) => p.category))), [posts]);
  const [featured, ...rest] = posts;

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rest.filter((post) => {
      const matchesCategory = !activeCategory || post.category === activeCategory;
      const matchesQuery =
        !q ||
        post.title.toLowerCase().includes(q) ||
        post.description.toLowerCase().includes(q) ||
        post.keywords.some((k) => k.toLowerCase().includes(q));
      return matchesCategory && matchesQuery;
    });
  }, [rest, query, activeCategory]);

  const showFeatured = !query.trim() && !activeCategory;

  return (
    <>
      <div className="flex flex-col sm:flex-row gap-4 mb-10">
        <div className="relative flex-1">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-[#9ca3af]" />
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search articles (TEF, Quebec, speaking practice...)"
            className="w-full rounded-full border border-[#e5e7eb] bg-white pl-12 pr-5 py-3.5 text-[#1C1E21] font-medium outline-none focus:border-[#007BFF] focus:ring-2 focus:ring-[#007BFF]/15 placeholder:text-[#9ca3af]"
          />
        </div>
      </div>

      <div className="flex flex-wrap gap-2 mb-14">
        <button
          type="button"
          onClick={() => setActiveCategory(null)}
          className={`rounded-full px-4 py-2 text-sm font-bold transition-colors ${
            activeCategory === null ? "bg-[#1C1E21] text-white" : "bg-white border border-[#e5e7eb] text-[#33383F] hover:border-[#007BFF]/40"
          }`}
        >
          All topics
        </button>
        {categories.map((cat) => (
          <button
            key={cat}
            type="button"
            onClick={() => setActiveCategory(cat)}
            className={`rounded-full px-4 py-2 text-sm font-bold transition-colors ${
              activeCategory === cat ? "bg-[#1C1E21] text-white" : "bg-white border border-[#e5e7eb] text-[#33383F] hover:border-[#007BFF]/40"
            }`}
          >
            {cat}
          </button>
        ))}
      </div>

      {showFeatured && featured && (
        <Link
          href={`/blog/${featured.slug}`}
          className="group block rounded-3xl bg-white border border-[#e5e7eb] p-8 md:p-10 mb-10 hover:border-[#007BFF]/40 hover:shadow-md transition-all"
        >
          <div className="flex flex-wrap items-center gap-3 mb-4 text-xs font-bold uppercase tracking-widest">
            <span className="rounded-full bg-[#e5f1ff] text-[#007BFF] px-3 py-1">Latest</span>
            <span className="text-[#007BFF]">{featured.category}</span>
            <span className="text-[#9ca3af]">&middot;</span>
            <span className="text-[#9ca3af]">{featured.readingTime}</span>
          </div>
          <h2 className="text-2xl md:text-3xl font-extrabold text-[#1C1E21] tracking-tight mb-3 group-hover:text-[#007BFF] transition-colors max-w-2xl">
            {featured.title}
          </h2>
          <p className="text-lg text-[#6b7280] leading-relaxed mb-4 max-w-2xl">{featured.description}</p>
          <span className="inline-flex items-center gap-2 text-sm font-bold text-[#007BFF]">
            Read the article <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
          </span>
        </Link>
      )}

      {(showFeatured ? rest : filtered).length === 0 ? (
        <p className="text-center text-lg text-[#6b7280] py-16">
          No articles match that search yet. Try a different word, or clear the filter.
        </p>
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6 justify-center">
          {(showFeatured ? rest : filtered).map((post) => (
            <Link
              key={post.slug}
              href={`/blog/${post.slug}`}
              className="group flex flex-col rounded-3xl bg-white border border-[#e5e7eb] p-7 hover:border-[#007BFF]/40 hover:shadow-md transition-all"
            >
              <div className="flex flex-wrap items-center gap-2 mb-4 text-xs font-bold uppercase tracking-widest">
                <span className="text-[#007BFF]">{post.category}</span>
                <span className="text-[#9ca3af]">&middot;</span>
                <span className="text-[#9ca3af]">{post.readingTime}</span>
              </div>
              <h3 className="text-lg font-extrabold text-[#1C1E21] tracking-tight mb-3 group-hover:text-[#007BFF] transition-colors">
                {post.title}
              </h3>
              <p className="text-[#6b7280] leading-relaxed mb-4 flex-1">{post.description}</p>
              <span className="inline-flex items-center gap-2 text-sm font-bold text-[#007BFF]">
                Read the article <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
              </span>
            </Link>
          ))}
        </div>
      )}
    </>
  );
}
