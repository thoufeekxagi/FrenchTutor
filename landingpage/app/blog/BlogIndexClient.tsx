"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { ArrowRight, Search } from "lucide-react";
import type { BlogPost } from "./data";

export function BlogIndexClient({ posts }: { posts: BlogPost[] }) {
  const [query, setQuery] = useState("");
  const [activeCategory, setActiveCategory] = useState<string | null>(null);

  const categories = useMemo(() => Array.from(new Set(posts.map((p) => p.category))), [posts]);
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return posts.filter((post) => {
      const matchesCategory = !activeCategory || post.category === activeCategory;
      const matchesQuery =
        !q ||
        post.title.toLowerCase().includes(q) ||
        post.description.toLowerCase().includes(q) ||
        post.keywords.some((k) => k.toLowerCase().includes(q));
      return matchesCategory && matchesQuery;
    });
  }, [posts, query, activeCategory]);

  const featured = filtered[0];
  const showFeatured = Boolean(featured && !query.trim() && !activeCategory);
  const visiblePosts = showFeatured ? filtered.slice(1) : filtered;
  const formatDate = (date: string) => new Intl.DateTimeFormat("en-CA", { month: "short", day: "numeric", year: "numeric" }).format(new Date(`${date}T12:00:00`));

  return (
    <div className="journal-feed">
      <div className="journal-controls">
        <label className="journal-search">
          <Search aria-hidden="true" />
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label="Search the ParleSprint journal"
            placeholder="Search French, TCF Canada, speaking…"
          />
        </label>
      </div>

      <div className="journal-topics" role="group" aria-label="Filter journal by topic">
        <button
          type="button"
          onClick={() => setActiveCategory(null)}
          aria-pressed={activeCategory === null}
        >
          All topics
        </button>
        {categories.map((cat) => (
          <button
            key={cat}
            type="button"
            onClick={() => setActiveCategory(cat)}
            aria-pressed={activeCategory === cat}
          >
            {cat}
          </button>
        ))}
      </div>

      {showFeatured && featured && (
        <Link
          href={`/blog/${featured.slug}`}
          className="journal-featured"
        >
          <div className="journal-featured-copy">
            <div className="journal-meta"><span className="journal-latest">Latest article</span><span>{featured.category}</span><span>{formatDate(featured.date)}</span><span>{featured.readingTime}</span></div>
            <h2>{featured.title}</h2>
            <p>{featured.description}</p>
            <span className="journal-read-link">Read the article <ArrowRight aria-hidden="true" /></span>
          </div>
          <div className="journal-featured-note" aria-hidden="true"><span>PARLESPRINT<br />JOURNAL</span><strong>French for<br />real life.</strong><small>Ideas you can use today</small></div>
        </Link>
      )}

      {visiblePosts.length === 0 ? (
        <p className="journal-empty">
          No articles match that search yet. Try a different word, or clear the filter.
        </p>
      ) : (
        <div className="journal-post-grid">
          {visiblePosts.map((post) => (
            <Link
              key={post.slug}
              href={`/blog/${post.slug}`}
              className="journal-card"
            >
              <div className="journal-meta"><span>{post.category}</span><span>{formatDate(post.date)}</span><span>{post.readingTime}</span></div>
              <h3>{post.title}</h3>
              <p>{post.description}</p>
              <span className="journal-read-link">Read the article <ArrowRight aria-hidden="true" /></span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
