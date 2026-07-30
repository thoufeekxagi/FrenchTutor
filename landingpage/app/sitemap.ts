import type { MetadataRoute } from "next";
import { getSortedPosts } from "./blog/data";
import { stories, getStoryUpdatesSorted } from "./stories/data";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export default function sitemap(): MetadataRoute.Sitemap {
  const posts = getSortedPosts();
  return [
    { url: siteUrl, lastModified: new Date(), changeFrequency: "weekly", priority: 1 },
    { url: `${siteUrl}/blog`, lastModified: new Date(), changeFrequency: "daily", priority: 0.8 },
    ...posts.map((post) => ({
      url: `${siteUrl}/blog/${post.slug}`,
      lastModified: new Date(post.date),
      changeFrequency: "monthly" as const,
      priority: 0.7,
    })),
    { url: `${siteUrl}/stories`, lastModified: new Date(), changeFrequency: "weekly", priority: 0.8 },
    ...stories.map((story) => ({
      url: `${siteUrl}/stories/${story.slug}`,
      lastModified: new Date(getStoryUpdatesSorted(story)[0]?.date ?? Date.now()),
      changeFrequency: "weekly" as const,
      priority: 0.7,
    })),
  ];
}
